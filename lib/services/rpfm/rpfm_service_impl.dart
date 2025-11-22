import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';
import 'package:twmt/services/rpfm/models/rpfm_pack_info.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of RPFM service
class RpfmServiceImpl implements IRpfmService {
  final RpfmCliManager _cliManager = RpfmCliManager();
  final LoggingService _logger = LoggingService.instance;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<RpfmLogMessage> _logController =
      StreamController<RpfmLogMessage>.broadcast();

  Process? _currentProcess;
  bool _isCancelled = false;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  Stream<RpfmLogMessage> get logStream => _logController.stream;

  void _addLog(String message) {
    _logController.add(RpfmLogMessage(message: message));
  }

  @override
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
      final rpfmPathResult = await _cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Determine output directory
      final outDir = outputDirectory ??
          await _createTempDirectory('rpfm_extract_');

      await Directory(outDir).create(recursive: true);

      _logger.info('Extracting localization files from: $packFilePath');
      _logger.info('Output directory: $outDir');

      // First, list files to get only .loc files
      _logger.info('Listing pack contents...');
      final listResult = await listPackContents(packFilePath);
      if (listResult is Err) {
        _logger.error('Failed to list pack contents: ${listResult.error}');
        return Err(listResult.error);
      }

      final allFiles = (listResult as Ok).value as List<String>;
      _logger.info('Found ${allFiles.length} files in pack');
      final locFiles = RpfmOutputParser.filterLocalizationFiles(allFiles);
      _logger.info('Filtered to ${locFiles.length} localization files');

