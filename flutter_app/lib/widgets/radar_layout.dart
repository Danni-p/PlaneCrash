import 'dart:math' as math;
import 'dart:ui';

import '../engine/physics_engine.dart';

/// Geometry for the top-down radar instrument. The plane sits at the centre
/// pointing up (heading-up, no rotation); the island is a blip whose angle is
/// the bearing relative to the plane heading and whose radius scales with
/// distance, clamped to the edge once the island is at or beyond [maxRangeMeters].
abstract final class RadarLayout {
  /// Maximum distance the radar can resolve. Matches the emergency starting
  /// distance so the island begins on the edge and moves inward as it closes.
  static const double maxRangeMeters = PhysicsEngine.initialDistance;

  /// Screen-space position of the island blip inside the radar circle.
  ///
  /// [relativeBearingRad] is `0` straight ahead (up) and positive to the right,
  /// matching `GameState.relativeBearing`. The radial offset is linear in
  /// distance up to [maxRangeMeters], where the blip rests on the circle border.
  static Offset targetOffset({
    required Offset center,
    required double displayRadius,
    required double relativeBearingRad,
    required double distanceMeters,
  }) {
    final norm = (distanceMeters / maxRangeMeters).clamp(0.0, 1.0);
    final r = norm * displayRadius;
    return Offset(
      center.dx + r * math.sin(relativeBearingRad),
      center.dy - r * math.cos(relativeBearingRad),
    );
  }
}
