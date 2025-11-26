import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

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
  final LoggingService _logger;

  const TmImportExportService({
    required TranslationMemoryRepository repository,
    required TmxService tmxService,
    required LoggingService logger,
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
    double? minQuality,
  }) async {
    try {
      _logger.info('Starting TMX export process', {
        'outputPath': outputPath,
        'sourceLanguageCode': sourceLanguageCode,
        'targetLanguageCode': targetLanguageCode,
        'minQuality': minQuality,
      });

      // Get all entries from repository
      final entriesResult = await _repository.getAll();

      if (entriesResult.isErr) {
        return Err(
          TmExportException(
            'Failed to retrieve entries from database: ${entriesResult.error}',
            outputPath: outputPath,
            error: entriesResult.error,
          ),
        );
      }

      var entries = entriesResult.value;

      // Apply filters
      entries = _applyExportFilters(
        entries,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        minQuality: minQuality,
      );

      if (entries.isEmpty) {
        _logger.warning('No entries match export criteria', {
          'outputPath': outputPath,
        });
        return Ok(0);
      }

      // Determine target language
      // If not specified, use the most common one
      String tgtLang = targetLanguageCode ?? entries.first.targetLanguageId;
      // For TMX export, we use a placeholder source language since it's not stored
      String srcLang = sourceLanguageCode ?? 'en';

      // Export to TMX using TmxService
      final exportResult = await _tmxService.exportToTmx(
        filePath: outputPath,
        entries: entries,
        sourceLanguage: srcLang,
        targetLanguage: tgtLang,
      );

      if (exportResult.isErr) {
        return Err(TmExportException(
          'Failed to export TMX: ${exportResult.error}',
          outputPath: outputPath,
          entriesCount: entries.length,
          error: exportResult.error.error,
          stackTrace: exportResult.error.stackTrace,
        ));
      }

      _logger.info('TMX export completed', {
        'outputPath': outputPath,
        'entriesExported': entries.length,
      });

      return Ok(entries.length);
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

  List<TranslationMemoryEntry> _applyExportFilters(
    List<TranslationMemoryEntry> entries, {
    String? sourceLanguageCode,
    String? targetLanguageCode,
    double? minQuality,
  }) {
    var filtered = entries;

    // Note: sourceLanguageCode filter is no longer applicable as source language is not stored

    if (targetLanguageCode != null) {
      filtered = filtered
          .where((e) => e.targetLanguageId == targetLanguageCode)
          .toList();
    }

    if (minQuality != null) {
      filtered = filtered
          .where((e) =>
              e.qualityScore != null && e.qualityScore! >= minQuality)
          .toList();
    }

    return filtered;
  }
}
