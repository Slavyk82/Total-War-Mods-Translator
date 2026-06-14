import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project_publication.dart';

void main() {
  group('ProjectPublication', () {
    test('round-trips through json with snake_case keys', () {
      const pub = ProjectPublication(
        projectId: 'p1',
        languageCode: 'fr',
        steamId: '3664274763',
        publishedAt: 1777103299,
      );

      final json = pub.toJson();
      expect(json, {
        'project_id': 'p1',
        'language_code': 'fr',
        'steam_id': '3664274763',
        'published_at': 1777103299,
      });

      final parsed = ProjectPublication.fromJson(json);
      expect(parsed.projectId, 'p1');
      expect(parsed.languageCode, 'fr');
      expect(parsed.steamId, '3664274763');
      expect(parsed.publishedAt, 1777103299);
    });

    test('tolerates null steam_id and published_at', () {
      final parsed = ProjectPublication.fromJson({
        'project_id': 'p1',
        'language_code': 'de',
        'steam_id': null,
        'published_at': null,
      });
      expect(parsed.steamId, isNull);
      expect(parsed.publishedAt, isNull);
    });
  });
}
