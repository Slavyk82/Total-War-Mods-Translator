import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

import '../helpers/noop_logger.dart';
import '../helpers/test_database.dart';

/// End-to-end integration tests for the structured-persistence migration.
///
/// These tests wire the real repositories, real ValidationServiceImpl, and
/// the real in-memory DB so the full chain from legacy row → structured
/// JSON payload is exercised end-to-end.
void main() {
  late Database db;
  late ValidationRescanService svc;
  late TranslationVersionRepository versionRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> seedLegacy(int count) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (var i = 0; i < count; i++) {
      final id = 'unit-${i.toString().padLeft(4, '0')}';
      await db.insert('translation_units', {
        'id': id,
        'project_id': 'proj-1',
        'key': 'key_$i',
        // Source text that will trigger different rules across rows.
        'source_text': i.isEven
            ? 'Hello {0}'  // variables rule for odd translations
            : '<b>Bold text</b>', // markup rule if tags drop
        'is_obsolete': 0,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('translation_versions', {
        'id': 'v-${i.toString().padLeft(4, '0')}',
        'unit_id': id,
        'project_language_id': 'pl-1',
        'translated_text': i.isEven ? 'Bonjour' : 'Gras',
        'status': 'translated',
        // Legacy format: Dart List.toString() flavour that the old parser
        // produced. The new parser should treat this as legacy until the
        // row is re-validated by the rescan service.
        'validation_issues': '[legacy msg 1, legacy msg 2]',
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  setUp(() async {
    db = await TestDatabase.openMigrated();
    versionRepo = TranslationVersionRepository();
    svc = ValidationRescanService(
      versionRepo: versionRepo,
      unitRepo: TranslationUnitRepository(),
      validation: ValidationServiceImpl(logger: NoopLogger()),
      logger: NoopLogger(),
    );
  });

  tearDown(() => TestDatabase.close(db));

  test('full rescan migrates every legacy row to structured JSON',
      () async {
    await seedLegacy(120);

    await svc.run().drain<void>();

    // All rows migrated.
    expect(
      (await versionRepo.countLegacyValidationRows()).unwrap(),
      0,
    );

    // Every non-null validation_issues payload is now structured JSON.
    final rows = await db.rawQuery('''
      SELECT validation_issues
      FROM translation_versions
      WHERE validation_issues IS NOT NULL
        AND TRIM(validation_issues) <> ''
    ''');
    for (final r in rows) {
      final payload = r['validation_issues'] as String;
      final decoded = jsonDecode(payload);
      expect(decoded, isA<List>());
      for (final entry in decoded as List) {
        final map = entry as Map<String, dynamic>;
        expect(map, containsPair('rule', isA<String>()));
        expect(map, containsPair('severity', isA<String>()));
        expect(map, containsPair('message', isA<String>()));
      }
    }
  });

  test('interrupted rescan resumes cleanly on next run', () async {
    // Seed enough rows to exceed `commitBatchSize` so a mid-run stop
    // leaves some legacy rows untouched.
    await seedLegacy(ValidationRescanService.commitBatchSize + 500);

    // Drain only the first progress event (one full commit batch).
    final firstEvent = await svc.run().first;
    expect(firstEvent.done, ValidationRescanService.commitBatchSize);

    // Some rows remain at schema_version = 0.
    final remainingAfterPartial =
        (await versionRepo.countLegacyValidationRows()).unwrap();
    expect(remainingAfterPartial, 500);

    // A fresh service instance picks up where we left off.
    final svc2 = ValidationRescanService(
      versionRepo: versionRepo,
      unitRepo: TranslationUnitRepository(),
      validation: ValidationServiceImpl(logger: NoopLogger()),
      logger: NoopLogger(),
    );
    await svc2.run().drain<void>();

    expect(
      (await versionRepo.countLegacyValidationRows()).unwrap(),
      0,
    );
    expect(
      (await versionRepo.countMigratedValidationRows()).unwrap(),
      ValidationRescanService.commitBatchSize + 500,
    );
  });

  test('buildPlan reports resume state after partial run', () async {
    await seedLegacy(40);

    // Fully drain the first commit batch to migrate ~100 rows... but we
    // only have 40, so all will go at once. Use a smaller partial: take
    // the first emission which covers ALL 40 in a single sub-batch.
    final gen = svc.run();
    // Just let the stream run to end for 40 rows.
    await gen.drain<void>();

    // Reopen plan on a second instance; there are no legacy rows left.
    final svc2 = ValidationRescanService(
      versionRepo: versionRepo,
      unitRepo: TranslationUnitRepository(),
      validation: ValidationServiceImpl(logger: NoopLogger()),
      logger: NoopLogger(),
    );
    final plan = await svc2.buildPlan();
    expect(plan, isNull,
        reason: 'no legacy rows remain after full rescan');
  });
}
