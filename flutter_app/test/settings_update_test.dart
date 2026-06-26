import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/engine/physics_engine.dart';
import 'package:planecrash/models/broadcast_message.dart';

void main() {
  group('SettingsUpdate.fromJson', () {
    test('defaults bankPerPerson when missing', () {
      final update = SettingsUpdate.fromJson({
        'distanceSpeed': 20,
        'source': 'ctrl-test',
      });
      expect(update.distanceSpeed, 20);
      expect(update.bankPerPerson, PhysicsEngine.defaultBankPerPerson);
      expect(update.source, 'ctrl-test');
    });

    test('round-trips bankPerPerson', () {
      const update = SettingsUpdate(
        distanceSpeed: 18,
        bankPerPerson: 3.5,
        source: 'ctrl-test',
      );
      final parsed = SettingsUpdate.fromJson(update.toJson());
      expect(parsed.distanceSpeed, 18);
      expect(parsed.bankPerPerson, 3.5);
      expect(parsed.source, 'ctrl-test');
    });
  });
}
