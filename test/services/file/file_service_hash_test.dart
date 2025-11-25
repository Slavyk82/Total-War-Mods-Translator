import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/file_service_impl.dart';

void main() {
  group('FileServiceImpl - Hash Calculation', () {
    late FileServiceImpl fileService;
    late Directory tempDir;

    setUp(() async {
      fileService = FileServiceImpl();
      tempDir = await Directory.systemTemp.createTemp('file_service_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('calculateFileHash - SHA-256 returns valid hex hash', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      const testContent = 'Hello, World!';
      await testFile.writeAsString(testContent);

      // Expected SHA-256 hash of "Hello, World!"
      const expectedHash =
          'dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
        algorithm: 'sha256',
      );

      // Assert
      expect(result.isOk, isTrue);
      final hash = result.unwrap();
      expect(hash, equals(expectedHash));
    });

    test('calculateFileHash - default algorithm is SHA-256', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      const testContent = 'Hello, World!';
      await testFile.writeAsString(testContent);

      const expectedHash =
          'dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
      );

      // Assert
      expect(result.isOk, isTrue);
      final hash = result.unwrap();
      expect(hash, equals(expectedHash));
    });

    test('calculateFileHash - SHA-1 returns valid hex hash', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      const testContent = 'Hello, World!';
      await testFile.writeAsString(testContent);

      // Expected SHA-1 hash of "Hello, World!"
      const expectedHash = '0a0a9f2a6772942557ab5355d76af442f8f65e01';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
        algorithm: 'sha1',
      );

      // Assert
      expect(result.isOk, isTrue);
      final hash = result.unwrap();
      expect(hash, equals(expectedHash));
    });

    test('calculateFileHash - MD5 returns valid hex hash', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      const testContent = 'Hello, World!';
      await testFile.writeAsString(testContent);

      // Expected MD5 hash of "Hello, World!"
      const expectedHash = '65a8e27d8879283831b664bd8b7f0ad4';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
        algorithm: 'md5',
      );

      // Assert
      expect(result.isOk, isTrue);
      final hash = result.unwrap();
      expect(hash, equals(expectedHash));
    });

    test('calculateFileHash - same file produces same hash', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      await testFile.writeAsString('Test content');

      // Act
      final result1 = await fileService.calculateFileHash(
        filePath: testFile.path,
      );
      final result2 = await fileService.calculateFileHash(
        filePath: testFile.path,
      );

      // Assert
      expect(result1.isOk, isTrue);
      expect(result2.isOk, isTrue);
      expect(result1.unwrap(), equals(result2.unwrap()));
    });

    test('calculateFileHash - different content produces different hash',
        () async {
      // Arrange
      final testFile1 = File('${tempDir.path}/test1.txt');
      final testFile2 = File('${tempDir.path}/test2.txt');
      await testFile1.writeAsString('Content A');
      await testFile2.writeAsString('Content B');

      // Act
      final result1 = await fileService.calculateFileHash(
        filePath: testFile1.path,
      );
      final result2 = await fileService.calculateFileHash(
        filePath: testFile2.path,
      );

      // Assert
      expect(result1.isOk, isTrue);
      expect(result2.isOk, isTrue);
      expect(result1.unwrap(), isNot(equals(result2.unwrap())));
    });

    test('calculateFileHash - returns error for non-existent file', () async {
      // Arrange
      final nonExistentPath = '${tempDir.path}/non_existent.txt';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: nonExistentPath,
      );

      // Assert
      expect(result.isErr, isTrue);
      final error = result.unwrapErr();
      expect(error.toString(), contains('File not found'));
    });

    test('calculateFileHash - returns error for unsupported algorithm',
        () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      await testFile.writeAsString('Test');

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
        algorithm: 'invalid_algorithm',
      );

      // Assert
      expect(result.isErr, isTrue);
      final error = result.unwrapErr();
      expect(error.toString(), contains('Unsupported hash algorithm'));
    });

    test('calculateFileHash - handles empty file', () async {
      // Arrange
      final testFile = File('${tempDir.path}/empty.txt');
      await testFile.writeAsString('');

      // Expected SHA-256 hash of empty string
      const expectedHash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
      );

      // Assert
      expect(result.isOk, isTrue);
      expect(result.unwrap(), equals(expectedHash));
    });

    test('calculateFileHash - handles large file', () async {
      // Arrange
      final testFile = File('${tempDir.path}/large.txt');
      final largeContent = 'A' * 1024 * 1024; // 1 MB of 'A's
      await testFile.writeAsString(largeContent);

      // Act
      final result = await fileService.calculateFileHash(
        filePath: testFile.path,
      );

      // Assert
      expect(result.isOk, isTrue);
      expect(result.unwrap().length, equals(64)); // SHA-256 produces 64 hex chars
    });

    test('calculateFileHash - supports all hash algorithms', () async {
      // Arrange
      final testFile = File('${tempDir.path}/test.txt');
      await testFile.writeAsString('Test');

      final algorithms = ['sha256', 'sha1', 'sha224', 'sha384', 'sha512', 'md5'];

      for (final algorithm in algorithms) {
        // Act
        final result = await fileService.calculateFileHash(
          filePath: testFile.path,
          algorithm: algorithm,
        );

        // Assert
        expect(result.isOk, isTrue,
            reason: 'Algorithm $algorithm should be supported');
      }
    });
  });
}
