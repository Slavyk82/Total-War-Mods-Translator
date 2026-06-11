import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
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
  final ProjectLanguageRepository _languageRepository;
  final ModUpdateAnalysisCacheRepository _analysisCacheRepository;
  final ILoggingService _logger;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<InitializationLogMessage> _logController =
      StreamController<InitializationLogMessage>.broadcast();

  bool _isCancelled = false;

  ProjectInitializationServiceImpl({
    required IRpfmService rpfmService,
    required ILocalizationParser locParser,
    required TranslationUnitRepository unitRepository,
    required ProjectLanguageRepository languageRepository,
    required ModUpdateAnalysisCacheRepository analysisCacheRepository,
    ILoggingService? logger,
  })  : _rpfmService = rpfmService,
        _locParser = locParser,
        _unitRepository = unitRepository,
        _languageRepository = languageRepository,
        _analysisCacheRepository = analysisCacheRepository,
        _logger = logger ?? ServiceLocator.get<ILoggingService>();

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

      // Fetch the project's languages ONCE up front. They don't change during
      // import, so re-querying them per unit (potentially tens of thousands of
      // times) is wasted work. Cache the list and reuse it for every entry.
      final languagesResult = await _languageRepository.getByProject(projectId);
      if (languagesResult.isErr) {
        _logger.warning('Failed to get project languages', {
          'projectId': projectId,
          'error': languagesResult.error,
        });
      }
      final projectLanguages = languagesResult.isOk
          ? languagesResult.value
          : <ProjectLanguage>[];

      // Fetch the project's existing unit keys ONCE up front instead of a
      // getByKey SELECT per parsed entry. For a brand-new project this is
      // empty, but a re-init / overlapping import could already have rows;
      // this single query lets us de-dup in memory and avoid N round-trips.
      final existingUnitsResult = await _unitRepository.getByProject(projectId);
      if (existingUnitsResult.isErr) {
        _logger.warning('Failed to load existing project units', {
          'projectId': projectId,
          'error': existingUnitsResult.error,
        });
      }
      final existingKeys = existingUnitsResult.isOk
          ? existingUnitsResult.value.map((u) => u.key).toSet()
          : <String>{};

      for (int i = 0; i < locFiles.length; i++) {
        if (_isCancelled) {
          return Err(ServiceException('Initialization cancelled'));
        }

        final tsvFilePath = locFiles[i];
        final fileName = tsvFilePath.split('\\').last.split('/').last;
        
        // Extract the original .loc file path relative to extraction directory
        // TSV path: C:\temp\rpfm_extract_xxx\text\db\something.loc.tsv
        // Extraction dir: C:\temp\rpfm_extract_xxx
        // Result: text/db/something.loc
        String sourceLocFile = tsvFilePath
            .replaceAll('\\', '/')
            .replaceFirst('${extraction.outputDirectory.replaceAll('\\', '/')}/', '');
        
        // Remove .tsv extension to get the original .loc path
        if (sourceLocFile.endsWith('.tsv')) {
          sourceLocFile = sourceLocFile.substring(0, sourceLocFile.length - 4);
        }
        
        _logger.info('Parsing TSV file ${i + 1}/${locFiles.length}', {
          'file': tsvFilePath,
          'sourceLocFile': sourceLocFile,
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

        // Step 3: Build the new translation units for this file in memory,
        // de-duplicating against keys already in the project AND keys already
        // seen in this import run. We no longer issue a getByKey SELECT per
        // entry; existence is checked against the in-memory set fetched once.
        final unitsToInsert = <TranslationUnit>[];
        for (final entry in locFile.entries) {
          if (_isCancelled) {
            return Err(ServiceException('Initialization cancelled'));
          }

          // Skip duplicates (already in DB or already queued this run).
          if (!existingKeys.add(entry.key)) {
            _logger.debug('Skipping existing unit', {'key': entry.key});
            continue;
          }

          unitsToInsert.add(TranslationUnit(
            id: uuid.v4(),
            projectId: projectId,
            key: entry.key,
            sourceText: entry.value,
            context: null,
            notes: null,
            sourceLocFile: sourceLocFile,
            isObsolete: false,
            createdAt: now,
            updatedAt: now,
          ));
        }

        // Insert every unit for this file plus its per-language versions in a
        // SINGLE transaction (one commit, no O(entries x languages) awaited
        // round-trips), but isolate each unit behind a SAVEPOINT. A failing
        // insert rolls back ONLY that unit's writes (so the invariant "every
        // unit has a full version set" holds); the unit is logged with its
        // key, skipped, and not counted, and the rest of the file still
        // commits. Mirrors addNewUnits in mod_update_analysis_service.dart;
        // contract pinned by
        // test/integration/project_initialization_savepoint_test.dart.
        if (unitsToInsert.isNotEmpty) {
          const savepoint = 'sp_init_unit';
          try {
            final skippedKeys = <String>[];
            final inserted = await DatabaseService.transaction<int>((txn) async {
              var insertedCount = 0;
              for (final unit in unitsToInsert) {
                await txn.execute('SAVEPOINT $savepoint');
                try {
                  await txn.insert(
                    'translation_units',
                    unit.toJson(),
                    conflictAlgorithm: ConflictAlgorithm.abort,
                  );

                  // Create translation versions for all project languages.
                  // Uses the languages cached once before the loop above.
                  for (final language in projectLanguages) {
                    final version = TranslationVersion(
                      id: uuid.v4(),
                      unitId: unit.id,
                      projectLanguageId: language.id,
                      translatedText: null, // Empty for new imports
                      isManuallyEdited: false,
                      status: TranslationVersionStatus.pending,
                      validationIssues: null,
                      createdAt: now,
                      updatedAt: now,
                    );

                    await txn.insert(
                      'translation_versions',
                      version.toJson(),
                      conflictAlgorithm: ConflictAlgorithm.abort,
                    );
                  }

                  await txn.execute('RELEASE SAVEPOINT $savepoint');
                  insertedCount++;
                } catch (e) {
                  // Roll back only this unit's writes and keep going. NOTE:
                  // the rollback MUST go through rawQuery, not execute —
                  // sqflite's getSqlInTransactionArgument treats any statement
                  // starting with "rollback" (including ROLLBACK TO SAVEPOINT)
                  // as leaving the outer transaction, which corrupts its
                  // bookkeeping. rawQuery skips that SQL sniffing.
                  await txn.rawQuery('ROLLBACK TO SAVEPOINT $savepoint');
                  await txn.execute('RELEASE SAVEPOINT $savepoint');
                  skippedKeys.add(unit.key);
                  _logger.warning(
                      'Failed to insert unit and its versions, rolled back', {
                    'file': tsvFilePath,
                    'key': unit.key,
                    'error': e,
                  });
                }
              }
              return insertedCount;
            });
            totalUnitsImported += inserted;

            if (skippedKeys.isNotEmpty) {
              // Release the in-memory key reservations for the skipped units
              // so they are not falsely considered imported.
              skippedKeys.forEach(existingKeys.remove);
              _addLog(
                  'Skipped ${skippedKeys.length} invalid entr'
                  '${skippedKeys.length == 1 ? 'y' : 'ies'} from $fileName',
                  InitializationLogLevel.warning);
            }
          } catch (e, stackTrace) {
            // Whole-transaction failure (per-unit failures are handled by the
            // savepoints above): the batch for this file rolled back. Keep
            // behavior resilient: log and continue with the next file. Roll
            // back the in-memory key reservations for this file so they are
            // not falsely considered imported.
            for (final unit in unitsToInsert) {
              existingKeys.remove(unit.key);
            }
            _logger.warning('Failed to insert unit batch, rolled back', {
              'file': tsvFilePath,
              'units': unitsToInsert.length,
              'error': e,
              'stackTrace': stackTrace.toString(),
            });
            _addLog('Failed to import entries from $fileName: $e',
                InitializationLogLevel.warning);
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

      // Populate analysis cache to prevent re-extraction when returning to Mods screen
      // For a newly created project, there are no changes (0 new/removed/modified)
      await _populateAnalysisCache(
        projectId: projectId,
        packFilePath: packFilePath,
        totalUnits: totalUnitsImported,
      );

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

  /// Populate the analysis cache for a newly initialized project.
  ///
  /// Creates a cache entry showing no changes (0 new/removed/modified units)
  /// since the project was just created from the pack file.
  /// This prevents re-extraction when returning to the Mods screen.
  Future<void> _populateAnalysisCache({
    required String projectId,
    required String packFilePath,
    required int totalUnits,
  }) async {
    try {
      final packFile = File(packFilePath);
      if (!await packFile.exists()) {
        _logger.warning('Pack file not found for analysis cache', {
          'packFilePath': packFilePath,
        });
        return;
      }

      final fileStat = await packFile.stat();
      final fileLastModified = fileStat.modified.millisecondsSinceEpoch ~/ 1000;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final cacheEntry = ModUpdateAnalysisCache(
        id: const Uuid().v4(),
        projectId: projectId,
        packFilePath: packFilePath,
        fileLastModified: fileLastModified,
        newUnitsCount: 0,
        removedUnitsCount: 0,
        modifiedUnitsCount: 0,
        totalPackUnits: totalUnits,
        totalProjectUnits: totalUnits,
        analyzedAt: now,
      );

      await _analysisCacheRepository.upsert(cacheEntry);
      _logger.debug('Populated analysis cache for new project', {
        'projectId': projectId,
        'totalUnits': totalUnits,
      });
    } catch (e) {
      // Non-critical - cache miss will just trigger re-analysis
      _logger.warning('Failed to populate analysis cache', {
        'projectId': projectId,
        'error': e,
      });
    }
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _logController.close();
  }
}
