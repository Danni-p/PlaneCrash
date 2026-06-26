import 'package:flutter/material.dart';

import 'instrument_aircraft_icon.dart';
import 'radar_layout.dart';

/// A top-down radar (plan view). The plane is fixed at the centre pointing up;
/// the island appears as a blip at its bearing relative to the plane heading,
/// scaled by distance and clamped to the edge at [RadarLayout.maxRangeMeters].
class RadarDisplay extends StatelessWidget {
  const RadarDisplay({
    super.key,
    required this.relativeBearingRad,
    required this.distanceMeters,
    this.size = 240,
  });

  /// Bearing to the island relative to the plane heading, in radians. Zero is
  /// dead ahead (up); positive is to the right.
  final double relativeBearingRad;

  /// Straight-line distance to the island in metres.
  final double distanceMeters;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: CustomPaint(
              size: Size.square(size),
              painter: _RadarPainter(
                relativeBearingRad: relativeBearingRad,
                distanceMeters: distanceMeters,
              ),
            ),
          ),
          CustomPaint(size: Size.square(size), painter: const InstrumentAircraftIcon()),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.relativeBearingRad,
    required this.distanceMeters,
  });

  static const Color _background = Color(0xFF0B1A0B);
  static const Color _grid = Color(0xFF39FF14);
  static const Color _blip = Color(0xFF39FF14);

  final double relativeBearingRad;
  final double distanceMeters;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = _background);

    final gridPaint = Paint()
      ..color = _grid.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    final ringPaint = Paint()
      ..color = _grid.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius * 0.5, ringPaint);

    final blip = RadarLayout.targetOffset(
      center: center,
      displayRadius: radius,
      relativeBearingRad: relativeBearingRad,
      distanceMeters: distanceMeters,
    );
    canvas.drawCircle(
      blip,
      4.5,
      Paint()
        ..color = _blip
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.relativeBearingRad != relativeBearingRad ||
      oldDelegate.distanceMeters != distanceMeters;
}
