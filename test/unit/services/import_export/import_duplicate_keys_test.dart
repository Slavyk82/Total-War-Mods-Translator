import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/import_preview_service.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/services/file/file_service_impl.dart';

import '../../../helpers/test_bootstrap.dart';

/// Regression test for the duplicate-key validation bug: `validateImport`
/// previously scanned only `preview.previewRows` (capped at 10 rows), so
/// duplicate keys appearing later in a large file were never reported,
/// giving users a false "no duplicates" signal. These tests pin the
/// whole-file scanning behavior.
void main() {
  late Directory tempDir;
  late ImportPreviewService service;

  setUp(() async {
    await TestBootstrap.registerFakes();
    tempDir = Directory.systemTemp.createTempSync('import_dup_keys_test');
    service = ImportPreviewService(ImportFileReader(FileServiceImpl()));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ImportSettings settings() => const ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        hasHeaderRow: true,
        columnMapping: {
          'key': ImportColumn.key,
          'source': ImportColumn.sourceText,
          'target': ImportColumn.targetText,
        },
      );

  /// Build a CSV file and return a matching preview (preview rows capped at 10,
  /// mirroring `previewImport`).
  Future<File> writeCsv(List<String> keys) async {
    final buffer = StringBuffer('key,source,target\n');
    for (final key in keys) {
      buffer.writeln('$key,source of $key,target of $key');
    }
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  test(
      'reports a duplicate key that appears only after the first 10 preview rows',
      () async {
    // 11 unique keys (rows 1-11) followed by a duplicate of KEY_1 at row 12,
    // i.e. beyond the 10-row preview window.
    final keys = <String>[
      for (var i = 1; i <= 11; i++) 'KEY_$i',
      'KEY_1', // duplicate, lives at row 12 (outside the preview)
    ];
    final file = await writeCsv(keys);

    final previewResult = await service.previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());
    final preview = previewResult.value;

    // Sanity: the duplicate is NOT visible in the capped preview rows.
    expect(preview.previewRows.length, 10);

    final result = await service.validateImport(preview, settings());
    expect(result.isOk, isTrue, reason: result.toString());

    expect(result.value.duplicateKeys, contains('KEY_1'));
    expect(result.value.duplicateKeys.length, 1);
    expect(
      result.value.warnings.any((w) => w.contains('duplicate')),
      isTrue,
    );
  });

  test('reports no duplicates when every key in the file is unique', () async {
    final keys = <String>[for (var i = 1; i <= 25; i++) 'KEY_$i'];
    final file = await writeCsv(keys);

    final previewResult = await service.previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());

    final result = await service.validateImport(
      previewResult.value,
      settings(),
    );
    expect(result.isOk, isTrue, reason: result.toString());

    expect(result.value.duplicateKeys, isEmpty);
    expect(
      result.value.warnings.any((w) => w.contains('duplicate')),
      isFalse,
    );
  });
}
