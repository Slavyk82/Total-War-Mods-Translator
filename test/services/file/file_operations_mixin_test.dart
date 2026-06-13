import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/mixins/file_operations_mixin.dart';

/// Concrete host so the mixin can be exercised directly.
class _Ops with FileOperationsMixin {}

void main() {
  late Directory tempDir;
  late _Ops ops;

  setUp(() async {
    ops = _Ops();
    tempDir = await Directory.systemTemp.createTemp('file_ops_mixin_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String pathIn(String name) => p.join(tempDir.path, name);

  group('readFileContent', () {
    test('reads UTF-8 text content', () async {
      final file = pathIn('hello.txt');
      await File(file).writeAsString('héllo wörld');

      final result = await ops.readFileContent(filePath: file);

      expect(result, isA<Ok>());
      expect(result.value, 'héllo wörld');
    });

    test('returns FileNotFoundException for a missing file', () async {
      final result = await ops.readFileContent(filePath: pathIn('nope.txt'));

      expect(result, isA<Err>());
      expect(result.error, isA<FileNotFoundException>());
      expect((result.error as FileNotFoundException).filePath,
          pathIn('nope.txt'));
    });

    test('honours the latin1 encoding', () async {
      final file = pathIn('latin.txt');
      await File(file).writeAsBytes(latin1.encode('café'));

      final result = await ops.readFileContent(filePath: file, encoding: 'latin1');

      expect(result.value, 'café');
    });
  });

  group('readFileBytesContent', () {
    test('reads raw bytes', () async {
      final file = pathIn('bytes.bin');
      await File(file).writeAsBytes([1, 2, 3, 4]);

      final result = await ops.readFileBytesContent(filePath: file);

      expect(result.value, [1, 2, 3, 4]);
    });

    test('returns FileNotFoundException for a missing file', () async {
      final result =
          await ops.readFileBytesContent(filePath: pathIn('missing.bin'));

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('writeFileContent', () {
    test('writes content and creates parent directories', () async {
      final file = pathIn(p.join('nested', 'deep', 'out.txt'));

      final result = await ops.writeFileContent(filePath: file, content: 'data');

      expect(result, isA<Ok>());
      expect(await File(file).readAsString(), 'data');
    });

    test('fails when parent missing and createDirectories is false', () async {
      final file = pathIn(p.join('absent', 'out.txt'));

      final result = await ops.writeFileContent(
        filePath: file,
        content: 'data',
        createDirectories: false,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
    });
  });

  group('writeFileBytesContent', () {
    test('writes bytes and creates directories', () async {
      final file = pathIn(p.join('bin', 'out.bin'));

      final result =
          await ops.writeFileBytesContent(filePath: file, bytes: [9, 8, 7]);

      expect(result, isA<Ok>());
      expect(await File(file).readAsBytes(), [9, 8, 7]);
    });

    test('fails when parent missing and createDirectories is false', () async {
      final file = pathIn(p.join('absent', 'out.bin'));

      final result = await ops.writeFileBytesContent(
        filePath: file,
        bytes: [1],
        createDirectories: false,
      );

      expect(result.error, isA<FileAccessDeniedException>());
    });
  });

  group('deleteFileAtPath', () {
    test('deletes an existing file', () async {
      final file = pathIn('todelete.txt');
      await File(file).writeAsString('x');

      final result = await ops.deleteFileAtPath(filePath: file);

      expect(result.value, isTrue);
      expect(await File(file).exists(), isFalse);
    });

    test('returns FileNotFoundException for a missing file', () async {
      final result = await ops.deleteFileAtPath(filePath: pathIn('ghost.txt'));

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('copyFileToPath', () {
    test('copies a file to a new path', () async {
      final src = pathIn('src.txt');
      final dst = pathIn(p.join('out', 'dst.txt'));
      await File(src).writeAsString('payload');

      final result =
          await ops.copyFileToPath(sourcePath: src, destinationPath: dst);

      expect(result.value, dst);
      expect(await File(dst).readAsString(), 'payload');
      expect(await File(src).exists(), isTrue);
    });

    test('errors when source is missing', () async {
      final result = await ops.copyFileToPath(
        sourcePath: pathIn('nosrc.txt'),
        destinationPath: pathIn('out.txt'),
      );

      expect(result.error, isA<FileNotFoundException>());
    });

    test('refuses to overwrite by default', () async {
      final src = pathIn('a.txt');
      final dst = pathIn('b.txt');
      await File(src).writeAsString('one');
      await File(dst).writeAsString('two');

      final result =
          await ops.copyFileToPath(sourcePath: src, destinationPath: dst);

      expect(result.error, isA<FileWriteException>());
      expect(await File(dst).readAsString(), 'two');
    });

    test('overwrites when overwrite is true', () async {
      final src = pathIn('a.txt');
      final dst = pathIn('b.txt');
      await File(src).writeAsString('one');
      await File(dst).writeAsString('two');

      final result = await ops.copyFileToPath(
        sourcePath: src,
        destinationPath: dst,
        overwrite: true,
      );

      expect(result, isA<Ok>());
      expect(await File(dst).readAsString(), 'one');
    });
  });

  group('moveFileToPath', () {
    test('moves a file to a new path', () async {
      final src = pathIn('move_src.txt');
      final dst = pathIn(p.join('moved', 'move_dst.txt'));
      await File(src).writeAsString('payload');

      final result =
          await ops.moveFileToPath(sourcePath: src, destinationPath: dst);

      expect(result.value, dst);
      expect(await File(dst).readAsString(), 'payload');
      expect(await File(src).exists(), isFalse);
    });

    test('errors when source is missing', () async {
      final result = await ops.moveFileToPath(
        sourcePath: pathIn('nosrc.txt'),
        destinationPath: pathIn('out.txt'),
      );

      expect(result.error, isA<FileNotFoundException>());
    });

    test('refuses to overwrite by default', () async {
      final src = pathIn('m_a.txt');
      final dst = pathIn('m_b.txt');
      await File(src).writeAsString('one');
      await File(dst).writeAsString('two');

      final result =
          await ops.moveFileToPath(sourcePath: src, destinationPath: dst);

      expect(result.error, isA<FileWriteException>());
    });

    test('overwrites when overwrite is true', () async {
      final src = pathIn('m_a.txt');
      final dst = pathIn('m_b.txt');
      await File(src).writeAsString('one');
      await File(dst).writeAsString('two');

      final result = await ops.moveFileToPath(
        sourcePath: src,
        destinationPath: dst,
        overwrite: true,
      );

      expect(result, isA<Ok>());
      expect(await File(dst).readAsString(), 'one');
      expect(await File(src).exists(), isFalse);
    });
  });

  group('getFileInfoAtPath', () {
    test('returns metadata for an existing file', () async {
      final file = pathIn('info.pack');
      await File(file).writeAsString('hello');

      final result = await ops.getFileInfoAtPath(filePath: file);

      expect(result, isA<Ok>());
      final FileInfo info = result.value;
      expect(info.name, 'info.pack');
      expect(info.sizeBytes, 5);
      expect(info.extension, '.pack');
      expect(info.path, file);
    });

    test('extension is null when there is none', () async {
      final file = pathIn('noext');
      await File(file).writeAsString('x');

      final result = await ops.getFileInfoAtPath(filePath: file);

      expect(result.value.extension, isNull);
    });

    test('returns FileNotFoundException for a missing file', () async {
      final result = await ops.getFileInfoAtPath(filePath: pathIn('absent'));

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('calculateHashForFile', () {
    test('computes sha256 by default', () async {
      final file = pathIn('hash.txt');
      await File(file).writeAsString('abc');
      final expected = sha256.convert(utf8.encode('abc')).toString();

      final result = await ops.calculateHashForFile(filePath: file);

      expect(result.value, expected);
    });

    test('supports md5', () async {
      final file = pathIn('hash.txt');
      await File(file).writeAsString('abc');
      final expected = md5.convert(utf8.encode('abc')).toString();

      final result =
          await ops.calculateHashForFile(filePath: file, algorithm: 'md5');

      expect(result.value, expected);
    });

    test('rejects an unsupported algorithm', () async {
      final file = pathIn('hash.txt');
      await File(file).writeAsString('abc');

      final result =
          await ops.calculateHashForFile(filePath: file, algorithm: 'crc32');

      expect(result.error, isA<FileServiceException>());
      expect(result.error.message, contains('Unsupported hash algorithm'));
    });

    test('returns FileNotFoundException for a missing file', () async {
      final result =
          await ops.calculateHashForFile(filePath: pathIn('absent.txt'));

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('listFilesInDirectory', () {
    test('lists files non-recursively', () async {
      await File(pathIn('a.txt')).writeAsString('a');
      await File(pathIn('b.loc')).writeAsString('b');
      await Directory(pathIn('sub')).create();
      await File(pathIn(p.join('sub', 'c.txt'))).writeAsString('c');

      final result =
          await ops.listFilesInDirectory(directoryPath: tempDir.path);

      expect(result.value, hasLength(2));
    });

    test('lists files recursively', () async {
      await File(pathIn('a.txt')).writeAsString('a');
      await Directory(pathIn('sub')).create();
      await File(pathIn(p.join('sub', 'c.txt'))).writeAsString('c');

      final result = await ops.listFilesInDirectory(
        directoryPath: tempDir.path,
        recursive: true,
      );

      expect(result.value, hasLength(2));
    });

    test('filters by glob pattern', () async {
      await File(pathIn('keep.loc')).writeAsString('a');
      await File(pathIn('skip.txt')).writeAsString('b');

      final result = await ops.listFilesInDirectory(
        directoryPath: tempDir.path,
        pattern: '*.loc',
      );

      expect(result.value, hasLength(1));
      expect(result.value.single, endsWith('keep.loc'));
    });

    test('returns FileNotFoundException for a missing directory', () async {
      final result = await ops.listFilesInDirectory(
        directoryPath: pathIn('no-such-dir'),
      );

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('createDirectoryAtPath', () {
    test('creates a nested directory', () async {
      final dir = pathIn(p.join('x', 'y', 'z'));

      final result = await ops.createDirectoryAtPath(directoryPath: dir);

      expect(result.value, dir);
      expect(await Directory(dir).exists(), isTrue);
    });

    test('fails non-recursively when parent is missing', () async {
      final dir = pathIn(p.join('missing-parent', 'child'));

      final result = await ops.createDirectoryAtPath(
        directoryPath: dir,
        recursive: false,
      );

      expect(result.error, isA<FileAccessDeniedException>());
    });
  });

  group('deleteDirectoryAtPath', () {
    test('deletes an empty directory', () async {
      final dir = pathIn('empty');
      await Directory(dir).create();

      final result = await ops.deleteDirectoryAtPath(directoryPath: dir);

      expect(result.value, isTrue);
      expect(await Directory(dir).exists(), isFalse);
    });

    test('deletes a non-empty directory recursively', () async {
      final dir = pathIn('full');
      await Directory(dir).create();
      await File(p.join(dir, 'f.txt')).writeAsString('x');

      final result = await ops.deleteDirectoryAtPath(
        directoryPath: dir,
        recursive: true,
      );

      expect(result.value, isTrue);
    });

    test('returns FileNotFoundException for a missing directory', () async {
      final result =
          await ops.deleteDirectoryAtPath(directoryPath: pathIn('ghost-dir'));

      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('getEncoding', () {
    test('maps known encodings', () {
      expect(ops.getEncoding('utf-8'), utf8);
      expect(ops.getEncoding('UTF8'), utf8);
      expect(ops.getEncoding('latin1'), latin1);
      expect(ops.getEncoding('iso-8859-1'), latin1);
      expect(ops.getEncoding('ascii'), ascii);
    });

    test('utf-16 variants resolve to a codec', () {
      expect(ops.getEncoding('utf-16le'), isA<Encoding>());
      expect(ops.getEncoding('utf-16be'), isA<Encoding>());
      expect(ops.getEncoding('utf-16'), isA<Encoding>());
    });

    test('falls back to utf-8 for unknown names', () {
      expect(ops.getEncoding('shift-jis'), utf8);
    });
  });

  group('globToRegex', () {
    test('translates wildcards and escapes dots', () {
      final regex = ops.globToRegex('*.loc');
      expect(regex.hasMatch('data.loc'), isTrue);
      expect(regex.hasMatch('dataxloc'), isFalse);
    });

    test('single-char wildcard maps to dot', () {
      final regex = ops.globToRegex('a?c');
      expect(regex.hasMatch('abc'), isTrue);
      expect(regex.hasMatch('ac'), isFalse);
    });
  });
}
