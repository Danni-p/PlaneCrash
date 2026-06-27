import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';
import 'package:planecrash/models/broadcast_message.dart';
import 'package:planecrash/models/game_phase.dart';
import 'package:planecrash/models/game_state.dart';

void main() {
  GameState state() => GameState();

  void startEmergency(GameState gs, {int initialAltitude = 5000}) {
    gs.applySettingsUpdate(
      SettingsUpdate(
        distanceSpeed: PhysicsEngine.defaultDistanceSpeed,
        bankPerPerson: PhysicsEngine.defaultBankPerPerson,
        initialAltitude: initialAltitude,
        source: 'test',
      ),
    );
    gs.applyPhaseAction(PhaseAction.startCruise);
    gs.applyPhaseAction(PhaseAction.engineMalfunction);
    gs.enterBriefing();
    gs.applyPhaseAction(PhaseAction.startEmergency);
  }

  group('GameState altitude countdown', () {
    test('starts at cruise display altitude during countdown', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      expect(gs.phase, GamePhase.emergency);
      expect(gs.isAltitudeCountdownActive, isTrue);
      expect(gs.altitude, PhysicsEngine.displayCruiseAltitude);
    });

    test('interpolates toward run initial over 3 seconds', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      gs.advance(1.5);
      expect(gs.altitude, closeTo(11250, 1));
      gs.advance(1.5);
      expect(gs.isAltitudeCountdownActive, isFalse);
      expect(gs.altitude, 5000);
    });

    test('updates target if settings arrive mid-countdown', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      gs.advance(1.0);
      gs.applySettingsUpdate(
        SettingsUpdate(
          distanceSpeed: PhysicsEngine.defaultDistanceSpeed,
          bankPerPerson: PhysicsEngine.defaultBankPerPerson,
          initialAltitude: 4000,
          source: 'test',
        ),
      );
      gs.advance(2.0);
      expect(gs.altitude, 4000);
    });
  });

  group('GameState altitude boost', () {
    test('adds 100 m after countdown', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      gs.advance(PhysicsEngine.altitudeCountdownSeconds);
      gs.applyAltitudeBoost(const AltitudeBoost(source: 'test'));
      expect(gs.altitude, 5100);
      expect(gs.altitudeBoostTotal, 100);
    });

    test('caps at initial plus 500', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      gs.advance(PhysicsEngine.altitudeCountdownSeconds);
      for (var i = 0; i < 10; i++) {
        gs.applyAltitudeBoost(const AltitudeBoost(source: 'test'));
      }
      expect(gs.altitude, 5500);
      expect(gs.altitudeBoostTotal, 500);
    });

    test('ignores boost during countdown', () {
      final gs = state();
      startEmergency(gs, initialAltitude: 5000);
      gs.applyAltitudeBoost(const AltitudeBoost(source: 'test'));
      expect(gs.altitudeBoostTotal, 0);
    });
  });
}
