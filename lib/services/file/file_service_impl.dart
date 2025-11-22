import 'dart:async';
import 'dart:convert' show Encoding, utf8, latin1, ascii, Converter;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/file_watch_service.dart';

/// Implementation of file system operations service
///
/// Provides comprehensive file I/O with Windows-specific paths and features.
///
/// This service delegates import/export and file watching operations to
/// specialized services to maintain clean separation of concerns.
class FileServiceImpl implements IFileService {
  /// Singleton instance
  static final FileServiceImpl _instance = FileServiceImpl._internal();

  factory FileServiceImpl() => _instance;

  FileServiceImpl._internal();

  /// Service for import/export operations
  final FileImportExportService _importExportService =
      FileImportExportService();

  /// Service for file watching operations
  final FileWatchService _watchService = FileWatchService();

  @override
  Future<Result<String, FileServiceException>> readFile({
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
        encoding: _getEncoding(encoding),
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

  @override
  Future<Result<List<int>, FileServiceException>> readFileBytes({
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

  @override
  Future<Result<String, FileServiceException>> writeFile({
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
        encoding: _getEncoding(encoding),
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

  @override
  Future<Result<String, FileServiceException>> writeFileBytes({
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

  @override
  Future<Result<bool, FileServiceException>> deleteFile({
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

  @override
  Future<Result<String, FileServiceException>> copyFile({
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

  @override
  Future<Result<String, FileServiceException>> moveFile({
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

  @override
  Future<bool> fileExists(String filePath) async {
    try {
      return await File(filePath).exists();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Result<FileInfo, FileServiceException>> getFileInfo({
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

  @override
  Future<Result<List<String>, FileServiceException>> listFiles({
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
        final regex = _globToRegex(pattern);
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

  @override
  Future<Result<String, FileServiceException>> createDirectory({
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

  @override
  Future<Result<bool, FileServiceException>> deleteDirectory({
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

  @override
  Future<String> getAppDataDirectory() async =>
      await _watchService.getAppDataDirectory();

  @override
  Future<String> getConfigDirectory() async =>
      await _watchService.getConfigDirectory();

  @override
  Future<String> getDatabaseDirectory() async =>
      await _watchService.getDatabaseDirectory();

  @override
  Future<String> getLogsDirectory() async =>
      await _watchService.getLogsDirectory();

  @override
  Future<String> getCacheDirectory() async =>
      await _watchService.getCacheDirectory();

  @override
  Future<String> getTempDirectory() async =>
      await _watchService.getTempDirectory();

  @override
  Future<Result<String, FileServiceException>> createTempFile({
    String? prefix,
    String? suffix,
  }) =>
      _watchService.createTempFile(prefix: prefix, suffix: suffix);

  @override
  Future<Result<int, FileServiceException>> cleanupTempFiles({
    Duration olderThan = const Duration(days: 7),
  }) =>
      _watchService.cleanupTempFiles(olderThan: olderThan);

  @override
  Stream<FileChangeEvent> watchFile({required String path}) =>
      _watchService.watchFile(path: path);

  @override
  Future<void> stopWatching({required String path}) =>
      _watchService.stopWatching(path: path);

  @override
  Future<Result<List<Map<String, String>>, ImportException>> importFromCsv({
    required String filePath,
    bool hasHeader = true,
  }) =>
      _importExportService.importFromCsv(
        filePath: filePath,
        hasHeader: hasHeader,
      );

  @override
  Future<Result<String, ExportException>> exportToCsv({
    required List<Map<String, String>> data,
    required String filePath,
    List<String>? headers,
  }) =>
      _importExportService.exportToCsv(
        data: data,
        filePath: filePath,
        headers: headers,
      );

  @override
  Future<Result<dynamic, ImportException>> importFromJson({
    required String filePath,
  }) =>
      _importExportService.importFromJson(filePath: filePath);

  @override
  Future<Result<String, ExportException>> exportToJson({
    required dynamic data,
    required String filePath,
    bool prettyPrint = true,
  }) =>
      _importExportService.exportToJson(
        data: data,
        filePath: filePath,
        prettyPrint: prettyPrint,
      );

  @override
  Future<Result<List<Map<String, String>>, ImportException>> importFromExcel({
    required String filePath,
    String? sheetName,
    bool hasHeader = true,
  }) =>
      _importExportService.importFromExcel(
        filePath: filePath,
        sheetName: sheetName,
        hasHeader: hasHeader,
      );

  @override
  Future<Result<String, ExportException>> exportToExcel({
    required List<Map<String, String>> data,
    required String filePath,
    String sheetName = 'Sheet1',
    List<String>? headers,
  }) =>
      _importExportService.exportToExcel(
        data: data,
        filePath: filePath,
        sheetName: sheetName,
        headers: headers,
      );

  @override
  Future<Result<String, FileServiceException>> calculateFileHash({
    required String filePath,
    String algorithm = 'sha256',
  }) async {
    try {
      final file = File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      // Read file as bytes
      final bytes = await file.readAsBytes();

      // Calculate hash based on algorithm
      final digest = switch (algorithm.toLowerCase()) {
        'sha256' => sha256.convert(bytes),
        'sha1' => sha1.convert(bytes),
        'sha224' => sha224.convert(bytes),
        'sha384' => sha384.convert(bytes),
        'sha512' => sha512.convert(bytes),
        'md5' => md5.convert(bytes),
        _ => throw ArgumentError('Unsupported hash algorithm: $algorithm'),
      };

      // Return hex string representation
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

  @override
  Future<Result<bool, FileServiceException>> compareFiles({
    required String filePath1,
    required String filePath2,
    bool compareContent = true,
  }) =>
      _watchService.compareFiles(
        filePath1: filePath1,
        filePath2: filePath2,
        compareContent: compareContent,
      );

  /// Convert encoding string to Dart Encoding
  Encoding _getEncoding(String encodingName) {
    return switch (encodingName.toLowerCase()) {
      'utf-8' || 'utf8' => utf8,
      'utf-16le' => _Utf16LeCodec(),
      'utf-16be' => _Utf16BeCodec(),
      'utf-16' || 'utf16' => _Utf16LeCodec(), // Default to LE
      'latin1' || 'iso-8859-1' => latin1,
      'ascii' => ascii,
      _ => utf8,
    };
  }

  /// Convert glob pattern to regex
  RegExp _globToRegex(String glob) {
    var pattern = glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp(pattern);
  }
}

/// UTF-16 Little Endian codec
class _Utf16LeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => const _Utf16LeDecoder();

  @override
  Converter<String, List<int>> get encoder => const _Utf16LeEncoder();

  @override
  String get name => 'utf-16le';
}

/// UTF-16 Big Endian codec
class _Utf16BeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => const _Utf16BeDecoder();

  @override
  Converter<String, List<int>> get encoder => const _Utf16BeEncoder();

  @override
  String get name => 'utf-16be';
}

/// UTF-16 LE Decoder
class _Utf16LeDecoder extends Converter<List<int>, String> {
  const _Utf16LeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
}

/// UTF-16 BE Decoder
class _Utf16BeDecoder extends Converter<List<int>, String> {
  const _Utf16BeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}

/// UTF-16 LE Encoder
class _Utf16LeEncoder extends Converter<String, List<int>> {
  const _Utf16LeEncoder();

  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (final unit in input.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }
}

/// UTF-16 BE Encoder
class _Utf16BeEncoder extends Converter<String, List<int>> {
  const _Utf16BeEncoder();

  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (final unit in input.codeUnits) {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
    return bytes;
  }
}
