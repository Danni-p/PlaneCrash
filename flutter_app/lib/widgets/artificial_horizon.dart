import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An attitude indicator (artificial horizon): a circle split into sky and
/// ground that rolls with the bank angle. A fixed aircraft reference stays level
/// on top so the roll is easy to read.
class ArtificialHorizon extends StatelessWidget {
  const ArtificialHorizon({
    super.key,
    required this.bankAngleDegrees,
    this.size = 240,
  });

  final double bankAngleDegrees;
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
            child: Transform.rotate(
              angle: -bankAngleDegrees * math.pi / 180.0,
              child: CustomPaint(
                size: Size.square(size),
                painter: _HorizonPainter(),
              ),
            ),
          ),
          CustomPaint(size: Size.square(size), painter: _AircraftReferencePainter()),
        ],
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  static const Color _sky = Color(0xFF2E86DE);
  static const Color _ground = Color(0xFF8B5A2B);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    // Oversize the halves so they always cover the circle when rotated.
    final extent = size.longestSide;

    final skyPaint = Paint()..color = _sky;
    final groundPaint = Paint()..color = _ground;
    canvas.drawRect(
      Rect.fromLTWH(center.dx - extent, center.dy - extent, extent * 2, extent),
      skyPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(center.dx - extent, center.dy, extent * 2, extent),
      groundPaint,
    );

    final horizonPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(center.dx - extent, center.dy),
      Offset(center.dx + extent, center.dy),
      horizonPaint,
    );

    // Pitch ladder ticks above and below the horizon.
    final tickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;
    for (var i = 1; i <= 3; i++) {
      final dy = i * size.height / 10;
      final half = size.width * 0.08;
      canvas.drawLine(
        Offset(center.dx - half, center.dy - dy),
        Offset(center.dx + half, center.dy - dy),
        tickPaint,
      );
      canvas.drawLine(
        Offset(center.dx - half, center.dy + dy),
        Offset(center.dx + half, center.dy + dy),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter oldDelegate) => false;
}

class _AircraftReferencePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color(0xFFFFC312)
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

    // Outer bezel.
    final bezel = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, size.width / 2 - 1.5, bezel);
  }

  @override
  bool shouldRepaint(covariant _AircraftReferencePainter oldDelegate) => false;
}
