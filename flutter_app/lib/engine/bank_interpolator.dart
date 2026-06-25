import 'physics_engine.dart';

/// Smooths the displayed bank angle between the 1 Hz physics ticks so the
/// artificial horizon rotates fluidly instead of jumping once per second.
class BankInterpolator {
  /// Seconds to reach ~90% of the target angle; tuned just under the 1 s tick.
  static const double _timeToTarget = 0.6;

  double _current = 0.0;

  /// Current displayed bank angle in degrees.
  double get value => _current;

  /// Eases the displayed angle toward [target] degrees by [dt] seconds.
  void update({required double target, required double dt}) {
    _current = PhysicsEngine.approach(
      current: _current,
      target: target,
      dt: dt,
      timeToTarget: _timeToTarget,
    );
  }

  void reset() => _current = 0.0;
}
