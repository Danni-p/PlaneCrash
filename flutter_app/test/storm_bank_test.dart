import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';
import 'package:planecrash/engine/storm_bank.dart';

void main() {
  group('StormBank', () {
    test('rolls base and jitter immediately on first advance', () {
      final storm = StormBank();
      final random = math.Random(42);

      storm.advance(0.1, random);

      expect(
        storm.base,
        inInclusiveRange(
          -PhysicsEngine.stormMaxBankDegrees,
          PhysicsEngine.stormMaxBankDegrees,
        ),
      );
      expect(
        storm.jitter,
        inInclusiveRange(
          storm.base - PhysicsEngine.stormJitterDegrees,
          storm.base + PhysicsEngine.stormJitterDegrees,
        ),
      );
    });

    test('re-rolls jitter about every second', () {
      final storm = StormBank();
      final random = math.Random(42);

      storm.advance(0.1, random);
      final firstJitter = storm.jitter;

      storm.advance(1.0, random);
      expect(storm.jitter, isNot(equals(firstJitter)));
      expect(
        storm.jitter,
        inInclusiveRange(
          storm.base - PhysicsEngine.stormJitterDegrees,
          storm.base + PhysicsEngine.stormJitterDegrees,
        ),
      );
    });

    test('re-rolls base about every three seconds', () {
      final storm = StormBank();
      final random = math.Random(42);

      storm.advance(0.1, random);
      final firstBase = storm.base;

      storm.advance(PhysicsEngine.stormBaseIntervalSeconds, random);
      expect(storm.base, isNot(equals(firstBase)));
      expect(
        storm.base,
        inInclusiveRange(
          -PhysicsEngine.stormMaxBankDegrees,
          PhysicsEngine.stormMaxBankDegrees,
        ),
      );
    });

    test('preserves elapsed time when advance is not called', () {
      final storm = StormBank();
      final random = math.Random(42);

      storm.advance(0.1, random);
      final jitterAfterInit = storm.jitter;

      storm.advance(0.5, random);
      expect(storm.jitter, equals(jitterAfterInit));

      storm.advance(0.6, random);
      expect(storm.jitter, isNot(equals(jitterAfterInit)));
    });

    test('reset clears state so the next advance re-initializes', () {
      final storm = StormBank();
      final random = math.Random(42);

      storm.advance(5.0, random);
      final beforeReset = storm.base;

      storm.reset();
      expect(storm.base, 0);
      expect(storm.jitter, 0);

      storm.advance(0.1, random);
      expect(
        storm.base,
        inInclusiveRange(
          -PhysicsEngine.stormMaxBankDegrees,
          PhysicsEngine.stormMaxBankDegrees,
        ),
      );
      expect(storm.base, isNot(equals(beforeReset)));
    });
  });
}
