import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/repositories/export_history_repository.dart';

import '../../helpers/test_database.dart';

/// Sentinel to distinguish "argument omitted" from "explicitly null".
const Object _unset = Object();

void main() {
  late Database db;
  late ExportHistoryRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ExportHistoryRepository();
    // The export_history table is NOT created by schema.sql or any migration;
    // the repository owns its DDL via ensureTableExists().
    await repository.ensureTableExists();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ExportHistoryRepository', () {
    ExportHistory createTestExport({
      String? id,
      String? projectId,
      String? languages,
      ExportFormat? format,
      bool? validatedOnly,
      String? outputPath,
      // Sentinel default so callers can pass an explicit null fileSize.
      Object? fileSize = _unset,
      int? entryCount,
      int? exportedAt,
    }) {
      return ExportHistory(
        id: id ?? 'export-id',
        projectId: projectId ?? 'project-1',
        languages: languages ?? '["en","fr"]',
        format: format ?? ExportFormat.csv,
        validatedOnly: validatedOnly ?? false,
        outputPath: outputPath ?? 'C:\\exports\\output.csv',
        fileSize: identical(fileSize, _unset) ? 1024 : fileSize as int?,
        entryCount: entryCount ?? 42,
        exportedAt: exportedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }

    group('ensureTableExists', () {
      test('is idempotent (CREATE TABLE IF NOT EXISTS)', () async {
        // setUp already called it once. Calling again must not throw.
        await repository.ensureTableExists();
        await repository.ensureTableExists();

        // Table is usable after repeated calls.
        final maps = await db.query('export_history');
        expect(maps, isEmpty);
      });

      test('CHECK constraint rejects an invalid format', () async {
        // Sanity-check that the table's CHECK(format IN (...)) is in force.
        // Bypass the model (which can only build valid formats) with raw SQL.
        expect(
          () => db.rawInsert(
            'INSERT INTO export_history '
            '(id, project_id, languages, format, validated_only, output_path, entry_count, exported_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            ['bad', 'p', '[]', 'pdf', 0, 'out', 1, 1000],
          ),
          throwsA(anything),
        );
      });
    });

    group('insert', () {
      test('should insert an export record successfully', () async {
        final export = createTestExport();

        final result = await repository.insert(export);

        expect(result.isOk, isTrue);
        expect(result.value, equals(export));

        final maps =
            await db.query('export_history', where: 'id = ?', whereArgs: [export.id]);
        expect(maps.length, equals(1));
        expect(maps.first['project_id'], equals('project-1'));
        expect(maps.first['format'], equals('csv'));
        // BoolIntConverter stores false as 0.
        expect(maps.first['validated_only'], equals(0));
      });

      test('should fail when inserting duplicate ID', () async {
        final export = createTestExport();
        await repository.insert(export);

        final duplicate = createTestExport(outputPath: 'C:\\other.csv');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should store validatedOnly true as integer 1', () async {
        final export = createTestExport(id: 'validated', validatedOnly: true);

        final result = await repository.insert(export);

        expect(result.isOk, isTrue);
        final maps = await db
            .query('export_history', where: 'id = ?', whereArgs: ['validated']);
        expect(maps.first['validated_only'], equals(1));
      });
    });

    group('getById', () {
      test('should return export when found', () async {
        final export = createTestExport();
        await repository.insert(export);

        final result = await repository.getById(export.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(export.id));
        expect(result.value.format, equals(ExportFormat.csv));
        expect(result.value.validatedOnly, isFalse);
      });

      test('should return error when export not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no exports exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all exports ordered by exported_at DESC', () async {
        await repository.insert(createTestExport(id: 'e1', exportedAt: 1000));
        await repository.insert(createTestExport(id: 'e2', exportedAt: 3000));
        await repository.insert(createTestExport(id: 'e3', exportedAt: 2000));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('e2')); // newest first
        expect(result.value[1].id, equals('e3'));
        expect(result.value[2].id, equals('e1'));
      });
    });

    group('update', () {
      test('should update export successfully', () async {
        final export = createTestExport();
        await repository.insert(export);

        final updated = export.copyWith(entryCount: 99, fileSize: 2048);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.entryCount, equals(99));

        final getResult = await repository.getById(export.id);
        expect(getResult.value.entryCount, equals(99));
        expect(getResult.value.fileSize, equals(2048));
      });

      test('should be a no-op (still Ok) when id does not exist', () async {
        // update() issues an UPDATE ... WHERE id = ? which affects 0 rows
        // for a missing id. The repository does not treat that as an error.
        final export = createTestExport(id: 'non-existent');

        final result = await repository.update(export);

        expect(result.isOk, isTrue);
        // Nothing was actually written.
        final getResult = await repository.getById('non-existent');
        expect(getResult.isErr, isTrue);
      });
    });

    group('delete', () {
      test('should delete export successfully', () async {
        final export = createTestExport();
        await repository.insert(export);

        final result = await repository.delete(export.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(export.id);
        expect(getResult.isErr, isTrue);
      });

      test('should be a no-op (still Ok) when id does not exist', () async {
        // delete() affects 0 rows for a missing id and reports Ok.
        final result = await repository.delete('non-existent-id');

        expect(result.isOk, isTrue);
      });
    });

    group('getByProject', () {
      test('should return only exports for the given project, newest first',
          () async {
        await repository.insert(
            createTestExport(id: 'a', projectId: 'p1', exportedAt: 1000));
        await repository.insert(
            createTestExport(id: 'b', projectId: 'p1', exportedAt: 2000));
        await repository.insert(
            createTestExport(id: 'c', projectId: 'p2', exportedAt: 5000));

        final result = await repository.getByProject('p1');

        expect(result.length, equals(2));
        expect(result[0].id, equals('b')); // newest first
        expect(result[1].id, equals('a'));
      });

      test('should return empty list when project has no exports', () async {
        await repository.insert(createTestExport(projectId: 'p1'));

        final result = await repository.getByProject('unknown-project');

        expect(result, isEmpty);
      });
    });

    group('getByFormat', () {
      test('should return only exports matching the given format', () async {
        await repository
            .insert(createTestExport(id: 'csv1', format: ExportFormat.csv));
        await repository
            .insert(createTestExport(id: 'pack1', format: ExportFormat.pack));
        await repository
            .insert(createTestExport(id: 'tmx1', format: ExportFormat.tmx));

        final result = await repository.getByFormat(ExportFormat.pack);

        expect(result.length, equals(1));
        expect(result.first.id, equals('pack1'));
        expect(result.first.format, equals(ExportFormat.pack));
      });

      test('should return empty list when no export uses the format', () async {
        await repository.insert(createTestExport(format: ExportFormat.csv));

        final result = await repository.getByFormat(ExportFormat.excel);

        expect(result, isEmpty);
      });
    });

    group('getRecent', () {
      test('should respect the limit and return newest first', () async {
        for (var i = 0; i < 5; i++) {
          await repository.insert(
              createTestExport(id: 'r$i', exportedAt: 1000 + i));
        }

        final result = await repository.getRecent(limit: 3);

        expect(result.length, equals(3));
        expect(result[0].id, equals('r4')); // newest
        expect(result[1].id, equals('r3'));
        expect(result[2].id, equals('r2'));
      });

      test('should default to limit 10 and return all when fewer exist',
          () async {
        await repository.insert(createTestExport(id: 'only', exportedAt: 1000));

        final result = await repository.getRecent();

        expect(result.length, equals(1));
        expect(result.first.id, equals('only'));
      });

      test('should return empty list when no exports exist', () async {
        final result = await repository.getRecent();

        expect(result, isEmpty);
      });
    });

    group('getLastPackExportByProject', () {
      test('should return the most recent pack export for the project',
          () async {
        await repository.insert(createTestExport(
            id: 'pack-old',
            projectId: 'p1',
            format: ExportFormat.pack,
            exportedAt: 1000));
        await repository.insert(createTestExport(
            id: 'pack-new',
            projectId: 'p1',
            format: ExportFormat.pack,
            exportedAt: 5000));
        // A newer non-pack export must be ignored.
        await repository.insert(createTestExport(
            id: 'csv-newest',
            projectId: 'p1',
            format: ExportFormat.csv,
            exportedAt: 9000));

        final result = await repository.getLastPackExportByProject('p1');

        expect(result, isNotNull);
        expect(result!.id, equals('pack-new'));
        expect(result.format, equals(ExportFormat.pack));
      });

      test('should return null when project has no pack export', () async {
        await repository.insert(createTestExport(
            projectId: 'p1', format: ExportFormat.csv));

        final result = await repository.getLastPackExportByProject('p1');

        expect(result, isNull);
      });
    });

    group('deleteOlderThan', () {
      test('should delete only records older than the cutoff and return count',
          () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final old = now - (40 * 24 * 60 * 60); // 40 days ago
        final recent = now - (5 * 24 * 60 * 60); // 5 days ago

        await repository.insert(createTestExport(id: 'old1', exportedAt: old));
        await repository.insert(createTestExport(id: 'old2', exportedAt: old));
        await repository
            .insert(createTestExport(id: 'recent1', exportedAt: recent));

        final deleted = await repository.deleteOlderThan(days: 30);

        expect(deleted, equals(2));

        final remaining = await repository.getAll();
        expect(remaining.value.length, equals(1));
        expect(remaining.value.first.id, equals('recent1'));
      });

      test('should return 0 when nothing is older than the cutoff', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await repository.insert(createTestExport(id: 'fresh', exportedAt: now));

        final deleted = await repository.deleteOlderThan(days: 30);

        expect(deleted, equals(0));
        final remaining = await repository.getAll();
        expect(remaining.value.length, equals(1));
      });
    });

    group('round-trip mapping', () {
      test('should preserve all fields through insert + getById', () async {
        final export = createTestExport(
          id: 'roundtrip',
          projectId: 'proj-x',
          languages: '["en","de","ja"]',
          format: ExportFormat.tmx,
          validatedOnly: true,
          outputPath: 'D:\\path\\file.tmx',
          fileSize: 7777,
          entryCount: 123,
          exportedAt: 1700000000,
        );
        await repository.insert(export);

        final result = await repository.getById('roundtrip');

        expect(result.isOk, isTrue);
        expect(result.value, equals(export));
        expect(result.value.languagesList, equals(['en', 'de', 'ja']));
      });

      test('should preserve null fileSize', () async {
        final export = createTestExport(id: 'no-size', fileSize: null);
        await repository.insert(export);

        final result = await repository.getById('no-size');

        expect(result.isOk, isTrue);
        expect(result.value.fileSize, isNull);
      });
    });
  });
}
