import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/models/import_preview.dart';
import 'package:twmt/features/import_export/services/import_preview_service.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/services/file/file_service_impl.dart';

import '../../../helpers/test_bootstrap.dart';

/// Unit tests for [ImportPreviewService]. previewImport/validateImport are pure
/// file+logic operations (no database), so a real [FileServiceImpl] over a temp
/// file is enough. Covers the file-not-found guard, the preview row cap /
/// content-hash, and every validateImport branch (missing key column, missing
/// source/target, duplicate-key scan across the whole file, and the read-error
/// propagation).
void main() {
  late Directory tempDir;
  late ImportPreviewService service;

  setUp(() async {
    // FileServiceImpl resolves an ILoggingService from the ServiceLocator on
    // construction; register the baseline fakes so it can be built without a DB.
    await TestBootstrap.registerFakes();
    tempDir = Directory.systemTemp.createTempSync('import_preview_svc_test');
    service = ImportPreviewService(ImportFileReader(FileServiceImpl()));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ImportSettings settings({
    Map<String, ImportColumn>? columnMapping,
    ImportValidationOptions validationOptions = const ImportValidationOptions(),
  }) =>
      ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        hasHeaderRow: true,
        columnMapping: columnMapping ??
            const {
              'key': ImportColumn.key,
              'source': ImportColumn.sourceText,
              'target': ImportColumn.targetText,
            },
        validationOptions: validationOptions,
      );

  Future<File> writeCsv(String content) async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString(content);
    return file;
  }

  group('previewImport', () {
    test('returns a not-found error for a missing file', () async {
      final result = await service.previewImport(
        '${tempDir.path}/does_not_exist.csv',
        settings(),
      );
      expect(result.isErr, isTrue);
      expect(result.error.message, contains('File not found'));
    });

    test('caps preview rows at 10, counts all rows, and records a content hash',
        () async {
      final buffer = StringBuffer('key,source,target\n');
      for (var i = 0; i < 12; i++) {
        buffer.writeln('K$i,Source$i,Target$i');
      }
      final file = await writeCsv(buffer.toString());

      final result = await service.previewImport(file.path, settings());

      expect(result.isOk, isTrue, reason: result.toString());
      final preview = result.value;
      expect(preview.totalRows, 12);
      expect(preview.previewRows, hasLength(10)); // capped
      expect(preview.headers, ['key', 'source', 'target']);
      expect(preview.fileSize, greaterThan(0));
      expect(preview.contentHash, isNotNull);
      expect(preview.suggestedMapping, isNotEmpty);
      expect(preview.suggestedMapping['key'], 'key');
    });
  });

  group('validateImport', () {
    ImportPreview previewFor(File file) => ImportPreview(
          filePath: file.path,
          headers: const ['key', 'source', 'target'],
          previewRows: const [],
          totalRows: 0,
          fileSize: 0,
          encoding: 'utf-8',
        );

    test('missing key column yields an error and a missing "key" column',
        () async {
      final file = await writeCsv('source,target\nHello,Bonjour\n');

      final result = await service.validateImport(
        previewFor(file),
        settings(columnMapping: const {
          'source': ImportColumn.sourceText,
          'target': ImportColumn.targetText,
        }),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.isValid, isFalse);
      expect(result.value.errors, contains('Key column mapping is required'));
      expect(result.value.missingColumns, contains('key'));
    });

    test('missing both source and target yields an error', () async {
      final file = await writeCsv('key\nK1\n');

      final result = await service.validateImport(
        previewFor(file),
        settings(columnMapping: const {'key': ImportColumn.key}),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(
        result.value.errors,
        contains('At least one of Source Text or Target Text column is required'),
      );
    });

    test('detects duplicate keys across the whole file (beyond preview rows)',
        () async {
      final buffer = StringBuffer('key,source,target\n');
      for (var i = 0; i < 11; i++) {
        buffer.writeln('K$i,S$i,T$i');
      }
      // A duplicate of K0 appears on row 12, past the 10-row preview window.
      buffer.writeln('K0,S0-again,T0-again');
      final file = await writeCsv(buffer.toString());

      final result =
          await service.validateImport(previewFor(file), settings());

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.isValid, isTrue); // duplicates are warnings, not errors
      expect(result.value.duplicateKeys, contains('K0'));
      expect(result.value.warnings, isNotEmpty);
      expect(result.value.warnings.first, contains('duplicate keys'));
    });

    test('a valid mapping with unique keys passes with no warnings', () async {
      final file = await writeCsv('key,source,target\nK1,S1,T1\nK2,S2,T2\n');

      final result =
          await service.validateImport(previewFor(file), settings());

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.isValid, isTrue);
      expect(result.value.duplicateKeys, isEmpty);
      expect(result.value.warnings, isEmpty);
    });

    test('checkDuplicates disabled skips the duplicate scan', () async {
      final file = await writeCsv('key,source,target\nK1,S1,T1\nK1,S2,T2\n');

      final result = await service.validateImport(
        previewFor(file),
        settings(
          validationOptions:
              const ImportValidationOptions(checkDuplicates: false),
        ),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.duplicateKeys, isEmpty);
    });

    test('a read failure during the duplicate scan surfaces as an error',
        () async {
      // Valid mapping with a key column (so the scan runs) but a missing file.
      final preview = ImportPreview(
        filePath: '${tempDir.path}/missing.csv',
        headers: const ['key'],
        previewRows: const [],
        totalRows: 0,
        fileSize: 0,
        encoding: 'utf-8',
      );

      final result = await service.validateImport(preview, settings());

      expect(result.isErr, isTrue);
    });
  });
}
