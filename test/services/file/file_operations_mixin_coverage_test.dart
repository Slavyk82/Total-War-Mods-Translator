import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/mixins/file_operations_mixin.dart';

/// Concrete host so the mixin can be exercised directly.
///
/// Companion to `file_operations_mixin_test.dart` — this file targets the
/// error branches (`on FileSystemException` / generic catch) that the happy
/// path tests do not reach. Failures are provoked against real files using
/// Windows read-only attributes and path collisions, so every case runs
/// against `Directory.systemTemp` with deterministic cleanup.
class _Ops with FileOperationsMixin {}

void main() {
  late Directory tempDir;
  late _Ops ops;

  setUp(() async {
    ops = _Ops();
    tempDir = await Directory.systemTemp.createTemp('file_ops_mixin_cov_');
  });

  tearDown(() async {
    // Clear any lingering read-only attributes / denied ACLs so the recursive
    // delete works.
    try {
      Process.runSync('attrib', ['-R', p.join(tempDir.path, '*'), '/S', '/D']);
      Process.runSync('icacls', [tempDir.path, '/reset', '/T', '/C', '/Q']);
    } catch (_) {
      // best effort
    }
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // best effort: leftover read-only handles must not fail the suite
      }
    }
  });

  String pathIn(String name) => p.join(tempDir.path, name);

  /// Create a file then flag it read-only via the Windows `attrib` tool.
  Future<String> makeReadOnly(String name, [String content = 'x']) async {
    final path = pathIn(name);
    await File(path).writeAsString(content);
    Process.runSync('attrib', ['+R', path]);
    return path;
  }

  void clearReadOnly(String path) {
    Process.runSync('attrib', ['-R', path]);
  }

  /// Deny "Read Data" on [path] for Everyone. The entry is still stat-able
  /// (so `exists()` succeeds) but opening it for reading throws, which is the
  /// only reliable way to reach the read-side `FileSystemException` branches.
  /// Returns false when the ACL change did not take effect (skip the case).
  bool denyReadData(String path) {
    final r = Process.runSync('icacls', [path, '/deny', '*S-1-1-0:(RD)']);
    return r.exitCode == 0;
  }

  void resetAcl(String path) {
    Process.runSync('icacls', [path, '/reset', '/T', '/C', '/Q']);
  }

  group('writeFileContent error branches', () {
    test('maps a FileSystemException to FileAccessDeniedException', () async {
      final path = await makeReadOnly('ro_write.txt');

      final result =
          await ops.writeFileContent(filePath: path, content: 'new');

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      final err = result.error as FileAccessDeniedException;
      expect(err.accessType, 'write');
      expect(err.filePath, path);

      clearReadOnly(path);
    });
  });

  group('writeFileBytesContent error branches', () {
    test('maps a FileSystemException to FileAccessDeniedException', () async {
      final path = await makeReadOnly('ro_write.bin');

      final result =
          await ops.writeFileBytesContent(filePath: path, bytes: [1, 2, 3]);

      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'write');

      clearReadOnly(path);
    });
  });

  group('deleteFileAtPath error branches', () {
    test('maps a FileSystemException to FileAccessDeniedException', () async {
      final path = await makeReadOnly('ro_delete.txt');

      final result = await ops.deleteFileAtPath(filePath: path);

      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'delete');

      clearReadOnly(path);
    });
  });

  group('copyFileToPath error branches', () {
    test('maps a FileSystemException to FileServiceException', () async {
      final src = pathIn('copy_src.txt');
      await File(src).writeAsString('payload');
      final dst = await makeReadOnly('copy_dst.txt', 'old');

      // overwrite passes the guard; the actual copy onto the read-only
      // destination throws and is mapped to a generic FileServiceException.
      final result = await ops.copyFileToPath(
        sourcePath: src,
        destinationPath: dst,
        overwrite: true,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<FileServiceException>());
      expect(result.error.message, contains('Cannot copy file'));

      clearReadOnly(dst);
    });
  });

  group('moveFileToPath error branches', () {
    test('maps a FileSystemException to FileServiceException', () async {
      final src = pathIn('move_src.txt');
      await File(src).writeAsString('payload');
      final dst = await makeReadOnly('move_dst.txt', 'old');

      final result = await ops.moveFileToPath(
        sourcePath: src,
        destinationPath: dst,
        overwrite: true,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<FileServiceException>());
      expect(result.error.message, contains('Cannot move file'));

      clearReadOnly(dst);
    });

    test(
        'fails to create a destination directory under a file parent',
        () async {
      final src = pathIn('move_src2.txt');
      await File(src).writeAsString('payload');
      // Parent component is a regular file, so creating the destination
      // directory throws a FileSystemException.
      final parentFile = pathIn('parent_is_file');
      await File(parentFile).writeAsString('p');
      final dst = p.join(parentFile, 'child.txt');

      final result = await ops.moveFileToPath(
        sourcePath: src,
        destinationPath: dst,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<FileServiceException>());
    });
  });

  group('createDirectoryAtPath error branches', () {
    test('maps a FileSystemException when the path is an existing file',
        () async {
      final file = pathIn('already_a_file');
      await File(file).writeAsString('x');

      final result = await ops.createDirectoryAtPath(directoryPath: file);

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'write');
    });
  });

  group('deleteDirectoryAtPath error branches', () {
    test('non-recursive delete of a non-empty directory fails', () async {
      final dir = pathIn('non_empty');
      await Directory(dir).create();
      await File(p.join(dir, 'inside.txt')).writeAsString('x');

      final result = await ops.deleteDirectoryAtPath(
        directoryPath: dir,
        recursive: false,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'delete');
    });
  });

  group('copyFileToPath / moveFileToPath create-destination directory', () {
    test('copy creates a missing destination directory tree', () async {
      final src = pathIn('c_src.txt');
      await File(src).writeAsString('data');
      final dst = pathIn(p.join('made', 'deep', 'c_dst.txt'));

      final result = await ops.copyFileToPath(
        sourcePath: src,
        destinationPath: dst,
      );

      expect(result, isA<Ok>());
      expect(await File(dst).readAsString(), 'data');
    });

    test('move creates a missing destination directory tree', () async {
      final src = pathIn('m_src.txt');
      await File(src).writeAsString('data');
      final dst = pathIn(p.join('moved', 'deep', 'm_dst.txt'));

      final result = await ops.moveFileToPath(
        sourcePath: src,
        destinationPath: dst,
      );

      expect(result, isA<Ok>());
      expect(await File(dst).readAsString(), 'data');
      expect(await File(src).exists(), isFalse);
    });
  });

  group('read-side FileSystemException branches', () {
    test('readFileContent maps a denied read to FileAccessDeniedException',
        () async {
      final path = pathIn('denied_read.txt');
      await File(path).writeAsString('secret');
      if (!denyReadData(path)) {
        return; // ACL change unavailable in this environment.
      }

      final result = await ops.readFileContent(filePath: path);

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'read');

      resetAcl(path);
    });

    test('readFileBytesContent maps a denied read to FileAccessDeniedException',
        () async {
      final path = pathIn('denied_read.bin');
      await File(path).writeAsString('secret');
      if (!denyReadData(path)) {
        return;
      }

      final result = await ops.readFileBytesContent(filePath: path);

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'read');

      resetAcl(path);
    });

    test('calculateHashForFile maps a denied read to FileAccessDeniedException',
        () async {
      final path = pathIn('denied_hash.txt');
      await File(path).writeAsString('secret');
      if (!denyReadData(path)) {
        return;
      }

      final result = await ops.calculateHashForFile(filePath: path);

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'read');

      resetAcl(path);
    });

    test('listFilesInDirectory maps a denied listing to FileAccessDenied',
        () async {
      final dir = pathIn('denied_dir');
      await Directory(dir).create();
      await File(p.join(dir, 'a.txt')).writeAsString('a');
      if (!denyReadData(dir)) {
        return;
      }

      final result = await ops.listFilesInDirectory(directoryPath: dir);

      expect(result, isA<Err>());
      expect(result.error, isA<FileAccessDeniedException>());
      expect((result.error as FileAccessDeniedException).accessType, 'read');

      resetAcl(dir);
    });
  });

  group('calculateHashForFile additional algorithms', () {
    test('supports sha1, sha224, sha384 and sha512', () async {
      final file = pathIn('multi_hash.txt');
      await File(file).writeAsString('abc');

      for (final algo in ['sha1', 'sha224', 'sha384', 'sha512']) {
        final result =
            await ops.calculateHashForFile(filePath: file, algorithm: algo);
        expect(result, isA<Ok>(), reason: 'algorithm $algo should succeed');
        expect(result.value, isNotEmpty);
      }
    });
  });
}
