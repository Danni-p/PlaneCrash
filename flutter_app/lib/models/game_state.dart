import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/bank_interpolator.dart';
import '../engine/navigation_engine.dart';
import '../engine/physics_engine.dart';
import '../engine/storm_bank.dart';
import '../engine/weather_ramp.dart';
import '../engine/wind_gust.dart';
import 'broadcast_message.dart';
import 'game_phase.dart';
import 'weather_inputs.dart';

/// The cockpit-authoritative game state. It merges partial controller updates,
/// runs the flight physics during the emergency phase, and exposes smoothed
/// values for the UI to render.
///
/// Time is driven externally: the cockpit screen calls [advance] once per frame
/// with the elapsed delta. Altitude and 2D navigation are integrated every frame
/// from that delta, as are the smoothed weather and bank values.
class GameState extends ChangeNotifier {
  /// How long the malfunction alarm plays before briefing begins. Shared so the
  /// cockpit and controllers advance from malfunction to briefing in step.
  static const Duration malfunctionDuration = Duration(seconds: 8);

  /// Default plane/island layout used before the emergency reveals the island.
  /// Plane at the origin, island straight ahead at the starting distance.
  static const NavigationState _initialNav =
      NavigationState(planeX: 0, planeY: 0, headingRad: 0);
  static const math.Point<double> _initialIsland =
      math.Point<double>(0, PhysicsEngine.initialDistance);

  GamePhase _phase = GamePhase.waiting;
  double _altitude = PhysicsEngine.displayCruiseAltitude;
  double _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
  double _bankPerPerson = PhysicsEngine.defaultBankPerPerson;
  int _counterLeft = 0;
  int _counterRight = 0;
  WeatherInputs _weather = const WeatherInputs();

  NavigationState _nav = _initialNav;
  math.Point<double> _island = _initialIsland;
  final math.Random _random = math.Random();

  final WeatherRamp _stormRamp = WeatherRamp(timeToTarget: 12.0);
  final WeatherRamp _windRamp = WeatherRamp(timeToTarget: 8.0);
  final BankInterpolator _bank = BankInterpolator();
  final StormBank _stormBank = StormBank();
  final WindGust _windGust = WindGust();

  int _peakLeft = 0;
  int _peakRight = 0;
  double _elapsedSeconds = 0.0;

  double _runInitialAltitude = PhysicsEngine.defaultRunInitialAltitude;
  bool _initialAltitudeLocked = false;
  double _altitudeCountdownElapsed = 0.0;
  int _altitudeBoostTotal = 0;

  // --- Public read-only state ---

  GamePhase get phase => _phase;
  double get altitude => _altitude;

  /// Configured emergency start altitude for this run (metres).
  double get runInitialAltitude => _runInitialAltitude;

  /// Maximum reachable altitude: run initial plus rescue boost headroom.
  double get maxAltitude =>
      _runInitialAltitude + PhysicsEngine.maxBoostAboveInitial;

  /// Total metres gained via rescue-mission boosts this run.
  int get altitudeBoostTotal => _altitudeBoostTotal;

  /// True during the 3 s intro animation from cruise altitude to run initial.
  bool get isAltitudeCountdownActive =>
      _phase == GamePhase.emergency &&
      _altitudeCountdownElapsed < PhysicsEngine.altitudeCountdownSeconds;

  /// Reference altitude for horizon visuals: cruise display before emergency,
  /// run initial once the emergency landing has begun.
  double get horizonReferenceAltitude =>
      _phase == GamePhase.emergency || _phase == GamePhase.finished
          ? _runInitialAltitude
          : PhysicsEngine.displayCruiseAltitude;

  /// Straight-line distance to the island in metres, derived from the plane's
  /// current map position. Grows when the plane steers away from the island.
  double get distanceToIsland =>
      NavigationEngine.distanceTo(state: _nav, island: _island);

  /// Bearing to the island relative to the plane's heading, in radians and
  /// normalized to `[-pi, pi]`. Zero is dead ahead; positive is to the right.
  double get relativeBearing =>
      NavigationEngine.relativeBearing(state: _nav, island: _island);

