import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/platform/game_launcher_opener.dart';

void main() {
  group('buildSteamRunUri', () {
    test('returns the Steam scheme URI for a given app id', () {
      final uri = buildSteamRunUri('1142710');
      expect(uri.scheme, 'steam');
      expect(uri.host, 'run');
      expect(uri.path, '/1142710');
    });

    test('throws on empty app id', () {
      expect(() => buildSteamRunUri(''), throwsArgumentError);
    });

    test('throws on whitespace-only app id', () {
      expect(() => buildSteamRunUri('   '), throwsArgumentError);
    });

    test('toString round-trips to steam://run/<id>', () {
      expect(buildSteamRunUri('123').toString(), 'steam://run/123');
    });
  });
}
