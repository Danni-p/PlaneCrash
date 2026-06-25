import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/navigation_engine.dart';

void main() {
  const speed = 100.0;
  const turnRate = 0.035;

  NavigationState flyStraight(NavigationState state, double dt) {
    return NavigationEngine.step(
      state: state,
      bankDegrees: 0,
      groundSpeed: speed,
      turnRatePerBankDegree: turnRate,
      dt: dt,
    );
  }

  group('distanceTo', () {
    test('shrinks when flying straight toward the island', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: 0,
        distance: 1000,
      );
      const start = NavigationState(planeX: 0, planeY: 0, headingRad: 0);
      final next = flyStraight(start, 1.0);

      expect(
        NavigationEngine.distanceTo(state: next, island: island),
        closeTo(1000 - speed, 1e-9),
      );
    });

    test('grows when flying directly away from the island', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: 0,
        distance: 1000,
      );
      // Heading south (pi) points away from an island due north.
      const start = NavigationState(planeX: 0, planeY: 0, headingRad: math.pi);
      final next = flyStraight(start, 1.0);

      expect(
        NavigationEngine.distanceTo(state: next, island: island),
        closeTo(1000 + speed, 1e-6),
      );
    });

    test('is zero when the plane sits on the island', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: 0,
        distance: 1000,
      );
      final overhead = NavigationState(
        planeX: island.x,
        planeY: island.y,
        headingRad: 0,
      );

      expect(
        NavigationEngine.distanceTo(state: overhead, island: island),
        closeTo(0, 1e-9),
      );
    });
  });

  group('relativeBearing', () {
    test('is zero when the heading points at the island', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: 0,
        distance: 1000,
      );
      const state = NavigationState(planeX: 0, planeY: 0, headingRad: 0);

      expect(
        NavigationEngine.relativeBearing(state: state, island: island),
        closeTo(0, 1e-9),
      );
    });

    test('is positive when the island is to the right', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: math.pi / 2,
        distance: 1000,
      );
      const state = NavigationState(planeX: 0, planeY: 0, headingRad: 0);

      expect(
        NavigationEngine.relativeBearing(state: state, island: island),
        closeTo(math.pi / 2, 1e-9),
      );
    });

    test('flips sign as the plane turns past the island', () {
      final island = NavigationEngine.islandFromBearing(
        bearingRad: 0,
        distance: 1000,
      );
      // With the island dead astern, a tiny rotation across the heading of pi
      // wraps the relative bearing from near -pi to near +pi (opposite edges).
      final justBefore = NavigationState(
        planeX: 0,
        planeY: 0,
        headingRad: math.pi - 0.01,
      );
      final justAfter = NavigationState(
        planeX: 0,
        planeY: 0,
        headingRad: math.pi + 0.01,
      );

      final before =
          NavigationEngine.relativeBearing(state: justBefore, island: island);
      final after =
          NavigationEngine.relativeBearing(state: justAfter, island: island);

      expect(before, lessThan(0));
      expect(after, greaterThan(0));
      expect(before.abs(), closeTo(math.pi, 0.02));
      expect(after.abs(), closeTo(math.pi, 0.02));
    });
  });

  group('step', () {
    test('turns right under positive bank and keeps constant speed', () {
      const start = NavigationState(planeX: 0, planeY: 0, headingRad: 0);
      final next = NavigationEngine.step(
        state: start,
        bankDegrees: 30,
        groundSpeed: speed,
        turnRatePerBankDegree: turnRate,
        dt: 1.0,
      );

      expect(next.headingRad, closeTo(30 * turnRate, 1e-9));
      final travelled = math.sqrt(
        next.planeX * next.planeX + next.planeY * next.planeY,
      );
      expect(travelled, closeTo(speed, 1e-9));
    });
  });
}
