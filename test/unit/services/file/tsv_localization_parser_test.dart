import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/tsv_localization_parser.dart';

// Regression tests for TsvLocalizationParser data fidelity: the RPFM .loc.tsv
// `text` column (parts[1]) must be imported verbatim. Two historical bugs:
//  - rows whose text was literally "false" were dropped (the boolean tooltip
//    flag lives in parts[2], not the text column);
//  - leading/trailing whitespace was trimmed off the value, diverging from the
//    binary .loc parser and silently altering strings on re-export.

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tsv_loc_parser_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeTsv(String content) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}text_en.loc.tsv');
    await file.writeAsString(content);
    return file;
  }

  test('imports an entry whose text is literally "false"', () async {
    final file = await writeTsv(
      'key\ttext\ttooltip\n'
      '#Loc;1;loc_PackedFile\n'
      'option_disabled\tfalse\ttrue\n'
      'unit_name\tSwordsmen\tfalse\n',
    );

    final parser = TsvLocalizationParser();
    final result = await parser.parseFile(filePath: file.path);

    expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
    final entries = result.value.entries;
    final disabled = entries.where((e) => e.key == 'option_disabled');
    expect(disabled, hasLength(1),
        reason: 'A source string of "false" must not be dropped on import');
    expect(disabled.single.value, 'false');
  });

  test('preserves significant leading/trailing whitespace in the value',
      () async {
    final file = await writeTsv(
      'key\ttext\ttooltip\n'
      '#Loc;1;loc_PackedFile\n'
      'frag_of\t of \ttrue\n',
    );

    final parser = TsvLocalizationParser();
    final result = await parser.parseFile(filePath: file.path);

    expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
    final entry = result.value.entries.singleWhere((e) => e.key == 'frag_of');
    expect(entry.value, ' of ',
        reason: 'Leading/trailing spaces are data and must be preserved');
  });
}
