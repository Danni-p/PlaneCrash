import 'dart:math' as math;

/// Pure flight-physics calculations and the tunable constants that drive them.
///
/// Everything here is stateless so it can be unit tested in isolation; the
/// mutable run state lives in `GameState`.
abstract final class PhysicsEngine {
  /// Starting altitude in metres.
  static const double initialAltitude = 5000.0;

  /// Distance to the island in metres, set when the malfunction reveals it.
  static const double initialDistance = 3000.0;

  /// Altitude lost per second with zero active crew.
  static const double baseSinkRate = 15.0;

  /// Reduction of the per-second sink rate for each active crew member.
  static const double reductionPerPerson = 1.3;

  /// Lower bound on the sink rate; the plane always descends a little.
  static const double minSinkRate = 2.0;

  /// Extra altitude lost per second during a fully-ramped thunderstorm.
  static const double stormMaxBonus = 10.0;

  /// Maximum wind-induced bank bias in degrees at full strength.
  static const double maxWindBankDegrees = 15.0;

  /// Bank degrees contributed per unit of left/right counter difference.
  static const double bankPerCrewDifference = 4.0;

  /// Default island approach speed in metres per second.
  static const double defaultDistanceSpeed = 15.0;

  /// Altitude lost in one second for the given active crew and storm intensity.
  ///
  /// [stormIntensity] is the ramped thunderstorm strength in the range 0..1.
  static double altitudeLossPerSecond({
    required int activeTotal,
    required double stormIntensity,
  }) {
    final base = math.max(minSinkRate, baseSinkRate - activeTotal * reductionPerPerson);
    return base + stormMaxBonus * stormIntensity.clamp(0.0, 1.0);
  }

  /// Wind-induced bank bias in degrees.
  ///
  /// [windDirection] is -1 (left), +1 (right) or 0; [windFactor] folds the
  /// selected strength (0..1) and the ramped intensity (0..1) together.
  static double windBankDegrees({
    required int windDirection,
    required double windFactor,
  }) {
    return windDirection * windFactor.clamp(0.0, 1.0) * maxWindBankDegrees;
  }

  /// Target bank angle in degrees from crew balance plus wind.
  static double bankAngle({
    required int counterLeft,
    required int counterRight,
    required double windBankDegrees,
  }) {
    return (counterLeft - counterRight) * bankPerCrewDifference + windBankDegrees;
  }

  /// Eases [current] toward [target], reaching ~90% after [timeToTarget]
  /// seconds regardless of frame rate. Shared by the weather ramp and the bank
  /// interpolator.
  static double approach({
    required double current,
    required double target,
    required double dt,
    required double timeToTarget,
  }) {
    if (timeToTarget <= 0) return target;
    final rate = 1 - math.pow(0.1, dt / timeToTarget);
    return current + (target - current) * rate;
  }
}
