import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';
import 'package:planecrash/engine/wind_gust.dart';

void main() {
  group('PhysicsEngine.midBiasedUnit', () {
    test('returns values in 0..1', () {
      final random = math.Random(42);
      for (var i = 0; i < 100; i++) {
        expect(PhysicsEngine.midBiasedUnit(random), inInclusiveRange(0.0, 1.0));
      }
    });

    test('mean is near 0.5 over many samples', () {
      final random = math.Random(7);
      var sum = 0.0;
      const n = 10_000;
      for (var i = 0; i < n; i++) {
        sum += PhysicsEngine.midBiasedUnit(random);
      }
      expect(sum / n, closeTo(0.5, 0.02));
    });
  });

  group('WindGust', () {
    test('initializes value in 0..1 on first advance', () {
      final gust = WindGust();
      final random = math.Random(42);

      gust.advance(0.1, random);

      expect(gust.value, inInclusiveRange(0.0, 1.0));
      expect(gust.target, inInclusiveRange(0.0, 1.0));
      expect(gust.value, equals(gust.target));
    });

    test('eases gradually toward a new target', () {
      final gust = WindGust();
      final random = math.Random(42);

      gust.advance(0.1, random);
      gust.advance(6.0, random);
      final start = gust.value;
      final newTarget = gust.target;
      expect(start, isNot(equals(newTarget)));

      gust.advance(0.5, random);
      expect(gust.value, isNot(equals(start)));
      expect((gust.value - newTarget).abs(), lessThan((start - newTarget).abs()));
    });

    test('re-rolls target about every six seconds', () {
      final gust = WindGust();
      final random = math.Random(42);

      gust.advance(0.1, random);
      final firstTarget = gust.target;

      gust.advance(6.0, random);
      expect(gust.target, isNot(equals(firstTarget)));
      expect(gust.target, inInclusiveRange(0.0, 1.0));
    });

    test('preserves elapsed time when advance is not called', () {
      final gust = WindGust();
      final random = math.Random(42);

      gust.advance(0.1, random);
      final targetAfterInit = gust.target;

      gust.advance(3.0, random);
      expect(gust.target, equals(targetAfterInit));

      gust.advance(3.0, random);
      expect(gust.target, isNot(equals(targetAfterInit)));
    });

    test('reset clears state so the next advance re-initializes', () {
      final gust = WindGust();
      final random = math.Random(42);

      gust.advance(5.0, random);
      final beforeReset = gust.value;

      gust.reset();
      expect(gust.value, 0);
      expect(gust.target, 0);

      gust.advance(0.1, random);
      expect(gust.value, inInclusiveRange(0.0, 1.0));
      expect(gust.value, isNot(equals(beforeReset)));
    });
  });
}
