import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/validation/validation_schema.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Seed 180 legacy rows (schema_version = 0) and 70 migrated (= current).
    for (var i = 0; i < 180; i++) {
      await db.insert('translation_versions', {
        'id': 'legacy-${i.toString().padLeft(4, '0')}',
        'unit_id': 'unit-$i',
        'project_language_id': 'pl-1',
        'translated_text': 'translation $i',
        'status': 'needs_review',
        'validation_issues': '[msg]',
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    for (var i = 0; i < 70; i++) {
      await db.insert('translation_versions', {
        'id': 'migrated-${i.toString().padLeft(4, '0')}',
        'unit_id': 'unit-m$i',
        'project_language_id': 'pl-1',
        'translated_text': 'translation m$i',
        'status': 'translated',
        'validation_issues': null,
        'validation_schema_version': kCurrentValidationSchemaVersion,
        'created_at': now,
        'updated_at': now,
      });
    }
  });

  tearDown(() => TestDatabase.close(db));

  test('countLegacyValidationRows returns only below-current translated rows',
      () async {
    final r = await repo.countLegacyValidationRows();
    expect(r.unwrap(), 180);
  });

  test('countMigratedValidationRows returns rows at the current version',
      () async {
    final r = await repo.countMigratedValidationRows();
    expect(r.unwrap(), 70);
  });

  test('getLegacyValidationPage returns pages in stable id order without overlap',
      () async {
    final page1 =
        (await repo.getLegacyValidationPage(limit: 100)).unwrap();
    final page2 = (await repo.getLegacyValidationPage(
      limit: 100,
      afterId: page1.last.id,
    ))
        .unwrap();
    expect(page1.length, 100);
    expect(page2.length, 80);
    final ids = {...page1.map((v) => v.id), ...page2.map((v) => v.id)};
    expect(ids.length, 180, reason: 'pages must not overlap');
    // Only legacy ids surface.
    expect(
      ids.every((id) => id.startsWith('legacy-')),
      isTrue,
      reason: 'migrated rows should not be returned',
    );
  });

  test('updateValidationBatch bumps validation_schema_version to current',
      () async {
    final page = (await repo.getLegacyValidationPage(limit: 10)).unwrap();
    final updates = page
        .map((v) => (
              versionId: v.id,
              status: 'translated',
              validationIssues: '[]',
              schemaVersion: kCurrentValidationSchemaVersion,
            ))
        .toList();

    final result = await repo.updateValidationBatch(updates);
    expect(result.unwrap(), 10);
    expect((await repo.countLegacyValidationRows()).unwrap(), 170);
    expect((await repo.countMigratedValidationRows()).unwrap(), 80);
  });
}
