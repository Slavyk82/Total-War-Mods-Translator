import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
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

  // C1 regression: write basis must be target languages, not export languages.
  group('ProjectPublishItem.publicationLanguageCode (C1 regression)', () {
    test('publicationLanguageCode uses target languages, not export languages',
        () {
      // Export pack was generated for 'en' only; target languages include 'fr'.
      final enOnlyExport = ExportHistory(
        id: 'e1',
        projectId: 'p',
        languages: '["en"]', // languagesList returns ['en']
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:/out.pack',
        entryCount: 10,
        exportedAt: 1000,
      );

      final item = ProjectPublishItem(
        export: enOnlyExport,
        project: Project(
          id: 'p',
          name: 'P',
          gameInstallationId: 'g',
          createdAt: 0,
          updatedAt: 0,
        ),
        languageCodes: const ['en', 'fr'],
      );

      // Confirm the export drives languagesList (en-only pack).
      expect(item.languagesList, ['en']);

      // But the write key must be derived from target languages (prefers 'fr').
      expect(item.publicationLanguageCode, 'fr');
    });
  });
}
