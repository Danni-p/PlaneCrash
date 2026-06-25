import 'dart:math' as math;

/// A plane position and heading on the 2D navigation map.
///
/// The map uses a north-up convention: `+y` is north (forward when heading is
/// zero) and `+x` is east. Heading is measured clockwise from north in radians,
/// so the unit travel vector is `(sin(heading), cos(heading))`.
class NavigationState {
  const NavigationState({
    required this.planeX,
    required this.planeY,
    required this.headingRad,
  });

  final double planeX;
  final double planeY;
  final double headingRad;
}

/// Pure 2D navigation math for the emergency approach.
///
/// The plane moves at a constant ground speed along its current heading; bank
/// angle is the only thing that turns it. Distance to the island is the true
/// straight-line distance, so steering away genuinely increases it. Everything
/// here is stateless so it can be unit tested in isolation.
abstract final class NavigationEngine {
  /// Builds the island position from a bearing (radians, clockwise from north)
  /// and a straight-line distance, with the plane assumed to be at the origin.
  static math.Point<double> islandFromBearing({
    required double bearingRad,
    required double distance,
  }) {
    return math.Point<double>(
      distance * math.sin(bearingRad),
      distance * math.cos(bearingRad),
    );
  }

  /// Advances the plane by [dt] seconds. Bank angle sets the turn rate; ground
  /// speed is constant and unaffected by the turn.
  static NavigationState step({
    required NavigationState state,
    required double bankDegrees,
    required double groundSpeed,
    required double turnRatePerBankDegree,
    required double dt,
  }) {
    final heading = state.headingRad + bankDegrees * turnRatePerBankDegree * dt;
    return NavigationState(
      planeX: state.planeX + groundSpeed * math.sin(heading) * dt,
      planeY: state.planeY + groundSpeed * math.cos(heading) * dt,
      headingRad: heading,
    );
  }

  /// Straight-line distance from the plane to the island.
  static double distanceTo({
    required NavigationState state,
    required math.Point<double> island,
  }) {
    final dx = island.x - state.planeX;
    final dy = island.y - state.planeY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Bearing to the island relative to the current heading, normalized to
  /// `[-pi, pi]`. Zero means dead ahead; positive is to the right, negative to
  /// the left. Crossing +/-pi flips the sign, which the edge arrow relies on.
  static double relativeBearing({
    required NavigationState state,
    required math.Point<double> island,
  }) {
    final dx = island.x - state.planeX;
    final dy = island.y - state.planeY;
    return normalizeAngle(math.atan2(dx, dy) - state.headingRad);
  }

  /// Wraps [angle] (radians) into the range `[-pi, pi]`.
  static double normalizeAngle(double angle) {
    final twoPi = 2 * math.pi;
    var a = angle % twoPi;
    if (a > math.pi) a -= twoPi;
    if (a < -math.pi) a += twoPi;
    return a;
  }
}
