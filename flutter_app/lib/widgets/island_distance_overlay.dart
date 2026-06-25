import 'package:flutter/material.dart';

import 'island_viewport_layout.dart';

/// Compact distance readout that tracks the target island in view, or sits
/// beside the off-screen edge arrow when the island leaves the field of view.
class IslandDistanceOverlay extends StatelessWidget {
  const IslandDistanceOverlay({
    super.key,
    required this.distanceMeters,
    required this.relativeBearing,
    required this.islandApproach,
    required this.unit,
  });

  final int distanceMeters;
  final double relativeBearing;
  final double islandApproach;
  final String unit;

  static const Color _distanceColor = Color(0xFF0A6B82);
  static const Color _distanceGlow = Color(0x660A6B82);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = IslandViewportLayout.forTarget(
          size: size,
          relativeBearing: relativeBearing,
          islandApproach: islandApproach,
        );

        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: layout.labelPosition.dx,
                top: layout.labelPosition.dy,
                child: FractionalTranslation(
                  translation: layout.labelFractionalTranslation,
                  child: Text(
                    '$distanceMeters $unit',
                    style: const TextStyle(
                      color: _distanceColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(color: _distanceGlow, blurRadius: 8),
                        Shadow(color: _distanceGlow, blurRadius: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
