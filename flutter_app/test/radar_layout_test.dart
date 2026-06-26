import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/widgets/radar_layout.dart';

void main() {
  const center = Offset(100, 100);
  const radius = 100.0;

  Offset offsetFor(double bearingRad, double distanceMeters) =>
      RadarLayout.targetOffset(
        center: center,
        displayRadius: radius,
        relativeBearingRad: bearingRad,
        distanceMeters: distanceMeters,
      );

  group('RadarLayout.targetOffset', () {
    test('dead ahead at half range sits above the centre', () {
      final blip = offsetFor(0, RadarLayout.maxRangeMeters / 2);
      expect(blip.dx, closeTo(100, 1e-9));
      expect(blip.dy, closeTo(50, 1e-9));
    });

    test('90 degrees right at max range rests on the right border', () {
      final blip = offsetFor(math.pi / 2, RadarLayout.maxRangeMeters);
      expect(blip.dx, closeTo(200, 1e-9));
      expect(blip.dy, closeTo(100, 1e-9));
    });

    test('90 degrees left beyond max range clamps to the left border', () {
      final blip = offsetFor(-math.pi / 2, RadarLayout.maxRangeMeters * 1.5);
      expect(blip.dx, closeTo(0, 1e-9));
      expect(blip.dy, closeTo(100, 1e-9));
    });

    test('zero distance places the blip at the centre', () {
      final blip = offsetFor(0, 0);
      expect(blip.dx, closeTo(100, 1e-9));
      expect(blip.dy, closeTo(100, 1e-9));
    });
  });
}
