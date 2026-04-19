import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

import '../../../helpers/noop_logger.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late ValidationRescanService svc;
  late TranslationVersionRepository versionRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> seed({required int legacy, required int migrated}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Shared unit rows — each version links to one.
    for (var i = 0; i < legacy + migrated; i++) {
      await db.insert('translation_units', {
        'id': 'unit-${i.toString().padLeft(4, '0')}',
        'project_id': 'proj-1',
        'key': 'key_$i',
        'source_text': 'Hello $i',
        'is_obsolete': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    for (var i = 0; i < legacy; i++) {
      await db.insert('translation_versions', {
        'id': 'legacy-${i.toString().padLeft(4, '0')}',
        'unit_id': 'unit-${i.toString().padLeft(4, '0')}',
        'project_language_id': 'pl-1',
        'translated_text': 'Bonjour $i',
        'status': 'translated',
        'validation_issues': null,
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    for (var i = 0; i < migrated; i++) {
      await db.insert('translation_versions', {
        'id': 'migrated-${i.toString().padLeft(4, '0')}',
        'unit_id': 'unit-${(legacy + i).toString().padLeft(4, '0')}',
        'project_language_id': 'pl-1',
        'translated_text': 'Bonjour m$i',
        'status': 'translated',
        'validation_issues': null,
        'validation_schema_version': 1,
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

  group('ValidationRescanService.run', () {
    test('processes every legacy row in 100-unit commits', () async {
      await seed(legacy: 250, migrated: 0);

      final events = <RescanProgress>[];
      await for (final p in svc.run()) {
        events.add(p);
      }

      // Commits happen at 100, 200, 250.
      expect(events.map((e) => e.done).toList(), [100, 200, 250]);
      expect(
        (await versionRepo.countLegacyValidationRows()).unwrap(),
        0,
      );
      expect(
        (await versionRepo.countMigratedValidationRows()).unwrap(),
        250,
      );
    });

    test('second run on an already-migrated DB is a no-op', () async {
      await seed(legacy: 0, migrated: 50);

      final events = <RescanProgress>[];
      await for (final p in svc.run()) {
        events.add(p);
      }

      expect(events.length, 1);
      expect(events.first.done, 0);
      expect(events.first.total, 0);
    });

    test('progress is monotonic', () async {
      await seed(legacy: 250, migrated: 0);

      final events = <RescanProgress>[];
      await for (final p in svc.run()) {
        events.add(p);
      }

      for (var i = 1; i < events.length; i++) {
        expect(events[i].done, greaterThanOrEqualTo(events[i - 1].done));
      }
    });

    test('eta becomes non-null after the first commit', () async {
      await seed(legacy: 250, migrated: 0);

      final events = <RescanProgress>[];
      await for (final p in svc.run()) {
        events.add(p);
      }

      expect(events.first.eta, isNotNull);
    });

    test('emitted rows carry structured JSON validation_issues', () async {
      // Seed one row that will fail a rule (empty translated text is tricky
      // because the legacy dataset has translation; use a mismatched marker
      // like a bad encoding char).
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.insert('translation_units', {
        'id': 'unit-bad',
        'project_id': 'proj-1',
        'key': 'bad_key',
        'source_text': 'Hello world',
        'is_obsolete': 0,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('translation_versions', {
        'id': 'bad-v',
        'unit_id': 'unit-bad',
        'project_language_id': 'pl-1',
        'translated_text': 'Bad \uFFFD char',
        'status': 'translated',
        'validation_issues': null,
        'validation_schema_version': 0,
        'created_at': now,
        'updated_at': now,
      });

      await svc.run().drain<void>();

      final rows = await db.rawQuery(
        'SELECT validation_issues, validation_schema_version '
        'FROM translation_versions WHERE id = ?',
        ['bad-v'],
      );
      final row = rows.single;
      expect(row['validation_schema_version'], 1);
      final payload = row['validation_issues'] as String;
      final parsed = jsonDecode(payload) as List;
      expect(parsed, isNotEmpty);
      final first = parsed.first as Map<String, dynamic>;
      expect(first, containsPair('rule', isA<String>()));
      expect(first, containsPair('severity', isA<String>()));
      expect(first, containsPair('message', isA<String>()));
    });
  });

  group('ValidationRescanService.buildPlan', () {
    test('returns null when no legacy rows remain', () async {
      await seed(legacy: 0, migrated: 10);
      expect(await svc.buildPlan(), isNull);
    });

    test('reports totals and resume state', () async {
      await seed(legacy: 30, migrated: 5);
      final plan = await svc.buildPlan();
      expect(plan, isNotNull);
      expect(plan!.total, 30);
      expect(plan.already, 5);
      expect(plan.isResume, isTrue);
      expect(plan.estimated.inMicroseconds, greaterThan(0));
    });
  });
}