  double get distanceSpeed => _distanceSpeed;
  double get bankPerPerson => _bankPerPerson;
  int get counterLeft => _counterLeft;
  int get counterRight => _counterRight;
  int get activeTotal => _counterLeft + _counterRight;
  WeatherInputs get weather => _weather;

  /// Smoothed bank angle for the artificial horizon, in degrees.
  double get displayBankAngle => _bank.value;

  /// Instantaneous target bank before interpolation; useful for debug readouts.
  double get targetBankAngle => _targetBankAngle;

  /// Ramped thunderstorm intensity, 0..1.
  double get stormIntensity => _stormRamp.value;

  /// Ramped wind intensity, 0..1.
  double get windIntensity => _windRamp.value;

  /// Current gust multiplier in 0..1 before strength and ramp scaling.
  double get windGustMultiplier => _windGust.value;

  int get peakLeft => _peakLeft;
  int get peakRight => _peakRight;
  int get peakTotal => _peakLeft + _peakRight;
  int get elapsedSeconds => _elapsedSeconds.floor();

  // --- Time-driven simulation ---

  /// Advances the simulation by [dt] seconds. Call once per frame.
  void advance(double dt) {
    _updateRamps(dt);
    final stormActive = _phase == GamePhase.emergency &&
        !isAltitudeCountdownActive &&
        _weather.thunderstorm &&
        _stormRamp.value > 0;
    if (stormActive) {
      _stormBank.advance(dt, _random);
    }
    final windActive = _phase == GamePhase.emergency &&
        !isAltitudeCountdownActive &&
        (_weather.windLeft || _weather.windRight) &&
        _windRamp.value > 0;
    if (windActive) {
      _windGust.advance(dt, _random);
    }
    _bank.update(target: _targetBankAngle, dt: dt);

    if (_phase == GamePhase.emergency) {
      if (isAltitudeCountdownActive) {
        _advanceAltitudeCountdown(dt);
      } else {
        _stepEmergency(dt);
      }
    }

    notifyListeners();
  }

  void _advanceAltitudeCountdown(double dt) {
    _altitudeCountdownElapsed += dt;
    final duration = PhysicsEngine.altitudeCountdownSeconds;
    final t = (_altitudeCountdownElapsed / duration).clamp(0.0, 1.0);
    _altitude = _lerp(
      PhysicsEngine.displayCruiseAltitude,
      _runInitialAltitude,
      t,
    );
    if (_altitudeCountdownElapsed >= duration) {
      _altitude = _runInitialAltitude;
      _initialAltitudeLocked = true;
    }
  }

  static double _lerp(double from, double to, double t) => from + (to - from) * t;

  void _updateRamps(double dt) {
    final inEmergency = _phase == GamePhase.emergency && !isAltitudeCountdownActive;
    _stormRamp.update(
      target: inEmergency && _weather.thunderstorm ? 1.0 : 0.0,
      dt: dt,
    );
    final windActive = _weather.windLeft || _weather.windRight;
    _windRamp.update(target: inEmergency && windActive ? 1.0 : 0.0, dt: dt);
  }

  double get _targetBankAngle {
    if (_phase != GamePhase.emergency || isAltitudeCountdownActive) return 0.0;
    final maxFactor =
        (_weather.windStrength.value / 100.0) * _windRamp.value;
    final windFactor = maxFactor * _windGust.value;
    final windBank = PhysicsEngine.windBankDegrees(
      windDirection: _weather.windDirection,
      windFactor: windFactor,
    );
    final stormBank = PhysicsEngine.stormBankDegrees(
      baseDegrees: _stormBank.base,
      jitterDegrees: _stormBank.jitter,
      stormIntensity: _stormRamp.value,
    );
    return PhysicsEngine.bankAngle(
      counterLeft: _counterLeft,
      counterRight: _counterRight,
      bankPerPerson: _bankPerPerson,
      windBankDegrees: windBank,
      stormBankDegrees: stormBank,
    );
  }

