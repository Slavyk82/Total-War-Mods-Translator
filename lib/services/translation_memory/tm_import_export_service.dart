import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/language_id.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Translation Memory import/export service
///
/// Handles:
/// - TMX file import with progress tracking
/// - TMX file export with filtering
/// - Entry persistence and deduplication
/// - Progress callbacks for UI
class TmImportExportService {
  final TranslationMemoryRepository _repository;
  final TmxService _tmxService;
  final ILoggingService _logger;

  const TmImportExportService({
    required TranslationMemoryRepository repository,
    required TmxService tmxService,
    required ILoggingService logger,
  })  : _repository = repository,
        _tmxService = tmxService,
        _logger = logger;

  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      _logger.info('Starting TMX import process', {
        'filePath': filePath,
        'overwriteExisting': overwriteExisting,
      });

      // Import TMX entries using TmxService
      final importResult = await _tmxService.importFromTmx(
        filePath: filePath,
      );

      if (importResult.isErr) {
        return Err(importResult.error);
      }

      final entries = importResult.value;

      if (entries.isEmpty) {
        _logger.warning('No entries found in TMX file', {
          'filePath': filePath,
        });
        return Ok(0);
      }

      // Persist entries to database
      final persistResult = await _tmxService.persistTmxEntries(
        entries: entries,
        overwriteExisting: overwriteExisting,
        onProgress: onProgress,
      );

      if (persistResult.isErr) {
        return Err(persistResult.error);
      }

      final importedCount = persistResult.value;

      _logger.info('TMX import completed', {
        'filePath': filePath,
        'totalEntries': entries.length,
        'importedCount': importedCount,
      });

      return Ok(importedCount);
    } catch (e, stackTrace) {
      _logger.error('Unexpected error during TMX import', e, stackTrace);
      return Err(
        TmImportException(
          'Unexpected error during TMX import: ${e.toString()}',
          filePath: filePath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) async {
    try {
      _logger.info('Starting TMX export process', {
        'outputPath': outputPath,
        'sourceLanguageCode': sourceLanguageCode,
        'targetLanguageCode': targetLanguageCode,
      });

      // Push the target-language filter down to the query layer to avoid
      // loading the full TM into RAM.
      final String? dbTargetLanguageId = normalizeLanguageId(targetLanguageCode);

      // Resolve target language string for the TMX header/TUV xml:lang attribute.
      // If the caller did not specify a target language, peek at the first row
      // to discover the actual target language stored in the DB.
      String tgtLang;
      if (targetLanguageCode != null) {
        tgtLang = targetLanguageCode;
      } else {
        // Peek at one row to resolve the target language (option a per plan).
        final peekResult = await _repository.getPage(
          offset: 0,
          pageSize: 1,
          targetLanguageId: null,
        );
        if (peekResult.isErr) {
          return Err(TmExportException(
            'Failed to peek at DB for target language resolution: ${peekResult.error}',
            outputPath: outputPath,
            error: peekResult.error,
          ));
        }
        if (peekResult.value.isEmpty) {
          _logger.warning('No entries match export criteria', {
            'outputPath': outputPath,
          });
          // Produce a valid empty-body TMX so callers always get a well-formed file.
          final emptyResult = await _tmxService.exportToTmxStreaming(
            filePath: outputPath,
            pageFetcher: (_, __) async => const Ok([]),
            sourceLanguage: sourceLanguageCode ?? 'en',
            targetLanguage: 'unknown',
          );
          if (emptyResult.isErr) {
            return Err(TmExportException(
              'Failed to produce empty TMX: ${emptyResult.error}',
              outputPath: outputPath,
              error: emptyResult.error,
            ));
          }
          return Ok(0);
        }
        tgtLang = peekResult.value.first.targetLanguageId;
      }

      final srcLang = sourceLanguageCode ?? 'en';

      // Stream export page-by-page — never more than pageSize entries in RAM.
      // TODO: source-language filtering is not pushed down because the DB schema
      // does not index source_language_id for this query path; the existing
      // _applyExportFilters comment confirms source filtering is a no-op.
      final exportResult = await _tmxService.exportToTmxStreaming(
        filePath: outputPath,
        pageFetcher: (offset, pageSize) async {
          final result = await _repository.getPage(
            offset: offset,
            pageSize: pageSize,
            targetLanguageId: dbTargetLanguageId,
          );
          if (result.isErr) return Err(result.error);
          return Ok(result.value);
        },
        sourceLanguage: srcLang,
        targetLanguage: tgtLang,
      );

      if (exportResult.isErr) {
        return Err(TmExportException(
          'Failed to export TMX: ${exportResult.error}',
          outputPath: outputPath,
          error: exportResult.error.error,
          stackTrace: exportResult.error.stackTrace,
        ));
      }

      final totalWritten = exportResult.value;

      if (totalWritten == 0) {
        _logger.warning('No entries match export criteria', {
          'outputPath': outputPath,
        });
      } else {
        _logger.info('TMX export completed', {
          'outputPath': outputPath,
          'entriesExported': totalWritten,
        });
      }

      return Ok(totalWritten);
    } catch (e, stackTrace) {
      _logger.error('Unexpected error during TMX export', e, stackTrace);
      return Err(
        TmExportException(
          'Unexpected error during TMX export: ${e.toString()}',
          outputPath: outputPath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

}