      if (locFiles.isEmpty) {
        _logger.warning('No localization files found in pack');
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

      // Get Total War game from settings
      final gameResult = await _cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Extract each .loc file
      final extractedFiles = <String>[];
      int totalSize = 0;

      for (int i = 0; i < locFiles.length; i++) {
        if (_isCancelled) {
          return Err(const RpfmCancelledException('Extraction cancelled'));
        }

        final locFile = locFiles[i];
        _logger.info('Extracting: $locFile (${i + 1}/${locFiles.length})');

        // Update progress
        _progressController.add((i + 1) / locFiles.length);

        // Execute RPFM extract command (runInShell: false for security)
        // New syntax: rpfm_cli.exe --game <GAME> pack extract --pack-path <PACK_PATH>
        //             --file-path <FILE_PATH_IN_PACK;FOLDER_TO_EXTRACT_TO>
        final filePathArg = '$locFile;$outDir';
        final result = await Process.run(
          rpfmPath,
          [
            '--game',
            game,
            'pack',
            'extract',
            '--pack-path',
            packFilePath,
            '--file-path',
            filePathArg,
          ],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          final error = RpfmOutputParser.parseErrorMessage(result.stderr);
          _logger.error('Extraction failed for $locFile: $error');
          _logger.error('RPFM stderr: ${result.stderr}');
          continue; // Skip this file but continue with others
        }

        // Get extracted file path - RPFM 4.0+ preserves directory structure
        final extractedPath = path.join(outDir, locFile);
        if (await File(extractedPath).exists()) {
          extractedFiles.add(extractedPath);
          final stat = await File(extractedPath).stat();
          totalSize += stat.size;
        } else {
          _logger.warning(
              'Extracted file not found at expected path: $extractedPath');
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      _logger.info(
          'Extraction complete: ${extractedFiles.length}/${locFiles.length} files, ${totalSize ~/ 1024}KB, ${duration}ms');

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
      _progressController.add(1.0);
      _isCancelled = false;
    }
  }

  @override
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
      final rpfmPathResult = await _cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get schema directory path (from parameter or settings)
      final schemaDir = schemaPath ?? await _cliManager.getSchemaPath();
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
      final outDir = outputDirectory ??
          await _createTempDirectory('rpfm_extract_tsv_');

      await Directory(outDir).create(recursive: true);

      _logger.info('Extracting localization files as TSV from: $packFilePath');
      _logger.info('Output directory: $outDir');

      // First, list files to get only .loc files
      _logger.info('Listing pack contents...');
      final listResult = await listPackContents(packFilePath);
      if (listResult is Err) {
        _logger.error('Failed to list pack contents: ${listResult.error}');
        return Err(listResult.error);
      }

      final allFiles = (listResult as Ok).value as List<String>;
      _logger.info('Found ${allFiles.length} files in pack');
      final locFiles = RpfmOutputParser.filterLocalizationFiles(allFiles);
      _logger.info('Filtered to ${locFiles.length} localization files');

      if (locFiles.isEmpty) {
        _logger.warning('No localization files found in pack');
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

      // Get Total War game from settings
      final gameResult = await _cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Construct full schema file path based on game
      // RPFM requires the specific schema file, not just the directory
      // Map game name to schema file name (e.g., 'warhammer_3' -> 'wh3')
      final schemaFileName = _getSchemaFileName(game);
      final schemaFile = path.join(schemaDir, 'schema_$schemaFileName.ron');

      // Validate schema file exists
      if (!await File(schemaFile).exists()) {
        return Err(RpfmServiceException(
          'RPFM schema file not found: $schemaFile\n'
          'Make sure the schema directory contains schema_$schemaFileName.ron',
        ));
      }

      _logger.info('Using schema file: $schemaFile');

      // Extract each .loc file as TSV
      final extractedFiles = <String>[];
      int totalSize = 0;

      for (int i = 0; i < locFiles.length; i++) {
        if (_isCancelled) {
          return Err(const RpfmCancelledException('Extraction cancelled'));
        }

        final locFile = locFiles[i];
        _logger.info('Extracting as TSV: $locFile (${i + 1}/${locFiles.length})');
        _addLog('Extracting as TSV: $locFile (${i + 1}/${locFiles.length})');

        // Update progress
        _progressController.add((i + 1) / locFiles.length);

        // Execute RPFM extract command with --tables-as-tsv
        // Command: rpfm_cli.exe --game <GAME> pack extract --pack-path <PACK_PATH>
        //          --file-path <FILE_PATH_IN_PACK;FOLDER_TO_EXTRACT_TO>
        //          --tables-as-tsv <SCHEMA_FILE_PATH>
        final filePathArg = '$locFile;$outDir';
        final result = await Process.run(
          rpfmPath,
          [
            '--game',
            game,
            'pack',
            'extract',
            '--pack-path',
            packFilePath,
            '--file-path',
            filePathArg,
            '--tables-as-tsv',
            schemaFile,
          ],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          final error = RpfmOutputParser.parseErrorMessage(result.stderr);
          _logger.error('TSV extraction failed for $locFile: $error');
          _logger.error('RPFM stderr: ${result.stderr}');
          continue; // Skip this file but continue with others
        }

        // Get extracted TSV file path - RPFM adds .tsv extension
        // Normalize path separators for Windows (replace / with \)
        final normalizedPath = locFile.replaceAll('/', path.separator);
        final extractedPath = path.join(outDir, '$normalizedPath.tsv');
        if (await File(extractedPath).exists()) {
          extractedFiles.add(extractedPath);
          final stat = await File(extractedPath).stat();
          totalSize += stat.size;
          _logger.info('TSV file created: $extractedPath (${stat.size ~/ 1024}KB)');
          _addLog('TSV file created: $extractedPath (${stat.size ~/ 1024}KB)');
        } else {
          _logger.warning(
              'Extracted TSV file not found at expected path: $extractedPath');
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      _logger.info(
          'TSV extraction complete: ${extractedFiles.length}/${locFiles.length} files, ${totalSize ~/ 1024}KB, ${duration}ms');

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
      _progressController.add(1.0);
      _isCancelled = false;
    }
  }

  @override
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
      final rpfmPathResult = await _cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      await Directory(outputDirectory).create(recursive: true);

      _logger.info('Extracting all files from: $packFilePath');

      // Get Total War game from settings
      final gameResult = await _cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Calculate timeout based on file size
      final packStat = await File(packFilePath).stat();
      final timeoutSec = RpfmOutputParser.calculateTimeout(packStat.size);

      // Execute RPFM extract all command (runInShell: false for security)
      // New syntax: rpfm_cli.exe --game <GAME> pack extract --pack-path <PACK_PATH>
      //             --folder-path /;output_directory
      _logger.info('Executing RPFM extract all command');
      final folderPathArg = '/;$outputDirectory';
      _currentProcess = await Process.start(
        rpfmPath,
        [
          '--game',
          game,
          'pack',
          'extract',
          '--pack-path',
          packFilePath,
          '--folder-path',
          folderPathArg,
        ],
        runInShell: false,
      );

      // Capture output
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      _currentProcess!.stdout.listen((data) {
        stdout.write(String.fromCharCodes(data));
      });

      _currentProcess!.stderr.listen((data) {
        stderr.write(String.fromCharCodes(data));
      });

      // Wait with timeout
      final exitCode = await _currentProcess!.exitCode.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          _currentProcess?.kill();
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
      _currentProcess = null;
      _isCancelled = false;
    }
  }

