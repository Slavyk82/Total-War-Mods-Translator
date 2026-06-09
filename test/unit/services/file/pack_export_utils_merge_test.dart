import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/pack_export_utils.dart';

import '../../../helpers/noop_logger.dart';

/// Build a TSV file on disk in RPFM format and return a [GeneratedLocFile]
/// pointing at it with the given [internalPath].
Future<GeneratedLocFile> _writeTsv(
  Directory dir,
  String name,
  String internalPath,
  List<MapEntry<String, String>> rows,
) async {
  final buffer = StringBuffer();
  buffer.writeln('key\ttext\ttooltip');
  buffer.writeln('#Loc;1;$internalPath\t\t');
  for (final row in rows) {
    buffer.writeln('${row.key}\t${row.value}\tfalse');
  }
  final file = File(path.join(dir.path, name));
  await file.writeAsString(buffer.toString(), flush: true);
  return GeneratedLocFile(tsvPath: file.path, internalPath: internalPath);
}

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late PackExportUtils utils;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('twmt_merge_test_');
    sourceDir = await Directory.systemTemp.createTemp('twmt_merge_src_');
    utils = PackExportUtils(logger: NoopLogger());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    if (await sourceDir.exists()) {
      await sourceDir.delete(recursive: true);
    }
  });

  test('(a) internal path with double underscores is preserved exactly',
      () async {
    const internalPath = 'text/db/some__name.loc';
    final gen = await _writeTsv(
      sourceDir,
      'a.tsv',
      internalPath,
      [const MapEntry('k1', 'v1')],
    );

    await utils.copyTsvFilesToPackStructure([gen], tempDir);

    // File lands under the internal .loc path with a trailing .tsv extension
    // so createPack's `.tsv` filter matches and `--tsv-to-binary` runs.
    final expectedPath =
        path.join(tempDir.path, 'text', 'db', 'some__name.loc.tsv');
    expect(File(expectedPath).existsSync(), isTrue,
        reason: 'File must land at exactly $expectedPath without splitting __');

    // The wrongly-split path must NOT exist.
    final wrongPath =
        path.join(tempDir.path, 'text', 'db', 'some', 'name.loc');
    expect(File(wrongPath).existsSync(), isFalse);
  });

  test('(b) same internalPath, different keys -> merged file has both keys',
      () async {
    const internalPath = 'text/db/merge.loc';
    final genA = await _writeTsv(
      sourceDir,
      'a.tsv',
      internalPath,
      [const MapEntry('alpha', 'A')],
    );
    final genB = await _writeTsv(
      sourceDir,
      'b.tsv',
      internalPath,
      [const MapEntry('beta', 'B')],
    );

    await utils.copyTsvFilesToPackStructure([genA, genB], tempDir);

    final target =
        File(path.join(tempDir.path, 'text', 'db', 'merge.loc.tsv'));
    final lines = await target.readAsLines();

    expect(lines[0], 'key\ttext\ttooltip');
    expect(lines[1], '#Loc;1;$internalPath\t\t');

    final dataRows = lines.skip(2).where((l) => l.isNotEmpty).toList();
    expect(dataRows, contains('alpha\tA\tfalse'));
    expect(dataRows, contains('beta\tB\tfalse'));
    expect(dataRows.length, 2);
  });

  test('(c) duplicate key across files -> single row, first file wins',
      () async {
    const internalPath = 'text/db/dup.loc';
    final genA = await _writeTsv(
      sourceDir,
      'a.tsv',
      internalPath,
      [const MapEntry('shared', 'FIRST')],
    );
    final genB = await _writeTsv(
      sourceDir,
      'b.tsv',
      internalPath,
      [const MapEntry('shared', 'SECOND')],
    );

    await utils.copyTsvFilesToPackStructure([genA, genB], tempDir);

    final target = File(path.join(tempDir.path, 'text', 'db', 'dup.loc.tsv'));
    final lines = await target.readAsLines();
    final dataRows = lines.skip(2).where((l) => l.isNotEmpty).toList();

    expect(dataRows.length, 1);
    expect(dataRows.single, 'shared\tFIRST\tfalse');
  });
}
