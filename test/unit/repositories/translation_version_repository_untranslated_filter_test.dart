import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Seed a unit + its translation_version row in a single call.
  Future<void> seed({
    required String unitId,
    required String sourceText,
    required String projectLanguageId,
    required String status,
    String? translatedText,
    int isObsolete = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('translation_units', {
      'id': unitId,
      'project_id': 'proj-1',
      'key': 'k-$unitId',
      'source_text': sourceText,
      'is_obsolete': isObsolete,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('translation_versions', {
      'id': '$unitId-v',
      'unit_id': unitId,
      'project_language_id': projectLanguageId,
      'translated_text': translatedText,
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
  }

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();

    // Rows that must be RETURNED by the two queries:
    await seed(
      unitId: 'u-pending',
      sourceText: 'normal source',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-translating',
      sourceText: 'normal source 2',
      projectLanguageId: 'pl-1',
      status: 'translating',
      translatedText: null,
    );

    // Rows that must be EXCLUDED:
    await seed(
      unitId: 'u-translated-with-text',
      sourceText: 'normal source 3',
      projectLanguageId: 'pl-1',
      status: 'translated',
      translatedText: 'done',
    );
    await seed(
      unitId: 'u-translated-empty',
      sourceText: 'normal source 4',
      projectLanguageId: 'pl-1',
      status: 'translated', // Status/text inconsistency.
      translatedText: '',
    );
    await seed(
      unitId: 'u-needs-review',
      sourceText: 'normal source 5',
      projectLanguageId: 'pl-1',
      status: 'needs_review',
      translatedText: 'needs review text',
    );
    await seed(
      unitId: 'u-hidden',
      sourceText: '[HIDDEN] ui key',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-bracketed',
      sourceText: '[ok]',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-skip-text',
      // Matches `TranslationSkipFilter`'s fallback default `placeholder`.
      sourceText: 'placeholder',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-obsolete',
      sourceText: 'normal source 6',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
      isObsolete: 1,
    );
    await seed(
      unitId: 'u-wrong-lang',
      sourceText: 'normal source 7',
      projectLanguageId: 'pl-OTHER',
      status: 'pending',
      translatedText: '',
    );
  });

  tearDown(() => TestDatabase.close(db));

  group('getUntranslatedIds', () {
    test('returns only pending and translating rows that pass the skip filter',
        () async {
      final result = await repo.getUntranslatedIds(projectLanguageId: 'pl-1');
      final ids = result.unwrap().toSet();

      expect(ids, {'u-pending', 'u-translating'});
    });
  });

  group('filterUntranslatedIds', () {
    test('mirrors getUntranslatedIds when the input covers every seeded unit',
        () async {
      final inputIds = [
        'u-pending',
        'u-translating',
        'u-translated-with-text',
        'u-translated-empty',
        'u-needs-review',
        'u-hidden',
        'u-bracketed',
        'u-skip-text',
        'u-obsolete',
        'u-wrong-lang',
      ];

      final result = await repo.filterUntranslatedIds(
        ids: inputIds,
        projectLanguageId: 'pl-1',
      );
      final ids = result.unwrap().toSet();

      expect(ids, {'u-pending', 'u-translating'});
    });

    test('returns empty list when the input list is empty', () async {
      final result = await repo.filterUntranslatedIds(
        ids: const [],
        projectLanguageId: 'pl-1',
      );
      expect(result.unwrap(), isEmpty);
    });
  });
}
