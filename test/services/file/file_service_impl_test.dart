import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

import '../../helpers/test_bootstrap.dart';

void main() {
  late Directory tempDir;
  late FileServiceImpl service;

  setUp(() async {
    // FileServiceImpl builds sub-services that resolve a logger from ServiceLocator.
    await TestBootstrap.registerFakes();
    service = FileServiceImpl();
    tempDir = await Directory.systemTemp.createTemp('file_service_impl_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String pathIn(String name) => p.join(tempDir.path, name);

  test('factory returns the shared singleton', () {
    expect(identical(FileServiceImpl(), service), isTrue);
  });

  group('read/write text', () {
    test('round-trips string content', () async {
      final file = pathIn('rt.txt');

      final write =
          await service.writeFile(filePath: file, content: 'round-trip');
      expect(write, isA<Ok>());

      final read = await service.readFile(filePath: file);
      expect(read.value, 'round-trip');
    });

    test('readFile reports a missing file', () async {
      final read = await service.readFile(filePath: pathIn('absent.txt'));
      expect(read.error, isA<FileNotFoundException>());
    });
  });

  group('read/write bytes', () {
    test('round-trips byte content', () async {
      final file = pathIn('rt.bin');

      await service.writeFileBytes(filePath: file, bytes: [10, 20, 30]);
      final read = await service.readFileBytes(filePath: file);

      expect(read.value, [10, 20, 30]);
    });
  });

  group('fileExists', () {
    test('is true for an existing file and false otherwise', () async {
      final file = pathIn('present.txt');
      await File(file).writeAsString('x');

      expect(await service.fileExists(file), isTrue);
      expect(await service.fileExists(pathIn('nope.txt')), isFalse);
    });
  });

  group('deleteFile', () {
    test('removes an existing file', () async {
      final file = pathIn('del.txt');
      await File(file).writeAsString('x');

      final result = await service.deleteFile(filePath: file);

      expect(result.value, isTrue);
      expect(await File(file).exists(), isFalse);
    });

    test('reports a missing file', () async {
      final result = await service.deleteFile(filePath: pathIn('ghost.txt'));
      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('copyFile / moveFile', () {
    test('copies content to a new path', () async {
      final src = pathIn('c_src.txt');
      final dst = pathIn(p.join('sub', 'c_dst.txt'));
      await File(src).writeAsString('copy-me');

      final result =
          await service.copyFile(sourcePath: src, destinationPath: dst);

      expect(result.value, dst);
      expect(await File(dst).readAsString(), 'copy-me');
    });

    test('moves content and removes the source', () async {
      final src = pathIn('m_src.txt');
      final dst = pathIn('m_dst.txt');
      await File(src).writeAsString('move-me');

      final result =
          await service.moveFile(sourcePath: src, destinationPath: dst);

      expect(result.value, dst);
      expect(await File(src).exists(), isFalse);
    });
  });

  group('getFileInfo / calculateFileHash', () {
    test('returns metadata for a file', () async {
      final file = pathIn('meta.loc');
      await File(file).writeAsString('1234');

      final result = await service.getFileInfo(filePath: file);

      final FileInfo info = result.value;
      expect(info.sizeBytes, 4);
      expect(info.extension, '.loc');
    });

    test('hashes file content', () async {
      final file = pathIn('hash.txt');
      await File(file).writeAsString('abc');

      final result = await service.calculateFileHash(filePath: file);

      expect(result, isA<Ok>());
      expect(result.value, hasLength(64)); // sha256 hex digest
    });
  });

  group('directory operations', () {
    test('creates and deletes a directory', () async {
      final dir = pathIn(p.join('made', 'here'));

      final create = await service.createDirectory(directoryPath: dir);
      expect(create.value, dir);
      expect(await Directory(dir).exists(), isTrue);

      final delete = await service.deleteDirectory(directoryPath: dir);
      expect(delete.value, isTrue);
    });

    test('lists files with a pattern filter', () async {
      await File(pathIn('a.loc')).writeAsString('a');
      await File(pathIn('b.txt')).writeAsString('b');

      final result = await service.listFiles(
        directoryPath: tempDir.path,
        pattern: '*.loc',
      );

      expect(result.value, hasLength(1));
      expect(result.value.single, endsWith('a.loc'));
    });

    test('listFiles reports a missing directory', () async {
      final result =
          await service.listFiles(directoryPath: pathIn('no-dir'));
      expect(result.error, isA<FileNotFoundException>());
    });
  });
}
