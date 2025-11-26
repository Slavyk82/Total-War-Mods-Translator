import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/rpfm/utils/rpfm_game_schema.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Mixin providing extraction operations for RPFM service
mixin RpfmExtractionMixin {
  RpfmCliManager get cliManager;
  LoggingService get logger;
  StreamController<double> get progressController;
  StreamController<RpfmLogMessage> get logController;
  bool get isCancelled;
  set isCancelled(bool value);
  Process? get currentProcess;
  set currentProcess(Process? value);

  /// List pack contents (required for extraction filtering)
  Future<Result<List<String>, RpfmServiceException>> listPackContents(
    String packFilePath,
  );

  void _addLog(String message) {
    logController.add(RpfmLogMessage(message: message));
  }

  /// Extract localization files from a .pack file (binary format)
  Future<Result<RpfmExtractResult, RpfmServiceException>>
      extractLocalizationFiles(
    String packFilePath, {
    String? outputDirectory,
  }) async {
    final startTime = DateTime.now();

    try {
      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return Err(RpfmInvalidPackException(
          'Pack file not found',
          packFilePath: packFilePath,
        ));
      }

      // Get RPFM path
      final rpfmPathResult = await cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Determine output directory
      final outDir = outputDirectory ?? await _createTempDirectory('rpfm_extract_');
      await Directory(outDir).create(recursive: true);

      logger.info('Extracting localization files from: $packFilePath');
      logger.info('Output directory: $outDir');

      // List files to get only .loc files
      logger.info('Listing pack contents...');
      final listResult = await listPackContents(packFilePath);
      if (listResult is Err) {
        logger.error('Failed to list pack contents: ${listResult.error}');
        return Err(listResult.error);
      }

      final allFiles = (listResult as Ok).value as List<String>;
      logger.info('Found ${allFiles.length} files in pack');
      final locFiles = RpfmOutputParser.filterLocalizationFiles(allFiles);
      logger.info('Filtered to ${locFiles.length} localization files');

      if (locFiles.isEmpty) {
        return _createEmptyResult(packFilePath, outDir, startTime);
      }

      // Get Total War game from settings
      final gameResult = await cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Extract each .loc file
      final extractedFiles = <String>[];
      int totalSize = 0;

      for (int i = 0; i < locFiles.length; i++) {
        if (isCancelled) {
          return Err(const RpfmCancelledException('Extraction cancelled'));
        }

        final locFile = locFiles[i];
        logger.info('Extracting: $locFile (${i + 1}/${locFiles.length})');
        progressController.add((i + 1) / locFiles.length);

        final filePathArg = '$locFile;$outDir';
        final result = await Process.run(
          rpfmPath,
          ['--game', game, 'pack', 'extract', '--pack-path', packFilePath, '--file-path', filePathArg],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          final error = RpfmOutputParser.parseErrorMessage(result.stderr);
          logger.error('Extraction failed for $locFile: $error');
          logger.error('RPFM stderr: ${result.stderr}');
          continue;
        }

        final extractedPath = path.join(outDir, locFile);
        if (await File(extractedPath).exists()) {
          extractedFiles.add(extractedPath);
          final stat = await File(extractedPath).stat();
          totalSize += stat.size;
        } else {
          logger.warning('Extracted file not found at expected path: $extractedPath');
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      logger.info('Extraction complete: ${extractedFiles.length}/${locFiles.length} files, ${totalSize ~/ 1024}KB, ${duration}ms');

      return Ok(RpfmExtractResult(
        packFilePath: packFilePath,
        outputDirectory: outDir,
        extractedFiles: extractedFiles,
        localizationFileCount: extractedFiles.length,
        totalSizeBytes: totalSize,
        durationMs: duration,
        timestamp: DateTime.now(),
      ));
    } catch (e, stackTrace) {
      return Err(RpfmExtractionException(
        'Extraction failed: $e',
        packFilePath: packFilePath,
        stackTrace: stackTrace,
      ));
    } finally {
      progressController.add(1.0);
      isCancelled = false;
    }
  }

  /// Extract localization files from a .pack file as TSV format
  Future<Result<RpfmExtractResult, RpfmServiceException>>
      extractLocalizationFilesAsTsv(
    String packFilePath, {
    String? outputDirectory,
    String? schemaPath,
  }) async {
    final startTime = DateTime.now();

    try {
      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return Err(RpfmInvalidPackException(
          'Pack file not found',
          packFilePath: packFilePath,
        ));
      }

      // Get RPFM path
      final rpfmPathResult = await cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get schema directory path (from parameter or settings)
      final schemaDir = schemaPath ?? await cliManager.getSchemaPath();
      if (schemaDir == null || schemaDir.isEmpty) {
        return Err(const RpfmServiceException(
          'RPFM schema path not configured. Please set it in Settings > RPFM Tool.',
        ));
      }

      // Validate schema directory exists
      if (!await Directory(schemaDir).exists()) {
        return Err(RpfmServiceException(
          'RPFM schema directory not found: $schemaDir',
        ));
      }

      // Determine output directory
      final outDir = outputDirectory ?? await _createTempDirectory('rpfm_extract_tsv_');
      await Directory(outDir).create(recursive: true);

      logger.info('Extracting localization files as TSV from: $packFilePath');
      logger.info('Output directory: $outDir');

      // List files to get only .loc files
      logger.info('Listing pack contents...');
      final listResult = await listPackContents(packFilePath);
      if (listResult is Err) {
        logger.error('Failed to list pack contents: ${listResult.error}');
        return Err(listResult.error);
      }

      final allFiles = (listResult as Ok).value as List<String>;
      logger.info('Found ${allFiles.length} files in pack');
      final locFiles = RpfmOutputParser.filterLocalizationFiles(allFiles);
      logger.info('Filtered to ${locFiles.length} localization files');

      if (locFiles.isEmpty) {
        return _createEmptyResult(packFilePath, outDir, startTime);
      }

      // Get Total War game from settings
      final gameResult = await cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Construct full schema file path based on game
      final schemaFile = RpfmGameSchema.getSchemaFilePath(schemaDir, game);

      // Validate schema file exists
      if (!await File(schemaFile).exists()) {
        final schemaFileName = RpfmGameSchema.getSchemaFileName(game);
        return Err(RpfmServiceException(
          'RPFM schema file not found: $schemaFile\n'
          'Make sure the schema directory contains schema_$schemaFileName.ron',
        ));
      }

      logger.info('Using schema file: $schemaFile');

      // Extract each .loc file as TSV
      final extractedFiles = <String>[];
      int totalSize = 0;

      for (int i = 0; i < locFiles.length; i++) {
        if (isCancelled) {
          return Err(const RpfmCancelledException('Extraction cancelled'));
        }

        final locFile = locFiles[i];
        logger.info('Extracting as TSV: $locFile (${i + 1}/${locFiles.length})');
        _addLog('Extracting as TSV: $locFile (${i + 1}/${locFiles.length})');

        progressController.add((i + 1) / locFiles.length);

        final filePathArg = '$locFile;$outDir';
        final result = await Process.run(
          rpfmPath,
          ['--game', game, 'pack', 'extract', '--pack-path', packFilePath, '--file-path', filePathArg, '--tables-as-tsv', schemaFile],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          final error = RpfmOutputParser.parseErrorMessage(result.stderr);
          logger.error('TSV extraction failed for $locFile: $error');
          logger.error('RPFM stderr: ${result.stderr}');
          continue;
        }

        // Get extracted TSV file path - RPFM adds .tsv extension
        final normalizedPath = locFile.replaceAll('/', path.separator);
        final extractedPath = path.join(outDir, '$normalizedPath.tsv');
        if (await File(extractedPath).exists()) {
          extractedFiles.add(extractedPath);
          final stat = await File(extractedPath).stat();
          totalSize += stat.size;
          logger.info('TSV file created: $extractedPath (${stat.size ~/ 1024}KB)');
          _addLog('TSV file created: $extractedPath (${stat.size ~/ 1024}KB)');
        } else {
          logger.warning('Extracted TSV file not found at expected path: $extractedPath');
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      logger.info('TSV extraction complete: ${extractedFiles.length}/${locFiles.length} files, ${totalSize ~/ 1024}KB, ${duration}ms');

      return Ok(RpfmExtractResult(
        packFilePath: packFilePath,
        outputDirectory: outDir,
        extractedFiles: extractedFiles,
        localizationFileCount: extractedFiles.length,
        totalSizeBytes: totalSize,
        durationMs: duration,
        timestamp: DateTime.now(),
      ));
    } catch (e, stackTrace) {
      return Err(RpfmExtractionException(
        'TSV extraction failed: $e',
        packFilePath: packFilePath,
        stackTrace: stackTrace,
      ));
    } finally {
      progressController.add(1.0);
      isCancelled = false;
    }
  }

  /// Extract all files from a .pack file
  Future<Result<RpfmExtractResult, RpfmServiceException>> extractAllFiles(
    String packFilePath,
    String outputDirectory,
  ) async {
    final startTime = DateTime.now();

    try {
      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return Err(RpfmInvalidPackException(
          'Pack file not found',
          packFilePath: packFilePath,
        ));
      }

      // Get RPFM path
      final rpfmPathResult = await cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      await Directory(outputDirectory).create(recursive: true);

      logger.info('Extracting all files from: $packFilePath');

      // Get Total War game from settings
      final gameResult = await cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Calculate timeout based on file size
      final packStat = await File(packFilePath).stat();
      final timeoutSec = RpfmOutputParser.calculateTimeout(packStat.size);

      // Execute RPFM extract all command
      logger.info('Executing RPFM extract all command');
      final folderPathArg = '/;$outputDirectory';
      currentProcess = await Process.start(
        rpfmPath,
        ['--game', game, 'pack', 'extract', '--pack-path', packFilePath, '--folder-path', folderPathArg],
        runInShell: false,
      );

      // Capture output
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      currentProcess!.stdout.listen((data) {
        stdout.write(String.fromCharCodes(data));
      });

      currentProcess!.stderr.listen((data) {
        stderr.write(String.fromCharCodes(data));
      });

      // Wait with timeout
      final exitCode = await currentProcess!.exitCode.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          currentProcess?.kill();
          return -1;
        },
      );

      if (exitCode == -1) {
        return Err(RpfmTimeoutException(
          'Extraction timed out',
          timeoutSeconds: timeoutSec,
        ));
      }

      if (exitCode != 0) {
        final error = RpfmOutputParser.parseErrorMessage(stderr.toString());
        return Err(RpfmExtractionException(
          error,
          packFilePath: packFilePath,
        ));
      }

      // Count extracted files
      final extractedFiles = await _listDirectoryFiles(outputDirectory);
      final locFiles = RpfmOutputParser.filterLocalizationFiles(extractedFiles);

      // Calculate total size
      int totalSize = 0;
      for (final file in extractedFiles) {
        final stat = await File(file).stat();
        totalSize += stat.size;
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      return Ok(RpfmExtractResult(
        packFilePath: packFilePath,
        outputDirectory: outputDirectory,
        extractedFiles: extractedFiles,
        localizationFileCount: locFiles.length,
        totalSizeBytes: totalSize,
        durationMs: duration,
        timestamp: DateTime.now(),
      ));
    } catch (e, stackTrace) {
      return Err(RpfmExtractionException(
        'Extraction failed: $e',
        packFilePath: packFilePath,
        stackTrace: stackTrace,
      ));
    } finally {
      currentProcess = null;
      isCancelled = false;
    }
  }

  /// Create empty result for when no localization files are found
  Ok<RpfmExtractResult, RpfmServiceException> _createEmptyResult(
    String packFilePath,
    String outDir,
    DateTime startTime,
  ) {
    logger.warning('No localization files found in pack');
    return Ok(RpfmExtractResult(
      packFilePath: packFilePath,
      outputDirectory: outDir,
      extractedFiles: [],
      localizationFileCount: 0,
      totalSizeBytes: 0,
      durationMs: DateTime.now().difference(startTime).inMilliseconds,
      timestamp: DateTime.now(),
    ));
  }

  /// Create temporary directory for extraction
  Future<String> _createTempDirectory(String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final extractDir = await Directory(
      path.join(tempDir.path, '$prefix${DateTime.now().millisecondsSinceEpoch}'),
    ).create(recursive: true);
    return extractDir.path;
  }

  /// List all files in directory recursively
  Future<List<String>> _listDirectoryFiles(String dirPath) async {
    final files = <String>[];
    final dir = Directory(dirPath);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        files.add(entity.path);
      }
    }

    return files;
  }
}
