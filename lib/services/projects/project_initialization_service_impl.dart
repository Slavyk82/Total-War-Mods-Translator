import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'i_project_initialization_service.dart';

/// Implementation of project initialization service
///
/// Orchestrates the complete workflow of extracting LOC files from pack
/// files and importing them into the database as translation units.
class ProjectInitializationServiceImpl
    implements IProjectInitializationService {
  final IRpfmService _rpfmService;
  final ILocalizationParser _locParser;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _languageRepository;
  final LoggingService _logger;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<InitializationLogMessage> _logController =
      StreamController<InitializationLogMessage>.broadcast();

  bool _isCancelled = false;

  ProjectInitializationServiceImpl({
    required IRpfmService rpfmService,
    required ILocalizationParser locParser,
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository languageRepository,
    LoggingService? logger,
  })  : _rpfmService = rpfmService,
        _locParser = locParser,
        _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _languageRepository = languageRepository,
        _logger = logger ?? LoggingService.instance;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  Stream<InitializationLogMessage> get logStream => _logController.stream;

  void _addLog(String message, InitializationLogLevel level) {
    _logController.add(InitializationLogMessage(
      message: message,
      level: level,
    ));
  }

  @override
  Future<Result<int, ServiceException>> initializeProject({
    required String projectId,
    required String packFilePath,
  }) async {
    final startTime = DateTime.now();
    _isCancelled = false;

    try {
      _logger.info('Initializing project', {
        'projectId': projectId,
        'packFilePath': packFilePath,
      });

      // Step 1: Extract .loc files from .pack using RPFM as TSV format
      _progressController.add(0.0);
      _logger.info('Step 1/3: Extracting .loc files as TSV from pack');
      _addLog('Extracting localization files from pack file...', InitializationLogLevel.info);

      // Listen to RPFM logs and forward them
      final rpfmLogSubscription = _rpfmService.logStream.listen((rpfmLog) {
        _addLog(rpfmLog.message, InitializationLogLevel.info);
      });

      final extractResult = await _rpfmService.extractLocalizationFilesAsTsv(
        packFilePath,
      );

      // Cancel RPFM log subscription
      await rpfmLogSubscription.cancel();

      if (extractResult.isErr) {
        return Err(ServiceException(
          'Failed to extract .loc files: ${extractResult.error}',
        ));
      }

      final extraction = extractResult.value;
      final locFiles = extraction.extractedFiles;

      _logger.info('Extracted ${locFiles.length} .loc files', {
        'outputDirectory': extraction.outputDirectory,
      });
      _addLog('Found ${locFiles.length} localization file(s)', InitializationLogLevel.info);

      if (locFiles.isEmpty) {
        _addLog('No localization files found in pack file', InitializationLogLevel.error);
        return Err(ServiceException(
          'No .loc files found in pack file',
        ));
      }

      if (_isCancelled) {
        return Err(ServiceException('Initialization cancelled'));
      }

      _progressController.add(0.3);

      // Step 2: Parse each .loc file
      _logger.info('Step 2/3: Parsing .loc files');
      _addLog('Parsing and importing localization files...', InitializationLogLevel.info);

      int totalUnitsImported = 0;
      const uuid = Uuid();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (int i = 0; i < locFiles.length; i++) {
        if (_isCancelled) {
          return Err(ServiceException('Initialization cancelled'));
        }

        final tsvFilePath = locFiles[i];
        final fileName = tsvFilePath.split('\\').last.split('/').last;
        
        _logger.info('Parsing TSV file ${i + 1}/${locFiles.length}', {
          'file': tsvFilePath,
        });
        _addLog('Processing file ${i + 1}/${locFiles.length}: $fileName', InitializationLogLevel.info);

        // Parse the TSV file (no encoding detection needed - TSV is always UTF-8)
        final parseResult = await _locParser.parseFile(
          filePath: tsvFilePath,
          encoding: 'utf-8',
        );

        if (parseResult.isErr) {
          _logger.warning('Failed to parse TSV file', {
            'file': tsvFilePath,
            'error': parseResult.error,
          });
          _addLog('Failed to parse $fileName: ${parseResult.error}', InitializationLogLevel.warning);
          continue; // Skip this file but continue with others
        }

        final locFile = parseResult.value;
        _logger.info('Parsed ${locFile.entries.length} entries', {
          'file': tsvFilePath,
        });
        _addLog('Importing ${locFile.entries.length} entries from $fileName', InitializationLogLevel.info);

        // Step 3: Create translation_units in database
        for (final entry in locFile.entries) {
          if (_isCancelled) {
            return Err(ServiceException('Initialization cancelled'));
          }

          // Check if unit already exists (avoid duplicates)
          final existingResult = await _unitRepository.getByKey(
            projectId,
            entry.key,
          );

          if (existingResult.isOk) {
            // Unit already exists, skip
            _logger.debug('Skipping existing unit', {'key': entry.key});
            continue;
          }

          // Create new translation unit
          final unit = TranslationUnit(
            id: uuid.v4(),
            projectId: projectId,
            key: entry.key,
            sourceText: entry.value,
            context: null,
            notes: null,
            isObsolete: false,
            createdAt: now,
            updatedAt: now,
          );

          final insertResult = await _unitRepository.insert(unit);

          if (insertResult.isErr) {
            _logger.warning('Failed to insert translation unit', {
              'key': entry.key,
              'error': insertResult.error,
            });
            continue;
          }

          totalUnitsImported++;

          // Create translation versions for all project languages
          final languagesResult = await _languageRepository.getByProject(projectId);
          if (languagesResult.isOk) {
            final languages = languagesResult.value;
            for (final language in languages) {
              final version = TranslationVersion(
                id: uuid.v4(),
                unitId: unit.id,
                projectLanguageId: language.id,
                translatedText: null, // Empty for new imports
                isManuallyEdited: false,
                status: TranslationVersionStatus.pending,
                confidenceScore: null,
                validationIssues: null,
                createdAt: now,
                updatedAt: now,
              );

              final versionResult = await _versionRepository.insert(version);
              if (versionResult.isErr) {
                _logger.warning('Failed to insert translation version', {
                  'unitId': unit.id,
                  'projectLanguageId': language.id,
                  'error': versionResult.error,
                });
              }
            }
          } else {
            _logger.warning('Failed to get project languages', {
              'projectId': projectId,
              'error': languagesResult.error,
            });
          }
        }

        // Update progress
        final progress = 0.3 + (0.7 * (i + 1) / locFiles.length);
        _progressController.add(progress);
      }

      // Clean up: Delete temporary extraction directory
      try {
        final extractionDir = Directory(extraction.outputDirectory);
        if (await extractionDir.exists()) {
          await extractionDir.delete(recursive: true);
          _logger.debug('Cleaned up extraction directory', {
            'directory': extraction.outputDirectory,
          });
        }
      } catch (e) {
        _logger.warning('Failed to clean up extraction directory', {
          'directory': extraction.outputDirectory,
          'error': e,
        });
      }

      _progressController.add(1.0);

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      _logger.info('Project initialization complete', {
        'projectId': projectId,
        'unitsImported': totalUnitsImported,
        'durationMs': duration,
      });
      _addLog('Import completed: $totalUnitsImported translation units imported (${duration}ms)', InitializationLogLevel.info);

      return Ok(totalUnitsImported);
    } catch (e, stackTrace) {
      _logger.error('Project initialization failed', e, stackTrace);

      return Err(ServiceException(
        'Project initialization failed: $e',
        stackTrace: stackTrace,
      ));
    } finally {
      _isCancelled = false;
    }
  }

  @override
  Future<void> cancel() async {
    _logger.info('Cancelling project initialization');
    _isCancelled = true;
    await _rpfmService.cancel();
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _logController.close();
  }
}
