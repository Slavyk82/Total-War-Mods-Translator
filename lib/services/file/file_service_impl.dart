import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/file_watch_service.dart';
import 'package:twmt/services/file/mixins/file_operations_mixin.dart';

/// Implementation of file system operations service
///
/// Provides comprehensive file I/O with Windows-specific paths and features.
///
/// This service uses:
/// - [FileOperationsMixin] for core file operations (read, write, delete, etc.)
/// - [FileImportExportService] for import/export operations (CSV, JSON, Excel)
/// - [FileWatchService] for file watching and temp file management
///
/// This composition approach maintains clean separation of concerns while
/// keeping each file under the project's line limit guidelines.
class FileServiceImpl with FileOperationsMixin implements IFileService {
  /// Singleton instance
  static final FileServiceImpl _instance = FileServiceImpl._internal();

  factory FileServiceImpl() => _instance;

  FileServiceImpl._internal();

  /// Service for import/export operations
  final FileImportExportService _importExportService =
      FileImportExportService();

  /// Service for file watching operations
  final FileWatchService _watchService = FileWatchService();

  // ===========================================================================
  // FILE READ OPERATIONS (delegated to mixin)
  // ===========================================================================

  @override
  Future<Result<String, FileServiceException>> readFile({
    required String filePath,
    String encoding = 'utf-8',
  }) =>
      readFileContent(filePath: filePath, encoding: encoding);

  @override
  Future<Result<List<int>, FileServiceException>> readFileBytes({
    required String filePath,
  }) =>
      readFileBytesContent(filePath: filePath);

  // ===========================================================================
  // FILE WRITE OPERATIONS (delegated to mixin)
  // ===========================================================================

  @override
  Future<Result<String, FileServiceException>> writeFile({
    required String filePath,
    required String content,
    String encoding = 'utf-8',
    bool createDirectories = true,
  }) =>
      writeFileContent(
        filePath: filePath,
        content: content,
        encoding: encoding,
        createDirectories: createDirectories,
      );

  @override
  Future<Result<String, FileServiceException>> writeFileBytes({
    required String filePath,
    required List<int> bytes,
    bool createDirectories = true,
  }) =>
      writeFileBytesContent(
        filePath: filePath,
        bytes: bytes,
        createDirectories: createDirectories,
      );

  // ===========================================================================
  // FILE MANIPULATION (delegated to mixin)
  // ===========================================================================

  @override
  Future<Result<bool, FileServiceException>> deleteFile({
    required String filePath,
  }) =>
      deleteFileAtPath(filePath: filePath);

  @override
  Future<Result<String, FileServiceException>> copyFile({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  }) =>
      copyFileToPath(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        overwrite: overwrite,
      );

  @override
  Future<Result<String, FileServiceException>> moveFile({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  }) =>
      moveFileToPath(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        overwrite: overwrite,
      );

  @override
  Future<bool> fileExists(String filePath) async {
    try {
      return await File(filePath).exists();
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // FILE INFO OPERATIONS (delegated to mixin)
  // ===========================================================================

  @override
  Future<Result<FileInfo, FileServiceException>> getFileInfo({
    required String filePath,
  }) =>
      getFileInfoAtPath(filePath: filePath);

  @override
  Future<Result<String, FileServiceException>> calculateFileHash({
    required String filePath,
    String algorithm = 'sha256',
  }) =>
      calculateHashForFile(filePath: filePath, algorithm: algorithm);

  // ===========================================================================
  // DIRECTORY OPERATIONS (delegated to mixin)
  // ===========================================================================

  @override
  Future<Result<List<String>, FileServiceException>> listFiles({
    required String directoryPath,
    String? pattern,
    bool recursive = false,
  }) =>
      listFilesInDirectory(
        directoryPath: directoryPath,
        pattern: pattern,
        recursive: recursive,
      );

  @override
  Future<Result<String, FileServiceException>> createDirectory({
    required String directoryPath,
    bool recursive = true,
  }) =>
      createDirectoryAtPath(directoryPath: directoryPath, recursive: recursive);

  @override
  Future<Result<bool, FileServiceException>> deleteDirectory({
    required String directoryPath,
    bool recursive = false,
  }) =>
      deleteDirectoryAtPath(
        directoryPath: directoryPath,
        recursive: recursive,
      );

  // ===========================================================================
  // PATH MANAGEMENT (delegated to watch service)
  // ===========================================================================

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

  // ===========================================================================
  // TEMP FILE MANAGEMENT (delegated to watch service)
  // ===========================================================================

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

  // ===========================================================================
  // FILE WATCHING (delegated to watch service)
  // ===========================================================================

  @override
  Stream<FileChangeEvent> watchFile({required String path}) =>
      _watchService.watchFile(path: path);

  @override
  Future<void> stopWatching({required String path}) =>
      _watchService.stopWatching(path: path);

  // ===========================================================================
  // IMPORT/EXPORT OPERATIONS (delegated to import/export service)
  // ===========================================================================

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

  // ===========================================================================
  // FILE COMPARISON (delegated to watch service)
  // ===========================================================================

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
}
