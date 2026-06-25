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
          windBankDegrees: 0,
        ),
        0,
      );
    });

    test('tilts proportionally to the crew difference', () {
      expect(
        PhysicsEngine.bankAngle(
          counterLeft: 5,
          counterRight: 2,
          windBankDegrees: 0,
        ),
        3 * PhysicsEngine.bankPerCrewDifference,
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
