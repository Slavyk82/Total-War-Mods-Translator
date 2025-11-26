import 'dart:convert' show Encoding, utf8, latin1, ascii;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/utils/utf16_codec.dart';

/// Mixin providing core file system operations
///
/// Contains the fundamental file I/O operations used by FileServiceImpl.
/// Extracted to keep the main service file under the 600 line limit
/// while maintaining single responsibility.
mixin FileOperationsMixin {
  // ===========================================================================
  // FILE READ OPERATIONS
  // ===========================================================================

  /// Read file content as string
  Future<Result<String, FileServiceException>> readFileContent({
    required String filePath,
    String encoding = 'utf-8',
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      final content = await file.readAsString(
        encoding: getEncoding(encoding),
      );

      return Ok(content);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot read file: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error reading file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Read file content as bytes
  Future<Result<List<int>, FileServiceException>> readFileBytesContent({
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      final bytes = await file.readAsBytes();
      return Ok(bytes);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot read file: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error reading file bytes: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ===========================================================================
  // FILE WRITE OPERATIONS
  // ===========================================================================

  /// Write string content to file
  Future<Result<String, FileServiceException>> writeFileContent({
    required String filePath,
    required String content,
    String encoding = 'utf-8',
    bool createDirectories = true,
  }) async {
    try {
      final file = File(filePath);

      if (createDirectories) {
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      await file.writeAsString(
        content,
        encoding: getEncoding(encoding),
      );

      return Ok(filePath);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot write file: ${e.message}',
          filePath,
          'write',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error writing file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Write bytes to file
  Future<Result<String, FileServiceException>> writeFileBytesContent({
    required String filePath,
    required List<int> bytes,
    bool createDirectories = true,
  }) async {
    try {
      final file = File(filePath);

      if (createDirectories) {
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      await file.writeAsBytes(bytes);
      return Ok(filePath);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot write file: ${e.message}',
          filePath,
          'write',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error writing file bytes: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ===========================================================================
  // FILE MANIPULATION OPERATIONS
  // ===========================================================================

  /// Delete file
  Future<Result<bool, FileServiceException>> deleteFileAtPath({
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      await file.delete();
      return Ok(true);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot delete file: ${e.message}',
          filePath,
          'delete',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error deleting file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Copy file from source to destination
  Future<Result<String, FileServiceException>> copyFileToPath({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  }) async {
    try {
      final source = File(sourcePath);
      final destination = File(destinationPath);

      if (!await source.exists()) {
        return Err(
          FileNotFoundException(
            'Source file not found: $sourcePath',
            sourcePath,
          ),
        );
      }

      if (await destination.exists() && !overwrite) {
        return Err(
          FileWriteException(
            'Destination file already exists: $destinationPath',
            destinationPath,
          ),
        );
      }

      // Create parent directories if needed
      final destDir = destination.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      await source.copy(destinationPath);
      return Ok(destinationPath);
    } on FileSystemException catch (e) {
      return Err(
        FileServiceException(
          'Cannot copy file: ${e.message}',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error copying file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Move file from source to destination
  Future<Result<String, FileServiceException>> moveFileToPath({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  }) async {
    try {
      final source = File(sourcePath);
      final destination = File(destinationPath);

      if (!await source.exists()) {
        return Err(
          FileNotFoundException(
            'Source file not found: $sourcePath',
            sourcePath,
          ),
        );
      }

      if (await destination.exists() && !overwrite) {
        return Err(
          FileWriteException(
            'Destination file already exists: $destinationPath',
            destinationPath,
          ),
        );
      }

      // Create parent directories if needed
      final destDir = destination.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      await source.rename(destinationPath);
      return Ok(destinationPath);
    } on FileSystemException catch (e) {
      return Err(
        FileServiceException(
          'Cannot move file: ${e.message}',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error moving file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ===========================================================================
  // FILE INFO OPERATIONS
  // ===========================================================================

  /// Get file metadata information
  Future<Result<FileInfo, FileServiceException>> getFileInfoAtPath({
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      final stat = await file.stat();
      final fileName = path.basename(filePath);
      final extension = path.extension(filePath);

      final fileInfo = FileInfo(
        path: filePath,
        name: fileName,
        sizeBytes: stat.size,
        createdAt: stat.changed, // Windows: creation time
        modifiedAt: stat.modified,
        accessedAt: stat.accessed,
        isReadOnly: stat.mode & 0x80 == 0,
        extension: extension.isNotEmpty ? extension : null,
      );

      return Ok(fileInfo);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot access file info: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error getting file info: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Calculate file hash using specified algorithm
  Future<Result<String, FileServiceException>> calculateHashForFile({
    required String filePath,
    String algorithm = 'sha256',
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      final bytes = await file.readAsBytes();

      final digest = switch (algorithm.toLowerCase()) {
        'sha256' => sha256.convert(bytes),
        'sha1' => sha1.convert(bytes),
        'sha224' => sha224.convert(bytes),
        'sha384' => sha384.convert(bytes),
        'sha512' => sha512.convert(bytes),
        'md5' => md5.convert(bytes),
        _ => throw ArgumentError('Unsupported hash algorithm: $algorithm'),
      };

      return Ok(digest.toString());
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot read file for hashing: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } on ArgumentError catch (e) {
      return Err(
        FileServiceException(
          e.message,
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error calculating file hash: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ===========================================================================
  // DIRECTORY OPERATIONS
  // ===========================================================================

  /// List files in directory
  Future<Result<List<String>, FileServiceException>> listFilesInDirectory({
    required String directoryPath,
    String? pattern,
    bool recursive = false,
  }) async {
    try {
      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return Err(
          FileNotFoundException(
            'Directory not found: $directoryPath',
            directoryPath,
          ),
        );
      }

      final entities = await directory
          .list(recursive: recursive)
          .where((entity) => entity is File)
          .toList();

      var files = entities.map((e) => e.path).toList();

      // Apply pattern filter if provided
      if (pattern != null) {
        final regex = globToRegex(pattern);
        files = files.where((f) => regex.hasMatch(f)).toList();
      }

      return Ok(files);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot list directory: ${e.message}',
          directoryPath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error listing files: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Create directory
  Future<Result<String, FileServiceException>> createDirectoryAtPath({
    required String directoryPath,
    bool recursive = true,
  }) async {
    try {
      final directory = Directory(directoryPath);
      await directory.create(recursive: recursive);
      return Ok(directoryPath);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot create directory: ${e.message}',
          directoryPath,
          'write',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error creating directory: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Delete directory
  Future<Result<bool, FileServiceException>> deleteDirectoryAtPath({
    required String directoryPath,
    bool recursive = false,
  }) async {
    try {
      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return Err(
          FileNotFoundException(
            'Directory not found: $directoryPath',
            directoryPath,
          ),
        );
      }

      await directory.delete(recursive: recursive);
      return Ok(true);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot delete directory: ${e.message}',
          directoryPath,
          'delete',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error deleting directory: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ===========================================================================
  // UTILITY METHODS
  // ===========================================================================

  /// Convert encoding string to Dart Encoding
  Encoding getEncoding(String encodingName) {
    return switch (encodingName.toLowerCase()) {
      'utf-8' || 'utf8' => utf8,
      'utf-16le' => Utf16LeCodec(),
      'utf-16be' => Utf16BeCodec(),
      'utf-16' || 'utf16' => Utf16LeCodec(), // Default to LE
      'latin1' || 'iso-8859-1' => latin1,
      'ascii' => ascii,
      _ => utf8,
    };
  }

  /// Convert glob pattern to regex
  RegExp globToRegex(String glob) {
    var pattern = glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp(pattern);
  }
}