  @override
  Future<Result<String, RpfmServiceException>> createPack({
    required String inputDirectory,
    required String languageCode,
    required String outputPackPath,
  }) async {
    try {
      // Validate input directory exists
      if (!await Directory(inputDirectory).exists()) {
        return Err(RpfmPackingException(
          'Input directory not found: $inputDirectory',
        ));
      }

      // Get RPFM path
      final rpfmPathResult = await _cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get Total War game from settings
      final gameResult = await _cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Create output directory if needed
      final outputDir = path.dirname(outputPackPath);
      await Directory(outputDir).create(recursive: true);

      _logger.info('Creating pack: $outputPackPath');
      _logger.info('From directory: $inputDirectory');
      _logger.info('Language: $languageCode');

      // Step 1: Create empty pack
      // New syntax: rpfm_cli.exe --game <GAME> pack create --pack-path <PATH>
      var result = await Process.run(
        rpfmPath,
        [
          '--game',
          game,
          'pack',
          'create',
          '--pack-path',
          outputPackPath,
        ],
        runInShell: false,
      );

      if (result.exitCode != 0) {
        final error = RpfmOutputParser.parseErrorMessage(result.stderr);
        return Err(RpfmPackingException(
          'Failed to create empty pack: $error',
          outputPath: outputPackPath,
        ));
      }

      _logger.info('Empty pack created, now adding files...');

      // Step 2: Add files with prefix
      // Prefix format: !!!!!!!!!!_{LANG}_filename.loc
      final prefix = '!!!!!!!!!!_${languageCode.toUpperCase()}_';

      // Get all .loc files from input directory
      final locFiles = await _listDirectoryFiles(inputDirectory);
      final filteredFiles =
          locFiles.where((f) => f.toLowerCase().endsWith('.loc')).toList();

      _logger.info('Found ${filteredFiles.length} .loc files to add');

      // Add each file with prefixed name
      for (final filePath in filteredFiles) {
        final fileName = path.basename(filePath);
        final prefixedName = '$prefix$fileName';

        // Determine the internal pack path (text/filename.loc)
        final relativePath = path.relative(filePath, from: inputDirectory);
        final packPath = path.dirname(relativePath) == '.'
            ? 'text/$prefixedName'
            : '${path.dirname(relativePath)}/$prefixedName';

        // New syntax: rpfm_cli.exe --game <GAME> pack add --pack-path <PACK_PATH>
        //             --file-path <FILE_PATH;FOLDER_TO_ADD_TO>
        final filePathArg = '$filePath;$packPath';

        _logger.info('Adding: $fileName as $prefixedName');

        result = await Process.run(
          rpfmPath,
          [
            '--game',
            game,
            'pack',
            'add',
            '--pack-path',
            outputPackPath,
            '--file-path',
            filePathArg,
          ],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          final error = RpfmOutputParser.parseErrorMessage(result.stderr);
          _logger.warning('Failed to add file $fileName: $error');
          // Continue with other files
        }
      }

      // Verify pack was created
      if (!await File(outputPackPath).exists()) {
        return Err(RpfmPackingException(
          'Pack file was not created',
          outputPath: outputPackPath,
        ));
      }

      _logger.info('Pack created successfully: $outputPackPath');

      return Ok(outputPackPath);
    } catch (e, stackTrace) {
      return Err(RpfmPackingException(
        'Packing failed: $e',
        outputPath: outputPackPath,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<RpfmPackInfo, RpfmServiceException>> getPackInfo(
    String packFilePath,
  ) async {
    try {
      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return Err(RpfmInvalidPackException(
          'Pack file not found',
          packFilePath: packFilePath,
        ));
      }

      // Get file stats
      final stat = await File(packFilePath).stat();
      final fileName = path.basename(packFilePath);

      // Get file list to count files
      final listResult = await listPackContents(packFilePath);
      if (listResult is Err) {
        return Err(listResult.error);
      }

      final files = (listResult as Ok).value as List<String>;
      final locFileCount = RpfmOutputParser.countLocalizationFiles(files);

      return Ok(RpfmPackInfo(
        packFilePath: packFilePath,
        fileName: fileName,
        sizeBytes: stat.size,
        fileCount: files.length,
        localizationFileCount: locFileCount,
        lastModified: stat.modified,
      ));
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Failed to get pack info: $e',
        code: 'PACK_INFO_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<String>, RpfmServiceException>> listPackContents(
    String packFilePath,
  ) async {
    try {
      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return Err(RpfmInvalidPackException(
          'Pack file not found',
          packFilePath: packFilePath,
        ));
      }

      // Get RPFM path
      final rpfmPathResult = await _cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get Total War game from settings
      final gameResult = await _cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Execute RPFM list command (runInShell: false for security)
      // New syntax: rpfm_cli.exe --game <GAME> pack list --pack-path <PATH>
      _logger.info(
          'Executing RPFM list command: $rpfmPath --game $game pack list --pack-path $packFilePath');
      final result = await Process.run(
        rpfmPath,
        [
          '--game',
          game,
          'pack',
          'list',
          '--pack-path',
          packFilePath,
        ],
        runInShell: false,
      );

      _logger.info('RPFM list command exit code: ${result.exitCode}');

      if (result.exitCode != 0) {
        final error = RpfmOutputParser.parseErrorMessage(result.stderr);
        _logger.error('RPFM stderr: ${result.stderr}');
        return Err(RpfmServiceException(
          'Failed to list pack contents: $error',
          code: 'LIST_ERROR',
        ));
      }

      _logger.info(
          'RPFM stdout length: ${result.stdout.toString().length} bytes');
      final files = RpfmOutputParser.parseFileList(result.stdout);
      _logger.info('Parsed ${files.length} files from RPFM output');
      return Ok(files);
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Failed to list pack contents: $e',
        code: 'LIST_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<bool> isRpfmAvailable() async {
    return await _cliManager.isAvailable();
  }

  @override
  Future<Result<String, RpfmServiceException>> getRpfmVersion() async {
    return await _cliManager.getVersion();
  }

  @override
  Future<Result<String, RpfmServiceException>> downloadRpfm({
    bool force = false,
  }) async {
    return await _cliManager.downloadAndInstall(
      onProgress: (progress) => _progressController.add(progress),
    );
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentProcess?.kill();
    _currentProcess = null;
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

  /// Map game name to schema file name
  ///
  /// RPFM uses full game names (e.g., 'warhammer_3') for the --game flag,
  /// but schema files use short names (e.g., 'wh3')
  String _getSchemaFileName(String gameName) {
    const gameToSchemaMap = {
      'warhammer_3': 'wh3',
      'warhammer_2': 'wh2',
      'warhammer': 'wh',
      'three_kingdoms': '3k',
      'troy': 'troy',
      'pharaoh': 'pharaoh',
      'pharaoh_dynasties': 'pharaoh_dynasties',
      'thrones_of_britannia': 'tob',
      'attila': 'att',
      'rome_2': 'rom2',
      'shogun_2': 'sho2',
      'napoleon': 'nap',
      'empire': 'emp',
      'arena': 'arena',
    };

    return gameToSchemaMap[gameName] ?? gameName;
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _currentProcess?.kill();
  }
}
