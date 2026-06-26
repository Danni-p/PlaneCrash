import 'dart:math' as math;

import 'physics_engine.dart';

/// Rolls and eases wind gust intensity over time.
///
/// A new target in `0..1` is drawn every [PhysicsEngine.windGustIntervalSeconds]
/// using a mid-biased distribution; [value] eases toward that target over
/// [PhysicsEngine.windGustApproachSeconds]. The caller advances only while wind
/// is active so pauses preserve elapsed time.
class WindGust {
  double _current = 0.0;
  double _target = 0.0;
  double _elapsed = 0.0;
  bool _initialized = false;

  /// Current gust multiplier in `0..1` before strength and ramp scaling.
  double get value => _current;

  /// The target the gust is easing toward (exposed for tests).
  double get target => _target;

  /// Advances timers by [dt] seconds, rolls new targets when intervals elapse,
  /// and eases [value] toward [_target].
  void advance(double dt, math.Random random) {
    if (!_initialized) {
      _rollTarget(random);
      _current = _target;
      _initialized = true;
    }

    _elapsed += dt;
    while (_elapsed >= PhysicsEngine.windGustIntervalSeconds) {
      _elapsed -= PhysicsEngine.windGustIntervalSeconds;
      _rollTarget(random);
    }

    _current = PhysicsEngine.approach(
      current: _current,
      target: _target,
      dt: dt,
      timeToTarget: PhysicsEngine.windGustApproachSeconds,
    );
  }

  void _rollTarget(math.Random random) {
    _target = PhysicsEngine.midBiasedUnit(random);
  }

  void reset() {
    _current = 0.0;
    _target = 0.0;
    _elapsed = 0.0;
    _initialized = false;
  }
}