  /// Integrates altitude and 2D navigation for one frame. Altitude falls at the
  /// crew/storm sink rate; the plane flies at a constant ground speed along its
  /// heading while bank angle turns it. The run ends when altitude hits zero.
  void _stepEmergency(double dt) {
    _elapsedSeconds += dt;
    final loss = PhysicsEngine.altitudeLossPerSecond(
      activeTotal: activeTotal,
      stormIntensity: _stormRamp.value,
    );
    _altitude = math.max(0.0, _altitude - loss * dt);
    _nav = NavigationEngine.step(
      state: _nav,
      bankDegrees: _bank.value,
      groundSpeed: _distanceSpeed,
      turnRatePerBankDegree: PhysicsEngine.turnRatePerBankDegree,
      dt: dt,
    );
    if (_altitude <= 0.0) {
      _phase = GamePhase.finished;
    }
  }

  /// Places the island at a random bearing one [PhysicsEngine.initialDistance]
  /// away and resets the plane to the origin heading north. Called when the
  /// emergency landing begins so each run faces a different direction.
  void _initNavigation() {
    _stormBank.reset();
    _windGust.reset();
    final bearing = _random.nextDouble() * 2 * math.pi;
    _island = NavigationEngine.islandFromBearing(
      bearingRad: bearing,
      distance: PhysicsEngine.initialDistance,
    );
    _nav = _initialNav;
  }

  void _startAltitudeCountdown() {
    _altitudeCountdownElapsed = 0.0;
    _initialAltitudeLocked = false;
    _altitude = PhysicsEngine.displayCruiseAltitude;
  }

  // --- Applying broadcast updates from controllers ---

  void applyCounterUpdate(CounterUpdate update) {
    if (_phase != GamePhase.emergency || isAltitudeCountdownActive) return;
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
    if (update.initialAltitude != null && !_initialAltitudeLocked) {
      _runInitialAltitude = update.initialAltitude!.toDouble();
      if (isAltitudeCountdownActive) {
        final duration = PhysicsEngine.altitudeCountdownSeconds;
        final t =
            (_altitudeCountdownElapsed / duration).clamp(0.0, 1.0);
        _altitude = _lerp(
          PhysicsEngine.displayCruiseAltitude,
          _runInitialAltitude,
          t,
        );
      }
    }
    if (_phase != GamePhase.emergency) return;
    _distanceSpeed = update.distanceSpeed;
    _bankPerPerson = update.bankPerPerson;
    notifyListeners();
  }

  void applyAltitudeBoost(AltitudeBoost update) {
    if (_phase != GamePhase.emergency || isAltitudeCountdownActive) return;
    final cap = maxAltitude;
    final boosted = math.min(
      cap,
      _altitude + PhysicsEngine.altitudeBoostAmount,
    );
    final gained = (boosted - _altitude).round();
    if (gained > 0) {
      _altitude = boosted;
      _altitudeBoostTotal += gained;
      notifyListeners();
    }
  }

  /// Applies a controller's phase request, ignoring invalid transitions.
  /// Returns true if the phase changed.
  bool applyPhaseAction(PhaseAction action) {
    final before = _phase;
    switch (action) {
      case PhaseAction.startCruise:
        if (_phase == GamePhase.waiting) _phase = GamePhase.cruise;
      case PhaseAction.engineMalfunction:
        if (_phase == GamePhase.cruise) _phase = GamePhase.malfunction;
      case PhaseAction.startEmergency:
        if (_phase == GamePhase.briefing) {
          _phase = GamePhase.emergency;
          _initNavigation();
          _startAltitudeCountdown();
        }
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
    _altitude = PhysicsEngine.displayCruiseAltitude;
    _distanceSpeed = PhysicsEngine.defaultDistanceSpeed;
    _bankPerPerson = PhysicsEngine.defaultBankPerPerson;
    _counterLeft = 0;
    _counterRight = 0;
    _weather = const WeatherInputs();
    _nav = _initialNav;
    _island = _initialIsland;
    _peakLeft = 0;
    _peakRight = 0;
    _elapsedSeconds = 0.0;
    _runInitialAltitude = PhysicsEngine.defaultRunInitialAltitude;
    _initialAltitudeLocked = false;
    _altitudeCountdownElapsed = 0.0;
    _altitudeBoostTotal = 0;
    _stormRamp.reset();
    _windRamp.reset();
    _bank.reset();
    _stormBank.reset();
    _windGust.reset();
    notifyListeners();
  }
}
