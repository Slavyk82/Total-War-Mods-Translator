// Example usage of file hashing functionality
// This file demonstrates how to use the calculateFileHash method
// ignore_for_file: avoid_print

import 'package:twmt/services/file/file_service_impl.dart';

Future<void> main() async {
  final fileService = FileServiceImpl();

  // Example 1: Calculate SHA-256 hash (default)
  print('Example 1: SHA-256 hash');
  final result1 = await fileService.calculateFileHash(
    filePath: 'path/to/your/file.txt',
  );

  result1.when(
    ok: (hash) => print('SHA-256 hash: $hash'),
    err: (error) => print('Error: $error'),
  );

  // Example 2: Calculate MD5 hash
  print('\nExample 2: MD5 hash');
  final result2 = await fileService.calculateFileHash(
    filePath: 'path/to/your/file.txt',
    algorithm: 'md5',
  );

  result2.when(
    ok: (hash) => print('MD5 hash: $hash'),
    err: (error) => print('Error: $error'),
  );

  // Example 3: Detect file changes
  print('\nExample 3: Detect file changes');
  final filePath = 'path/to/monitored/file.txt';

  // Calculate initial hash
  final initialHashResult = await fileService.calculateFileHash(
    filePath: filePath,
  );

  if (initialHashResult.isOk) {
    final initialHash = initialHashResult.unwrap();
    print('Initial hash: $initialHash');

    // ... later, after potential file modification ...
    // await Future.delayed(Duration(seconds: 5));

    // Calculate new hash
    final newHashResult = await fileService.calculateFileHash(
      filePath: filePath,
    );

    if (newHashResult.isOk) {
      final newHash = newHashResult.unwrap();

      if (initialHash == newHash) {
        print('File has not changed');
      } else {
        print('File has changed!');
        print('New hash: $newHash');
      }
    }
  }

  // Example 4: Compare two files
  print('\nExample 4: Compare two files');
  final file1Result = await fileService.calculateFileHash(
    filePath: 'path/to/file1.txt',
  );
  final file2Result = await fileService.calculateFileHash(
    filePath: 'path/to/file2.txt',
  );

  if (file1Result.isOk && file2Result.isOk) {
    if (file1Result.unwrap() == file2Result.unwrap()) {
      print('Files are identical');
    } else {
      print('Files are different');
    }
  }

  // Example 5: Use different hash algorithms
  print('\nExample 5: All supported algorithms');
  final algorithms = ['sha256', 'sha1', 'sha224', 'sha384', 'sha512', 'md5'];
  final testFile = 'path/to/file.txt';

  for (final algorithm in algorithms) {
    final result = await fileService.calculateFileHash(
      filePath: testFile,
      algorithm: algorithm,
    );

    result.when(
      ok: (hash) => print('$algorithm: $hash'),
      err: (error) => print('$algorithm error: $error'),
    );
  }

  // Example 6: Error handling
  print('\nExample 6: Error handling');
  final nonExistentResult = await fileService.calculateFileHash(
    filePath: 'non_existent_file.txt',
  );

  nonExistentResult.when(
    ok: (hash) => print('Hash: $hash'),
    err: (error) {
      print('Caught error: ${error.message}');
      // Handle specific error types
      if (error.toString().contains('File not found')) {
        print('The file does not exist');
      }
    },
  );
}
