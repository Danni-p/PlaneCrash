import 'package:flutter/material.dart';

import '../models/game_phase.dart';
import 'island_viewport_layout.dart';

/// Full-screen background scenery for the cockpit. During cruise a distant
/// landmass drifts closer (purely cosmetic). Once the emergency landing begins
/// the target island is placed on the horizon according to its bearing relative
/// to the plane's heading: centered when dead ahead, sliding sideways as the
/// plane turns, and replaced by an edge arrow once it leaves the field of view.
/// A thunderstorm darkens the sky.
class PhaseScenery extends StatelessWidget {
  const PhaseScenery({
    super.key,
    required this.phase,
    required this.cruiseProgress,
    required this.islandApproach,
    required this.relativeBearing,
    required this.stormIntensity,
    required this.altitude,
  });

  final GamePhase phase;

  /// Cosmetic land approach during cruise, 0..1.
  final double cruiseProgress;

  /// Target island approach (1 - distance/initialDistance), 0..1.
  final double islandApproach;

  /// Bearing to the island relative to the plane heading, in radians and
  /// normalized to `[-pi, pi]`. Zero is dead ahead; positive is to the right.
  final double relativeBearing;

  /// Ramped thunderstorm intensity, 0..1.
  final double stormIntensity;

  /// Current altitude in metres; drives the scenery horizon position.
  final double altitude;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _SceneryPainter(
          phase: phase,
          cruiseProgress: cruiseProgress,
          islandApproach: islandApproach,
          relativeBearing: relativeBearing,
          stormIntensity: stormIntensity,
          altitude: altitude,
        ),
      ),
    );
  }
}

class _SceneryPainter extends CustomPainter {
  _SceneryPainter({
    required this.phase,
    required this.cruiseProgress,
    required this.islandApproach,
    required this.relativeBearing,
    required this.stormIntensity,
    required this.altitude,
  });

  final GamePhase phase;
  final double cruiseProgress;
  final double islandApproach;
  final double relativeBearing;
  final double stormIntensity;
  final double altitude;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = IslandViewportLayout.horizonYFor(size, altitude: altitude);

    _paintSky(canvas, size, horizonY);
    _paintSea(canvas, size, horizonY);

    if (phase == GamePhase.cruise) {
      _paintLand(
        canvas,
        size,
        horizonY,
        centerX: size.width / 2,
        progress: cruiseProgress,
        scale: 0.35,
      );
    } else if (phase == GamePhase.emergency || phase == GamePhase.finished) {
      _paintTargetIsland(canvas, size, horizonY);
    }
  }

  /// Draws the target island offset by its bearing, or an edge arrow when it
  /// has drifted out of view.
  void _paintTargetIsland(Canvas canvas, Size size, double horizonY) {
    final layout = IslandViewportLayout.forTarget(
      size: size,
      relativeBearing: relativeBearing,
      islandApproach: islandApproach,
      altitude: altitude,
    );
    if (layout.mode != IslandViewportMode.onIsland) {
      _paintEdgeArrow(
        canvas,
        horizonY: layout.horizonY,
        tipX: layout.arrowTipX!,
        baseX: layout.arrowBaseX!,
      );
      return;
    }
    _paintLand(
      canvas,
      size,
      horizonY,
      centerX: layout.islandCenterX!,
      progress: islandApproach,
      scale: 1.0,
    );
  }

  /// Draws a chevron on the left or right screen edge pointing toward the
  /// island when it is off-screen.
  void _paintEdgeArrow(
    Canvas canvas, {
    required double horizonY,
    required double tipX,
    required double baseX,
  }) {
    final path = Path()
      ..moveTo(tipX, horizonY)
      ..lineTo(baseX, horizonY - IslandViewportLayout.arrowHalfHeight)
      ..lineTo(baseX, horizonY + IslandViewportLayout.arrowHalfHeight)
      ..close();
    final paint = Paint()..color = const Color(0xFF39FF14);
    canvas.drawPath(path, paint);
  }

  void _paintSky(Canvas canvas, Size size, double horizonY) {
    final clear = const Color(0xFF6FB7E8);
    final dark = const Color(0xFF1B2733);
    final top = Color.lerp(clear, dark, stormIntensity)!;
    final bottom = Color.lerp(const Color(0xFFBFE3F5), const Color(0xFF3A4A57), stormIntensity)!;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(Rect.fromLTWH(0, 0, size.width, horizonY));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, horizonY), paint);
  }

  void _paintSea(Canvas canvas, Size size, double horizonY) {
    final calm = const Color(0xFF15527A);
    final rough = const Color(0xFF0B1E2C);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(const Color(0xFF2E86DE), rough, stormIntensity)!,
          Color.lerp(calm, rough, stormIntensity)!,
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY));
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY),
      paint,
    );
  }

  /// Draws the landmass sitting on the horizon at [centerX]. [progress] (0..1)
  /// drives how large and close it appears; [scale] caps the maximum size
  /// (cruise land stays small and distant, the target island can fill more of
  /// the view).
  void _paintLand(
    Canvas canvas,
    Size size,
    double horizonY, {
    required double centerX,
    required double progress,
    required double scale,
  }) {
    final t = progress.clamp(0.0, 1.0);
    final width = size.width * (0.18 + 0.55 * t) * scale;
    final height = size.height * (0.05 + 0.22 * t) * scale;

    final landPaint = Paint()..color = const Color(0xFF2F7D32);
    final path = Path()
      ..moveTo(centerX - width / 2, horizonY)
      ..quadraticBezierTo(
        centerX - width / 4,
        horizonY - height,
        centerX,
        horizonY - height * 0.9,
      )
      ..quadraticBezierTo(
        centerX + width / 4,
        horizonY - height,
        centerX + width / 2,
        horizonY,
      )
      ..close();
    canvas.drawPath(path, landPaint);

    // A small beach band at the waterline.
    final beachPaint = Paint()..color = const Color(0xFFE2C290);
    canvas.drawRect(
      Rect.fromLTWH(centerX - width / 2, horizonY, width, height * 0.12),
      beachPaint,
    );

    // A palm-trunk dot for the target island once it is reasonably close.
    if (scale >= 1.0 && t > 0.35) {
      final treePaint = Paint()..color = const Color(0xFF1B5E20);
      canvas.drawCircle(
        Offset(centerX, horizonY - height * 0.9),
        height * 0.12,
        treePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SceneryPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.cruiseProgress != cruiseProgress ||
        oldDelegate.islandApproach != islandApproach ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.stormIntensity != stormIntensity ||
        oldDelegate.altitude != altitude;
  }
}
