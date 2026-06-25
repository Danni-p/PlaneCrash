import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/widgets/island_viewport_layout.dart';

void main() {
  const size = Size(800, 600);

  group('IslandViewportLayout.forTarget', () {
    test('bearing zero places label centered above island peak', () {
      final layout = IslandViewportLayout.forTarget(
        size: size,
        relativeBearing: 0,
        islandApproach: 0.5,
      );

      expect(layout.mode, IslandViewportMode.onIsland);
      expect(layout.islandCenterX, closeTo(400, 1e-9));
      expect(layout.labelPosition.dx, closeTo(400, 1e-9));

      final horizonY = IslandViewportLayout.horizonYFor(size);
      final land = IslandViewportLayout.landMetrics(
        size: size,
        progress: 0.5,
        scale: 1.0,
        horizonY: horizonY,
      );
      expect(
        layout.labelPosition.dy,
        closeTo(land.peakY - IslandViewportLayout.labelPadding, 1e-9),
      );
      expect(layout.labelFractionalTranslation, const Offset(-0.5, -1.0));
    });

    test('bearing beyond +55° places label beside right edge arrow', () {
      final layout = IslandViewportLayout.forTarget(
        size: size,
        relativeBearing: 60 * math.pi / 180,
        islandApproach: 0.5,
      );

      expect(layout.mode, IslandViewportMode.offScreenRight);
      expect(layout.arrowToRight, isTrue);

      final tipX = IslandViewportLayout.arrowTipX(size, toRight: true);
      expect(
        layout.labelPosition.dx,
        closeTo(
          tipX -
              IslandViewportLayout.arrowDepth -
              IslandViewportLayout.arrowLabelGap,
          1e-9,
        ),
      );
      expect(
        layout.labelPosition.dy,
        closeTo(IslandViewportLayout.horizonYFor(size), 1e-9),
      );
      expect(layout.labelFractionalTranslation, const Offset(-1.0, -0.5));
    });

    test('bearing beyond -55° places label beside left edge arrow', () {
      final layout = IslandViewportLayout.forTarget(
        size: size,
        relativeBearing: -60 * math.pi / 180,
        islandApproach: 0.5,
      );

      expect(layout.mode, IslandViewportMode.offScreenLeft);
      expect(layout.arrowToRight, isFalse);

      final tipX = IslandViewportLayout.arrowTipX(size, toRight: false);
      expect(
        layout.labelPosition.dx,
        closeTo(
          tipX +
              IslandViewportLayout.arrowDepth +
              IslandViewportLayout.arrowLabelGap,
          1e-9,
        ),
      );
      expect(
        layout.labelPosition.dy,
        closeTo(IslandViewportLayout.horizonYFor(size), 1e-9),
      );
      expect(layout.labelFractionalTranslation, const Offset(0.0, -0.5));
    });
  });
}
