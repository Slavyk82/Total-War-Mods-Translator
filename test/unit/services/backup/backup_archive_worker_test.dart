import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/backup/backup_archive_worker.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('twmt_archive_worker_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Incompressible content: deflate cannot shrink random bytes, which
  /// exercises the stored/expanded path through the encoder.
  Uint8List randomBytes(int size, {int seed = 7}) {
    final rnd = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(size, (_) => rnd.nextInt(256)),
    );
  }

  /// Highly compressible content: long runs collapse to almost nothing.
  Uint8List repetitiveBytes(int size) =>
      Uint8List.fromList(List<int>.filled(size, 0x41));

  Future<File> writeSource(String name, Uint8List bytes) async {
    final f = File(path.join(tmp.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  /// Read one entry back out of the produced archive.
  List<int> readEntry(String zipPath, String entryName) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      final entry = archive.files.firstWhere((f) => f.name == entryName);
      return entry.content as List<int>;
    } finally {
      input.closeSync();
    }
  }

  test('round-trips an incompressible entry byte-for-byte', () async {
    final bytes = randomBytes(3 * 1024 * 1024);
    final source = await writeSource('twmt.db', bytes);
    final zipPath = path.join(tmp.path, 'out.zip');

    final warnings = await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    expect(warnings, isEmpty);
    expect(readEntry(zipPath, 'twmt.db'), equals(bytes));
  });

  test('round-trips a highly compressible entry byte-for-byte', () async {
    final bytes = repetitiveBytes(2 * 1024 * 1024);
    final source = await writeSource('twmt.db', bytes);
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    expect(readEntry(zipPath, 'twmt.db'), equals(bytes));
    // Sanity: it really did compress, so the deflate path ran.
    expect(await File(zipPath).length(), lessThan(bytes.length));
  });

  test('writes every source as its own entry, including a zero-byte one',
      () async {
    // Mirrors the legacy checkpoint-and-copy path: a TRUNCATE-checkpointed
    // WAL is zero bytes but must still become a valid entry.
    final db = await writeSource('twmt.db', randomBytes(64 * 1024));
    final wal = await writeSource('twmt.db-wal', Uint8List(0));
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [
        ('twmt.db', db.path),
        ('twmt.db-wal', wal.path),
      ],
      workDirPath: tmp.path,
    );

    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      expect(
        archive.files.map((f) => f.name).toList()..sort(),
        ['twmt.db', 'twmt.db-wal'],
      );
      final walEntry =
          archive.files.firstWhere((f) => f.name == 'twmt.db-wal');
      expect(walEntry.size, 0);
    } finally {
      input.closeSync();
    }
  });

  test('deletes its per-entry deflate temp files', () async {
    final source = await writeSource('twmt.db', randomBytes(128 * 1024));
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.deflate'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('propagates a missing source file as an exception', () async {
    final zipPath = path.join(tmp.path, 'out.zip');

    expect(
      () => writeBackupArchive(
        tempZipPath: zipPath,
        sources: [('twmt.db', path.join(tmp.path, 'does-not-exist.db'))],
        workDirPath: tmp.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
