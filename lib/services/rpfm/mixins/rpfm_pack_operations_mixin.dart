import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/models/rpfm_pack_info.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/rpfm/utils/rpfm_game_schema.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Mixin providing pack creation and inspection operations for RPFM service
mixin RpfmPackOperationsMixin {
  RpfmCliManager get cliManager;
  LoggingService get logger;

  /// Create a .pack file from directory
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
      final rpfmPathResult = await cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get Total War game from settings
      final gameResult = await cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Get schema path for TSV conversion
      final schemaDir = await cliManager.getSchemaPath();
      if (schemaDir == null || schemaDir.isEmpty) {
        return Err(const RpfmServiceException(
          'RPFM schema path not configured. Please set it in Settings > RPFM Tool.',
        ));
      }

      // Build schema file path
      final schemaFile = RpfmGameSchema.getSchemaFilePath(schemaDir, game);

      if (!await File(schemaFile).exists()) {
        return Err(RpfmServiceException(
          'RPFM schema file not found: $schemaFile',
        ));
      }

      // Create output directory if needed
      final outputDir = path.dirname(outputPackPath);
      await Directory(outputDir).create(recursive: true);

      logger.info('Creating pack: $outputPackPath');
      logger.info('From directory: $inputDirectory');
      logger.info('Language: $languageCode');
      logger.info('Using schema: $schemaFile');

      // Step 1: Create empty pack
      var result = await Process.run(
        rpfmPath,
        ['--game', game, 'pack', 'create', '--pack-path', outputPackPath],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) {
        final error = RpfmOutputParser.parseErrorMessage(result.stderr);
        return Err(RpfmPackingException(
          'Failed to create empty pack: $error',
          outputPath: outputPackPath,
        ));
      }

      logger.info('Empty pack created, now adding TSV files with conversion...');

      // Step 2: Find and add TSV files with --tsv-to-binary conversion
      final allFiles = await _listDirectoryFiles(inputDirectory);
      final tsvFiles = allFiles.where((f) => f.toLowerCase().endsWith('.tsv')).toList();

      logger.info('Found ${tsvFiles.length} TSV files to add');

      if (tsvFiles.isEmpty) {
        // Fallback: check for .loc files (legacy support)
        final locFiles = allFiles.where((f) => f.toLowerCase().endsWith('.loc')).toList();
        if (locFiles.isNotEmpty) {
          logger.warning('No TSV files found, falling back to .loc files (may cause issues)');
          for (final filePath in locFiles) {
            final relativePath = path.relative(filePath, from: inputDirectory);
            final packPath = relativePath.replaceAll('\\', '/');
            final filePathArg = '$filePath;$packPath';

            result = await Process.run(
              rpfmPath,
              ['--game', game, 'pack', 'add', '--pack-path', outputPackPath, '--file-path', filePathArg],
              runInShell: false,
              stdoutEncoding: utf8,
              stderrEncoding: utf8,
            );

            if (result.exitCode != 0) {
              final error = RpfmOutputParser.parseErrorMessage(result.stderr);
              logger.warning('Failed to add .loc file: $error');
            }
          }
        }
      } else {
        // Add TSV files with --tsv-to-binary conversion
        for (final tsvFilePath in tsvFiles) {
          // Get relative path from input directory
          final relativePath = path.relative(tsvFilePath, from: inputDirectory);

          // Remove .tsv extension to get the target .loc path
          final targetPath = relativePath.replaceAll('.tsv', '').replaceAll('\\', '/');

          logger.info('Adding TSV: $relativePath -> $targetPath');

          final filePathArg = '$tsvFilePath;$targetPath';

          result = await Process.run(
            rpfmPath,
            ['--game', game, 'pack', 'add', '--pack-path', outputPackPath, '--file-path', filePathArg, '--tsv-to-binary', schemaFile],
            runInShell: false,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );

          if (result.exitCode != 0) {
            final error = RpfmOutputParser.parseErrorMessage(result.stderr);
            logger.error('Failed to add TSV file: $error');
            logger.error('RPFM stderr: ${result.stderr}');
            logger.error('RPFM stdout: ${result.stdout}');
            return Err(RpfmPackingException(
              'Failed to add TSV file to pack: $error\nFile: $tsvFilePath',
              outputPath: outputPackPath,
            ));
          }

          logger.info('Successfully added: $targetPath');
        }
      }

      // Verify pack was created and has content
      if (!await File(outputPackPath).exists()) {
        return Err(RpfmPackingException(
          'Pack file was not created',
          outputPath: outputPackPath,
        ));
      }

      final packSize = await File(outputPackPath).length();
      logger.info('Pack created successfully: $outputPackPath (${packSize ~/ 1024}KB)');

      return Ok(outputPackPath);
    } catch (e, stackTrace) {
      return Err(RpfmPackingException(
        'Packing failed: $e',
        outputPath: outputPackPath,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get metadata about a .pack file
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

  /// List contents of a .pack file
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
      final rpfmPathResult = await cliManager.getRpfmPath();
      if (rpfmPathResult is Err) {
        return Err(rpfmPathResult.error);
      }
      final rpfmPath = (rpfmPathResult as Ok).value as String;

      // Get Total War game from settings
      final gameResult = await cliManager.getGameSetting();
      if (gameResult is Err) {
        return Err(gameResult.error);
      }
      final game = (gameResult as Ok).value as String;

      // Execute RPFM list command
      logger.info('Executing RPFM list command: $rpfmPath --game $game pack list --pack-path $packFilePath');
      final result = await Process.run(
        rpfmPath,
        ['--game', game, 'pack', 'list', '--pack-path', packFilePath],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      logger.info('RPFM list command exit code: ${result.exitCode}');

      if (result.exitCode != 0) {
        final error = RpfmOutputParser.parseErrorMessage(result.stderr);
        logger.error('RPFM stderr: ${result.stderr}');
        return Err(RpfmServiceException(
          'Failed to list pack contents: $error',
          code: 'LIST_ERROR',
        ));
      }

      logger.info('RPFM stdout length: ${result.stdout.toString().length} bytes');
      final files = RpfmOutputParser.parseFileList(result.stdout);
      logger.info('Parsed ${files.length} files from RPFM output');
      return Ok(files);
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Failed to list pack contents: $e',
        code: 'LIST_ERROR',
        stackTrace: stackTrace,
      ));
    }
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
