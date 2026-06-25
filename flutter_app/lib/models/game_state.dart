import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/bank_interpolator.dart';
import '../engine/physics_engine.dart';
import '../engine/weather_ramp.dart';
import 'broadcast_message.dart';
import 'game_phase.dart';
import 'weather_inputs.dart';

/// The cockpit-authoritative game state. It merges partial controller updates,
/// runs the flight physics during the emergency phase, and exposes smoothed
/// values for the UI to render.
///
/// Time is driven externally: the cockpit screen calls [advance] once per frame
/// with the elapsed delta. Discrete physics is applied in whole-second steps so
/// the sink/approach numbers stay predictable, while weather and bank values are
/// interpolated every frame for smooth visuals.
class GameState extends ChangeNotifier {
  /// How long the malfunction alarm plays before briefing begins. Shared so the
  /// cockpit and controllers advance from malfunction to briefing in step.
  static const Duration malfunctionDuration = Duration(seconds: 7);

  /// Seconds for the distant land to visually approach during cruise.
  static const double _cruiseApproachSeconds = 25.0;

  GamePhase _phase = GamePhase.waiting;
  double _altitude = PhysicsEngine.initialAltitude;
  double _distanceToIsland = PhysicsEngine.initialDistance;
  double _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
  int _counterLeft = 0;
  int _counterRight = 0;
  WeatherInputs _weather = const WeatherInputs();
  double _cruiseProgress = 0.0;

  final WeatherRamp _stormRamp = WeatherRamp(timeToTarget: 12.0);
  final WeatherRamp _windRamp = WeatherRamp(timeToTarget: 8.0);
  final BankInterpolator _bank = BankInterpolator();

  int _peakLeft = 0;
  int _peakRight = 0;
  double _elapsedSeconds = 0.0;
  double _secondAccumulator = 0.0;

  // --- Public read-only state ---

  GamePhase get phase => _phase;
  double get altitude => _altitude;
  double get distanceToIsland => _distanceToIsland;
  double get distanceSpeed => _distanceSpeed;
  int get counterLeft => _counterLeft;
  int get counterRight => _counterRight;
  int get activeTotal => _counterLeft + _counterRight;
  WeatherInputs get weather => _weather;

  /// Cosmetic land-approach progress during cruise, 0..1.
  double get cruiseProgress => _cruiseProgress;

  /// Smoothed bank angle for the artificial horizon, in degrees.
  double get displayBankAngle => _bank.value;

  /// Ramped thunderstorm intensity, 0..1.
  double get stormIntensity => _stormRamp.value;

  /// Ramped wind intensity, 0..1.
  double get windIntensity => _windRamp.value;

  int get peakLeft => _peakLeft;
  int get peakRight => _peakRight;
  int get peakTotal => _peakLeft + _peakRight;
  int get elapsedSeconds => _elapsedSeconds.floor();

  // --- Time-driven simulation ---

  /// Advances the simulation by [dt] seconds. Call once per frame.
  void advance(double dt) {
    _updateRamps(dt);
    _bank.update(target: _targetBankAngle, dt: dt);

    if (_phase == GamePhase.cruise) {
      _cruiseProgress =
          math.min(1.0, _cruiseProgress + dt / _cruiseApproachSeconds);
    }

    if (_phase == GamePhase.emergency) {
      _secondAccumulator += dt;
      while (_secondAccumulator >= 1.0 && _phase == GamePhase.emergency) {
        _secondAccumulator -= 1.0;
        _stepOneSecond();
      }
    }

    notifyListeners();
  }

  void _updateRamps(double dt) {
    final inEmergency = _phase == GamePhase.emergency;
    _stormRamp.update(
      target: inEmergency && _weather.thunderstorm ? 1.0 : 0.0,
      dt: dt,
    );
    final windActive = _weather.windLeft || _weather.windRight;
    _windRamp.update(target: inEmergency && windActive ? 1.0 : 0.0, dt: dt);
  }

  double get _targetBankAngle {
    if (_phase != GamePhase.emergency) return 0.0;
    final windFactor = (_weather.windStrength.value / 100.0) * _windRamp.value;
    final windBank = PhysicsEngine.windBankDegrees(
      windDirection: _weather.windDirection,
      windFactor: windFactor,
    );
    return PhysicsEngine.bankAngle(
      counterLeft: _counterLeft,
      counterRight: _counterRight,
      windBankDegrees: windBank,
    );
  }

  void _stepOneSecond() {
    _elapsedSeconds += 1.0;
    final loss = PhysicsEngine.altitudeLossPerSecond(
      activeTotal: activeTotal,
      stormIntensity: _stormRamp.value,
    );
    _altitude = math.max(0.0, _altitude - loss);
    _distanceToIsland = math.max(0.0, _distanceToIsland - _distanceSpeed);
    if (_altitude <= 0.0) {
      _phase = GamePhase.finished;
    }
  }

  // --- Applying broadcast updates from controllers ---

  void applyCounterUpdate(CounterUpdate update) {
    if (_phase != GamePhase.emergency) return;
    if (update.counterLeft != null) {
      _counterLeft = math.max(0, update.counterLeft!);
    }
    if (update.counterRight != null) {
      _counterRight = math.max(0, update.counterRight!);
    }
    _peakLeft = math.max(_peakLeft, _counterLeft);
    _peakRight = math.max(_peakRight, _counterRight);
    notifyListeners();
  }

  void applyWeatherUpdate(WeatherUpdate update) {
    _weather = update.weather;
    notifyListeners();
  }

  void applySettingsUpdate(SettingsUpdate update) {
    if (_phase != GamePhase.emergency) return;
    _distanceSpeed = update.distanceSpeed;
    notifyListeners();
  }

  /// Applies a controller's phase request, ignoring invalid transitions.
  /// Returns true if the phase changed.
  bool applyPhaseAction(PhaseAction action) {
    final before = _phase;
    switch (action) {
      case PhaseAction.startCruise:
        if (_phase == GamePhase.waiting) _phase = GamePhase.cruise;
      case PhaseAction.engineMalfunction:
        if (_phase == GamePhase.cruise) {
          _phase = GamePhase.malfunction;
          _distanceToIsland = PhysicsEngine.initialDistance;
        }
      case PhaseAction.startEmergency:
        if (_phase == GamePhase.briefing) _phase = GamePhase.emergency;
    }
    if (_phase != before) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Advances from malfunction to briefing once the cockpit alarm sequence ends.
  void enterBriefing() {
    if (_phase == GamePhase.malfunction) {
      _phase = GamePhase.briefing;
      notifyListeners();
    }
  }

  /// Resets everything back to the waiting state (cockpit session cancel).
  void resetToWaiting() {
    _phase = GamePhase.waiting;
    _altitude = PhysicsEngine.initialAltitude;
    _distanceToIsland = PhysicsEngine.initialDistance;
    _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
    _counterLeft = 0;
    _counterRight = 0;
    _weather = const WeatherInputs();
    _cruiseProgress = 0.0;
    _peakLeft = 0;
    _peakRight = 0;
    _elapsedSeconds = 0.0;
    _secondAccumulator = 0.0;
    _stormRamp.reset();
    _windRamp.reset();
    _bank.reset();
    notifyListeners();
  }
}
