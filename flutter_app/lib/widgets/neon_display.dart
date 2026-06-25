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
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 14,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          textBaseline: TextBaseline.alphabetic,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 52,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: [
                  Shadow(color: color, blurRadius: 16),
                  Shadow(color: color.withValues(alpha: 0.6), blurRadius: 32),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
