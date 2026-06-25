import 'physics_engine.dart';

/// Smoothly ramps a weather effect's intensity (0..1) toward a target so that
/// toggling weather on the controller does not snap on the cockpit. Wind ramps
/// in over ~8 seconds, a thunderstorm over ~12 seconds.
class WeatherRamp {
  WeatherRamp({required this.timeToTarget});

  /// Seconds to reach ~90% of the target intensity.
  final double timeToTarget;

  double _current = 0.0;

  /// Current ramped intensity, 0..1.
  double get value => _current;

  /// Advances the ramp toward [target] (0..1) by [dt] seconds.
  void update({required double target, required double dt}) {
    _current = PhysicsEngine.approach(
      current: _current,
      target: target,
      dt: dt,
      timeToTarget: timeToTarget,
    );
  }

  void reset() => _current = 0.0;
}
