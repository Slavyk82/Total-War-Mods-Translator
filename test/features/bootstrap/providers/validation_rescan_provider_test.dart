import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/bootstrap/providers/validation_rescan_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';
import 'package:twmt/services/validation/validation_schema.dart';

import '../../../helpers/noop_logger.dart';
import '../../../helpers/test_database.dart';

/// Regression coverage for the consolidated validation bootstrap.
///
/// Before consolidation, the user saw two sequential popups on startup —
/// `DataMigrationDialog` (step 1 = JSON rewrite) followed by
/// `ValidationRescanDialog` (schema rescan). Both are now owned by the
/// rescan controller. These tests exercise the controller end-to-end with
/// the real in-memory schema.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
  });

  tearDown(() => TestDatabase.close(db));

  /// The marker table is created lazily by the migration; tests that want
  /// to simulate "not yet applied" need to materialize it first, then clear
  /// the row.
  Future<void> clearMigrationMarker(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _migration_markers (
        id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL
      )
    ''');
    await db.delete('_migration_markers',
        where: 'id = ?', whereArgs: ['validation_issues_json']);
  }

  /// Build a container wired with real repositories + a real validation
  /// service, exactly like production but without ServiceLocator plumbing.
  ProviderContainer makeContainer() {
    final versionRepo = TranslationVersionRepository();
    final unitRepo = TranslationUnitRepository();
    final container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWith((ref) => versionRepo),
      translationUnitRepositoryProvider.overrideWith((ref) => unitRepo),
      validationRescanServiceProvider.overrideWith((ref) {
        return ValidationRescanService(
          versionRepo: versionRepo,
          unitRepo: unitRepo,
          validation: ValidationServiceImpl(logger: NoopLogger()),
          logger: NoopLogger(),
        );
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seedLegacy({
    required int withLegacyJson,
    required int withLegacySchemaOnly,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var i = 0;
    for (; i < withLegacyJson + withLegacySchemaOnly; i++) {
      await db.insert('translation_units', {
        'id': 'unit-$i',
        'project_id': 'proj-1',
        'key': 'key_$i',
        'source_text': 'Hello $i',
        'is_obsolete': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    i = 0;
    for (; i < withLegacyJson; i++) {
      await db.insert('translation_versions', {
        'id': 'leg-json-$i',
        'unit_id': 'unit-$i',
        'project_language_id': 'pl-1',
        'translated_text': 'Bonjour $i',
        'status': 'translated',
        // Dart-toString legacy payload — the normalization phase targets
        // exactly this shape.
        'validation_issues': '[legacy msg $i, other legacy]',
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    for (var j = 0; j < withLegacySchemaOnly; j++) {
      await db.insert('translation_versions', {
        'id': 'leg-schema-$j',
        'unit_id': 'unit-${withLegacyJson + j}',
        'project_language_id': 'pl-1',
        'translated_text': 'Bonjour s$j',
        'status': 'translated',
        'validation_issues': null,
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  group('ValidationRescanController.hasPendingWork', () {
    test('returns false on a clean migrated DB', () async {
      final c = makeContainer();
      final has = await c
          .read(validationRescanControllerProvider.notifier)
          .hasPendingWork();
      expect(has, isFalse);
    });

    test('returns true when only legacy JSON rows exist', () async {
      // Mark every row as already at current schema_version so the rescan
      // gate is closed — only the JSON rewrite remains pending.
      await seedLegacy(withLegacyJson: 3, withLegacySchemaOnly: 0);
      await db.execute(
          'UPDATE translation_versions SET validation_schema_version = $kCurrentValidationSchemaVersion');
      await clearMigrationMarker(db);

      final c = makeContainer();
      final has = await c
          .read(validationRescanControllerProvider.notifier)
          .hasPendingWork();
      expect(has, isTrue);
    });

    test('returns true when only legacy schema rows exist', () async {
      await seedLegacy(withLegacyJson: 0, withLegacySchemaOnly: 4);
      final c = makeContainer();
      final has = await c
          .read(validationRescanControllerProvider.notifier)
          .hasPendingWork();
      expect(has, isTrue);
    });
  });

  group('ValidationRescanController.prepare', () {
    test('JSON-only DB: normalizes then closes without a plan', () async {
      await seedLegacy(withLegacyJson: 2, withLegacySchemaOnly: 0);
      // Flip schema_version so the rescan has nothing to do.
      await db.execute(
          'UPDATE translation_versions SET validation_schema_version = $kCurrentValidationSchemaVersion');
      await clearMigrationMarker(db);

      final c = makeContainer();

      await c
          .read(validationRescanControllerProvider.notifier)
          .prepare();

      final state = c.read(validationRescanControllerProvider);
      expect(state.isDone, isTrue,
          reason: 'no rescan needed → dialog should close');
      expect(state.plan, isNull);
      expect(state.error, isNull);

      // Legacy payload has been rewritten to real JSON.
      final row = (await db.rawQuery(
              'SELECT validation_issues FROM translation_versions LIMIT 1'))
          .single;
      final decoded = jsonDecode(row['validation_issues'] as String);
      expect(decoded, isA<List>());
    });

    test('both pending: normalizes then exposes a rescan plan', () async {
      await seedLegacy(withLegacyJson: 3, withLegacySchemaOnly: 2);

      final c = makeContainer();

      await c
          .read(validationRescanControllerProvider.notifier)
          .prepare();

      final state = c.read(validationRescanControllerProvider);
      expect(state.isDone, isFalse,
          reason: 'rescan plan is ready — dialog must stay open');
      expect(state.plan, isNotNull);
      expect(state.plan!.total, greaterThan(0));
      expect(state.isNormalizing, isFalse,
          reason: 'normalization phase must be finished before plan shows');

      // Legacy JSON is already normalized by the time the user sees the plan.
      final legacyShapes = await db.rawQuery('''
        SELECT 1 FROM translation_versions
        WHERE validation_issues IS NOT NULL
          AND validation_issues NOT LIKE '["%'
          AND validation_issues NOT LIKE '[]'
          AND validation_issues NOT LIKE '[{"%'
        LIMIT 1
      ''');
      expect(legacyShapes, isEmpty,
          reason: 'JSON normalization must run before the plan is shown');

      // Marker written so next boot short-circuits the normalization phase.
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('clean DB: prepare is a no-op that closes immediately', () async {
      final c = makeContainer();

      await c
          .read(validationRescanControllerProvider.notifier)
          .prepare();

      final state = c.read(validationRescanControllerProvider);
      expect(state.isDone, isTrue);
      expect(state.plan, isNull);
      expect(state.error, isNull);
      expect(state.isNormalizing, isFalse);
    });
  });
}
