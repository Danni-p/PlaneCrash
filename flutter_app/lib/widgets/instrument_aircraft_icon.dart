import 'package:flutter/material.dart';

/// Shared cockpit-instrument overlay: a fixed yellow aircraft reference (two
/// wings plus a centre dot) and the outer bezel ring. Used by both the
/// artificial horizon and the radar so the two gauges look identical.
class InstrumentAircraftIcon extends CustomPainter {
  const InstrumentAircraftIcon();

  static const Color aircraftColor = Color(0xFFFFC312);
  static const Color bezelColor = Colors.white24;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = aircraftColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final wing = size.width * 0.22;
    final gap = size.width * 0.06;
    // Left wing, centre dot, right wing.
    canvas.drawLine(
      Offset(center.dx - wing, center.dy),
      Offset(center.dx - gap, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(center.dx + wing, center.dy),
      paint,
    );
    canvas.drawCircle(center, 3, paint);

    final bezel = Paint()
      ..color = bezelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, size.width / 2 - 1.5, bezel);
  }

  @override
  bool shouldRepaint(covariant InstrumentAircraftIcon oldDelegate) => false;
}
