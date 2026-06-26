import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';

void main() {
  group('altitudeLossPerSecond', () {
    test('uses the base rate with no active crew', () {
      expect(
        PhysicsEngine.altitudeLossPerSecond(activeTotal: 0, stormIntensity: 0),
        PhysicsEngine.baseSinkRate,
      );
    });

    test('slows the descent as more crew become active', () {
      final few = PhysicsEngine.altitudeLossPerSecond(
        activeTotal: 3,
        stormIntensity: 0,
      );
      final many = PhysicsEngine.altitudeLossPerSecond(
        activeTotal: 8,
        stormIntensity: 0,
      );
      expect(many, lessThan(few));
    });

    test('never drops below the minimum sink rate', () {
      expect(
        PhysicsEngine.altitudeLossPerSecond(activeTotal: 100, stormIntensity: 0),
        PhysicsEngine.minSinkRate,
      );
    });

    test('adds the storm bonus scaled by intensity', () {
      final base = PhysicsEngine.altitudeLossPerSecond(
        activeTotal: 0,
        stormIntensity: 0,
      );
      final full = PhysicsEngine.altitudeLossPerSecond(
        activeTotal: 0,
        stormIntensity: 1,
      );
      expect(full - base, closeTo(PhysicsEngine.stormMaxBonus, 1e-9));
    });
  });

  group('bankAngle', () {
    test('is level when both sides are balanced and there is no wind', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 4,
          counterRight: 4,
          bankPerPerson: 2,
          windBankDegrees: 0,
        ),
        0,
      );
    });

    test('banks left when more people are on the left', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 5,
          counterRight: 2,
          bankPerPerson: 2,
          windBankDegrees: 0,
        ),
        -6,
      );
    });

    test('banks right when more people are on the right', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 2,
          counterRight: 5,
          bankPerPerson: 2,
          windBankDegrees: 0,
        ),
        6,
      );
    });

    test('scales linearly with bankPerPerson', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 0,
          counterRight: 3,
          bankPerPerson: 2,
          windBankDegrees: 0,
        ),
        6,
      );
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 0,
          counterRight: 3,
          bankPerPerson: 4,
          windBankDegrees: 0,
        ),
        12,
      );
    });

    test('clamps crew plus wind to maxBankDegrees', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 0,
          counterRight: 20,
          bankPerPerson: 8,
          windBankDegrees: 15,
        ),
        PhysicsEngine.maxBankDegrees,
      );
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 20,
          counterRight: 0,
          bankPerPerson: 8,
          windBankDegrees: -15,
        ),
        -PhysicsEngine.maxBankDegrees,
      );
    });

    test('adds storm and wind additively with balanced crew', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 4,
          counterRight: 4,
          bankPerPerson: 2,
          windBankDegrees: -2,
          stormBankDegrees: 4,
        ),
        2,
      );
    });

    test('clamps crew plus wind plus storm to maxBankDegrees', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 0,
          counterRight: 10,
          bankPerPerson: 8,
          windBankDegrees: 15,
          stormBankDegrees: 5,
        ),
        PhysicsEngine.maxBankDegrees,
      );
    });
  });

  group('stormBankDegrees', () {
    test('is zero at zero storm intensity', () {
      expect(
        PhysicsEngine.stormBankDegrees(
          baseDegrees: 4,
          jitterDegrees: 0.3,
          stormIntensity: 0,
        ),
        0,
      );
    });

    test('scales base plus jitter at full intensity', () {
      expect(
        PhysicsEngine.stormBankDegrees(
          baseDegrees: 4,
          jitterDegrees: 0.3,
          stormIntensity: 1,
        ),
        closeTo(4.3, 1e-9),
      );
    });

    test('scales linearly with partial intensity', () {
      expect(
        PhysicsEngine.stormBankDegrees(
          baseDegrees: 4,
          jitterDegrees: 0,
          stormIntensity: 0.5,
        ),
        2,
      );
    });
  });

  group('approach', () {
    test('reaches roughly 90 percent after the time constant', () {
      final value = PhysicsEngine.approach(
        current: 0,
        target: 1,
        dt: 8,
        timeToTarget: 8,
      );
      expect(value, closeTo(0.9, 1e-6));
    });
  });
}
