import 'dart:math' as math;

import 'physics_engine.dart';

/// Rolls and tracks the thunderstorm's random bank bias over time.
///
/// A new base angle in `[-stormMaxBankDegrees, +stormMaxBankDegrees]` is drawn
/// every [PhysicsEngine.stormBaseIntervalSeconds]; jitter in
/// `[base - stormJitterDegrees, base + stormJitterDegrees]` is re-rolled every
/// [PhysicsEngine.stormJitterIntervalSeconds]. The caller advances timers only
/// while ramped storm intensity is above zero so pauses preserve elapsed time.
class StormBank {
  double _base = 0.0;
  double _jitter = 0.0;
  double _baseElapsed = 0.0;
  double _jitterElapsed = 0.0;
  bool _initialized = false;

  /// Current storm base bank in degrees before intensity scaling.
  double get base => _base;

  /// Current storm jitter in degrees before intensity scaling.
  double get jitter => _jitter;

  /// Advances timers by [dt] seconds and rolls new values when intervals elapse.
  void advance(double dt, math.Random random) {
    if (!_initialized) {
      _rollBase(random);
      _rollJitter(random);
      _initialized = true;
    }

    _jitterElapsed += dt;
    while (_jitterElapsed >= PhysicsEngine.stormJitterIntervalSeconds) {
      _jitterElapsed -= PhysicsEngine.stormJitterIntervalSeconds;
      _rollJitter(random);
    }

    _baseElapsed += dt;
    while (_baseElapsed >= PhysicsEngine.stormBaseIntervalSeconds) {
      _baseElapsed -= PhysicsEngine.stormBaseIntervalSeconds;
      _rollBase(random);
      _rollJitter(random);
    }
  }

  void _rollBase(math.Random random) {
    final range = PhysicsEngine.stormMaxBankDegrees * 2;
    _base = random.nextDouble() * range - PhysicsEngine.stormMaxBankDegrees;
  }

  void _rollJitter(math.Random random) {
    final range = PhysicsEngine.stormJitterDegrees * 2;
    _jitter = _base + random.nextDouble() * range - PhysicsEngine.stormJitterDegrees;
  }

  void reset() {
    _base = 0.0;
    _jitter = 0.0;
    _baseElapsed = 0.0;
    _jitterElapsed = 0.0;
    _initialized = false;
  }
}
