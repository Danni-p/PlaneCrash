import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';
import 'package:planecrash/widgets/island_viewport_layout.dart';

void main() {
  const size = Size(800, 600);
  const highAltitude = PhysicsEngine.initialAltitude;

  group('IslandViewportLayout.visualApproachFromDistance', () {
    const initial = PhysicsEngine.initialDistance;
    const minRatio = IslandViewportLayout.minVisualDistanceRatio;

    test('is zero at spawn distance', () {
      expect(
        IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: initial,
          initialDistance: initial,
        ),
        0.0,
      );
    });

    test('is one at the minimum visual distance', () {
      expect(
        IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: initial * minRatio,
          initialDistance: initial,
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('is about one percent at half spawn distance', () {
      expect(
        IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: initial / 2,
          initialDistance: initial,
        ),
        closeTo(0.010101010101010102, 1e-9),
      );
    });

    test('clamps to zero when farther than spawn', () {
      expect(
        IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: initial * 1.5,
          initialDistance: initial,
        ),
        0.0,
      );
    });

    test('clamps to one when closer than the visual floor', () {
      expect(
        IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: initial * minRatio / 2,
          initialDistance: initial,
        ),
        1.0,
      );
    });

    test('increases monotonically as distance shrinks', () {
      final distances = [10000.0, 5000.0, 2000.0, 1000.0, 500.0, 100.0];
      var previous = -1.0;
      for (final distance in distances) {
        final progress = IslandViewportLayout.visualApproachFromDistance(
          distanceMeters: distance,
          initialDistance: initial,
        );
        expect(progress, greaterThanOrEqualTo(previous));
        previous = progress;
      }
    });
  });

  group('IslandViewportLayout.horizonFractionForAltitude', () {
    test('at initial altitude horizon is mostly sky', () {
      expect(
        IslandViewportLayout.horizonFractionForAltitude(highAltitude),
        closeTo(IslandViewportLayout.horizonFractionAtHighAltitude, 1e-9),
      );
    });

    test('at sea level horizon is mostly water', () {
      expect(
        IslandViewportLayout.horizonFractionForAltitude(0),
        closeTo(IslandViewportLayout.horizonFractionAtLowAltitude, 1e-9),
      );
    });

    test('at half altitude horizon is between high and low', () {
      final fraction = IslandViewportLayout.horizonFractionForAltitude(
        highAltitude / 2,
      );
      expect(
        fraction,
        greaterThan(IslandViewportLayout.horizonFractionAtLowAltitude),
      );
      expect(
        fraction,
        lessThan(IslandViewportLayout.horizonFractionAtHighAltitude),
      );
    });
  });

  group('IslandViewportLayout.forTarget', () {
    test('bearing zero places label centered above island peak', () {
      final layout = IslandViewportLayout.forTarget(
        size: size,
        relativeBearing: 0,
        islandApproach: 0.5,
        altitude: highAltitude,
      );

      expect(layout.mode, IslandViewportMode.onIsland);
      expect(layout.islandCenterX, closeTo(400, 1e-9));
      expect(layout.labelPosition.dx, closeTo(400, 1e-9));

      final horizonY =
          IslandViewportLayout.horizonYFor(size, altitude: highAltitude);
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
        altitude: highAltitude,
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
        closeTo(
          IslandViewportLayout.horizonYFor(size, altitude: highAltitude),
          1e-9,
        ),
      );
      expect(layout.labelFractionalTranslation, const Offset(-1.0, -0.5));
    });

    test('bearing beyond -55° places label beside left edge arrow', () {
      final layout = IslandViewportLayout.forTarget(
        size: size,
        relativeBearing: -60 * math.pi / 180,
        islandApproach: 0.5,
        altitude: highAltitude,
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
        closeTo(
          IslandViewportLayout.horizonYFor(size, altitude: highAltitude),
          1e-9,
        ),
      );
      expect(layout.labelFractionalTranslation, const Offset(0.0, -0.5));
    });
  });
}
