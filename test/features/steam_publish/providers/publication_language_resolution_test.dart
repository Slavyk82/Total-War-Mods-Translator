import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project_publication.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';

void main() {
  group('resolvePublicationLanguage', () {
    test('prefers fr when present among targets', () {
      expect(resolvePublicationLanguage(['de', 'fr', 'es']), 'fr');
    });
    test('falls back to first target when no fr', () {
      expect(resolvePublicationLanguage(['de', 'es']), 'de');
    });
    test('defaults to fr when no targets', () {
      expect(resolvePublicationLanguage([]), 'fr');
    });
  });

  group('resolvePublication', () {
    final frRow = const ProjectPublication(
        projectId: 'p', languageCode: 'fr', steamId: '111', publishedAt: 5);
    final deRow = const ProjectPublication(
        projectId: 'p', languageCode: 'de', steamId: '222', publishedAt: 9);

    test('returns null when no rows', () {
      expect(resolvePublication([], ['fr']), isNull);
    });
    test('matches the resolved target language', () {
      expect(resolvePublication([deRow, frRow], ['fr'])?.steamId, '111');
    });
    test('falls back to first row when no language match', () {
      expect(resolvePublication([deRow], ['fr'])?.steamId, '222');
    });
  });
}
