import 'dart:math' as math;

/// Pure flight-physics calculations and the tunable constants that drive them.
///
/// Everything here is stateless so it can be unit tested in isolation; the
/// mutable run state lives in `GameState`.
abstract final class PhysicsEngine {
  /// Starting altitude in metres.
  static const double initialAltitude = 17500.0;

  /// Distance to the island in metres, set when the malfunction reveals it.
  static const double initialDistance = 13500.0;

  /// Altitude lost per second with zero active crew.
  static const double baseSinkRate = 25.0;

  /// Reduction of the per-second sink rate for each active crew member.
  static const double reductionPerPerson = 1.3;

  /// Lower bound on the sink rate; the plane always descends a little.
  static const double minSinkRate = 5.0;

  /// Extra altitude lost per second during a fully-ramped thunderstorm.
  static const double stormMaxBonus = 10.0;

  /// Maximum thunderstorm-induced bank bias in degrees at full intensity.
  static const double stormMaxBankDegrees = 2.0;

  /// Random jitter range around the storm base bank, in degrees.
  static const double stormJitterDegrees = 0.2;

  /// Seconds between new storm base bank rolls.
  static const double stormBaseIntervalSeconds = 3.0;

  /// Seconds between new storm jitter rolls.
  static const double stormJitterIntervalSeconds = 1.0;

  /// Maximum wind-induced bank bias in degrees at full strength.
  static const double maxWindBankDegrees = 15.0;

  /// Seconds between new wind gust target rolls.
  static const double windGustIntervalSeconds = 6.0;

  /// Seconds to ease the current gust toward each new target (~90% reached).
  static const double windGustApproachSeconds = 6.0;

  /// Draws a value in `0..1` biased toward the midpoint (triangular distribution).
  static double midBiasedUnit(math.Random random) {
    return (random.nextDouble() + random.nextDouble()) / 2;
  }

  /// Default bank degrees per person on one side when the counters are imbalanced.
  static const double defaultBankPerPerson = 2.0;

  /// Controller-adjustable range for [defaultBankPerPerson].
  static const double minBankPerPerson = 0.5;
  static const double maxBankPerPerson = 8.0;

  /// Maximum combined crew + weather bank angle in degrees.
  static const double maxBankDegrees = 90.0;

  /// Default island approach speed in metres per second.
  static const double defaultDistanceSpeed = 15.0;

  /// Turn rate in radians per second for each degree of bank. At the default a
  /// sustained 30 degree bank turns the plane roughly 60 degrees per second,
  /// which produces a visible curve without spinning on the spot.
  static const double turnRatePerBankDegree = 0.035;

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

  /// Thunderstorm-induced bank bias in degrees.
  ///
  /// [baseDegrees] and [jitterDegrees] come from [StormBank]; [stormIntensity]
  /// is the ramped thunderstorm strength in the range 0..1.
  static double stormBankDegrees({
    required double baseDegrees,
    required double jitterDegrees,
    required double stormIntensity,
  }) {
    return (baseDegrees + jitterDegrees) * stormIntensity.clamp(0.0, 1.0);
  }

  /// Target bank angle in degrees from crew balance plus wind and storm,
  /// clamped to [maxBankDegrees]. More people on the left bank left; more on
  /// the right bank right.
  static double bankAngle({
    required int counterLeft,
    required int counterRight,
    required double bankPerPerson,
    required double windBankDegrees,
    double stormBankDegrees = 0,
  }) {
    final crew = (counterRight - counterLeft) * bankPerPerson;
    return (crew + windBankDegrees + stormBankDegrees)
        .clamp(-maxBankDegrees, maxBankDegrees);
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
