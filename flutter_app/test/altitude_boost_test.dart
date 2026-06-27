import 'package:flutter_test/flutter_test.dart';
import 'package:planecrash/models/broadcast_message.dart';

void main() {
  group('AltitudeBoost.fromJson', () {
    test('round-trips source', () {
      const boost = AltitudeBoost(source: 'ctrl-test');
      final parsed = AltitudeBoost.fromJson(boost.toJson());
      expect(parsed.source, 'ctrl-test');
    });
  });
}
