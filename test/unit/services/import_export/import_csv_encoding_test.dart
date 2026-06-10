import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/services/file/file_service_impl.dart';

import '../../../helpers/test_bootstrap.dart';

/// Regression tests for F9: `ImportFileReader.readFile` ignored
/// `settings.encoding`, so a UTF-16 CSV (the common encoding for Total War
/// .loc exports opened/saved on Windows) was decoded as UTF-8 and produced
/// mojibake or a hard read failure. The user-visible encoding setting was
/// dead.
void main() {
  late Directory tempDir;
  late ImportFileReader reader;

  setUp(() async {
    await TestBootstrap.registerFakes();
    tempDir = Directory.systemTemp.createTempSync('import_csv_encoding_test');
    reader = ImportFileReader(FileServiceImpl());
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ImportSettings settings({required String encoding}) => ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        encoding: encoding,
        hasHeaderRow: true,
        columnMapping: const {
          'key': ImportColumn.key,
          'source': ImportColumn.sourceText,
          'target': ImportColumn.targetText,
        },
      );

  /// Encode [content] as UTF-16LE with a BOM (FF FE), the standard Windows
  /// "Unicode" text format.
  List<int> utf16LeWithBom(String content) {
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in content.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }

  test("settings.encoding='utf-16' decodes a UTF-16LE BOM CSV correctly",
      () async {
    const csv = 'key,source,target\nKEY_1,sword,épée\n';
    final file = File('${tempDir.path}/utf16le.csv');
    await file.writeAsBytes(utf16LeWithBom(csv));

    final result =
        await reader.readFile(file.path, settings(encoding: 'utf-16'));

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.rows, hasLength(1));
    expect(result.value.rows.first['key'], 'KEY_1');
    expect(result.value.rows.first['target'], 'épée');
  });

  test("settings.encoding='utf-16' decodes a UTF-16BE BOM CSV correctly",
      () async {
    const csv = 'key,source,target\nKEY_1,sword,épée\n';
    final bytes = <int>[0xFE, 0xFF];
    for (final unit in csv.codeUnits) {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
    final file = File('${tempDir.path}/utf16be.csv');
    await file.writeAsBytes(bytes);

    final result =
        await reader.readFile(file.path, settings(encoding: 'utf-16'));

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.rows, hasLength(1));
    expect(result.value.rows.first['target'], 'épée');
  });

  test("default settings.encoding='utf-8' still reads UTF-8 (with BOM) CSV",
      () async {
    const csv = '﻿key,source,target\nKEY_1,sword,épée\n';
    final file = File('${tempDir.path}/utf8.csv');
    await file.writeAsBytes(utf8.encode(csv));

    final result =
        await reader.readFile(file.path, settings(encoding: 'utf-8'));

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.rows, hasLength(1));
    expect(result.value.rows.first['key'], 'KEY_1');
    expect(result.value.rows.first['target'], 'épée');
  });
}
