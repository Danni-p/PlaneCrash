import 'package:flutter/material.dart';

/// A large glowing digital readout used for the cockpit gauges (altitude,
/// distance, bank angle).
class NeonDisplay extends StatelessWidget {
  const NeonDisplay({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.color = const Color(0xFF39FF14),
    this.scale = 1.0,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale.clamp(0.6, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 14 * s,
            letterSpacing: 2 * s,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4 * s),
        Row(
          textBaseline: TextBaseline.alphabetic,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 52 * s,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: [
                  Shadow(color: color, blurRadius: 16),
                  Shadow(color: color.withValues(alpha: 0.6), blurRadius: 32),
                ],
              ),
            ),
            SizedBox(width: 6 * s),
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 20 * s,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
