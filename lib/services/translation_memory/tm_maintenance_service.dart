import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_crud_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Translation Memory maintenance service
///
/// Handles:
/// - Rebuilding TM from existing translations
/// - Migrating legacy hashes to SHA256 format
/// - Long-running maintenance operations with progress callbacks
class TmMaintenanceService {
  final TranslationMemoryRepository _repository;
  final TmCrudService _crudService;
  final TextNormalizer _normalizer;
  final LoggingService _logger;

  const TmMaintenanceService({
    required TranslationMemoryRepository repository,
    required TmCrudService crudService,
    required TextNormalizer normalizer,
    required LoggingService logger,
  })  : _repository = repository,
        _crudService = crudService,
        _normalizer = normalizer,
        _logger = logger;

  /// Rebuild Translation Memory from existing translations
  ///
  /// Scans all LLM translations in the database and adds any missing
  /// entries to the Translation Memory. Useful for recovering TM entries
  /// that were not properly saved during translation.
  ///
  /// [projectId]: Optional project ID to limit rebuild scope
  /// [onProgress]: Optional progress callback (processed, total, added)
  ///
  /// Returns tuple of (entries added, entries already existing)
  Future<Result<({int added, int existing}), TmServiceException>>
      rebuildFromTranslations({
    String? projectId,
    void Function(int processed, int total, int added)? onProgress,
  }) async {
    try {
      _logger.info('Starting TM rebuild from translations', {
        'projectId': projectId ?? 'all',
      });

      // Count total translations
      final countResult = await _repository.countLlmTranslations(
        projectId: projectId,
      );

      if (countResult.isErr) {
        return Err(TmServiceException(
          'Failed to count translations: ${countResult.error}',
          error: countResult.error,
        ));
      }

      final total = countResult.value;
      if (total == 0) {
        _logger.info('No LLM translations found to process');
        return const Ok((added: 0, existing: 0));
      }

      _logger.info('Found $total unique LLM translations to check');

      var addedCount = 0;
      var existingCount = 0;
      var processedCount = 0;
      const batchSize = 500;

      // Process in batches
      for (var offset = 0; offset < total; offset += batchSize) {
        final batchResult = await _repository.getMissingTmTranslations(
          projectId: projectId,
          limit: batchSize,
          offset: offset,
        );

        if (batchResult.isErr) {
          _logger.warning('Failed to get batch at offset $offset', {
            'error': batchResult.error,
          });
          continue;
        }

        final rows = batchResult.value;

        // Build entries for this batch
        final entriesToAdd = <({String sourceText, String targetText})>[];
        final targetLanguageMap = <String, String>{};

        for (final row in rows) {
          final sourceText = row['source_text'] as String;
          final targetText = row['translated_text'] as String;
          final targetLanguageId = row['target_language_id'] as String;

          // Skip empty
          if (sourceText.trim().isEmpty || targetText.trim().isEmpty) {
            continue;
          }

          // Calculate hash
          final sourceHash = _calculateSourceHash(sourceText);

          // Check if already exists
          final existingResult = await _repository.findByHash(
            sourceHash,
            targetLanguageId,
          );

          if (existingResult.isOk) {
            existingCount++;
          } else {
            entriesToAdd.add((sourceText: sourceText, targetText: targetText));
            targetLanguageMap[sourceText] = targetLanguageId;
          }

          processedCount++;
        }

        // Add entries that don't exist
        if (entriesToAdd.isNotEmpty) {
          // Group by target language for batch insert
          final byLanguage =
              <String, List<({String sourceText, String targetText})>>{};
          for (final entry in entriesToAdd) {
            final langId = targetLanguageMap[entry.sourceText]!;
            // Convert language ID to code (lang_fr -> fr)
            final langCode =
                langId.startsWith('lang_') ? langId.substring(5) : langId;
            byLanguage.putIfAbsent(langCode, () => []).add(entry);
          }

          for (final entry in byLanguage.entries) {
            final result = await _crudService.addTranslationsBatch(
              translations: entry.value,
              targetLanguageCode: entry.key,
            );

            if (result.isOk) {
              addedCount += entry.value.length;
            } else {
              _logger.warning('Failed to add batch for ${entry.key}', {
                'error': result.error,
                'count': entry.value.length,
              });
            }
          }
        }

        // Report progress
        onProgress?.call(processedCount, total, addedCount);

        // Yield to UI
        await Future<void>.delayed(Duration.zero);
      }

      _logger.info('TM rebuild completed', {
        'added': addedCount,
        'existing': existingCount,
        'total': processedCount,
      });

      return Ok((added: addedCount, existing: existingCount));
    } catch (e, stackTrace) {
      return Err(TmServiceException(
        'Failed to rebuild TM: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Migrate legacy hashes to SHA256 format
  ///
  /// Older TM entries used integer hashes. This method converts them
  /// to SHA256 hashes for consistency with the current implementation.
  ///
  /// [onProgress]: Optional progress callback (processed, total)
  ///
  /// Returns number of entries migrated
  Future<Result<int, TmServiceException>> migrateLegacyHashes({
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      _logger.info('Starting legacy hash migration');

      // Count total entries to migrate
      final countResult = await _repository.countLegacyHashes();
      if (countResult.isErr) {
        return Err(TmServiceException(
          'Failed to count legacy hashes: ${countResult.error}',
          error: countResult.error,
        ));
      }

      final total = countResult.value;
      if (total == 0) {
        _logger.info('No legacy hashes to migrate');
        return const Ok(0);
      }

      _logger.info('Found $total entries with legacy hashes to migrate');

      var migratedCount = 0;
      var deletedDuplicates = 0;
      var processedCount = 0;
      const batchSize = 500;

      // Process in batches - use offset 0 always since we're modifying/deleting entries
      while (true) {
        final batchResult = await _repository.getEntriesWithLegacyHashes(
          limit: batchSize,
          offset: 0, // Always 0 since entries are being modified/deleted
        );

        if (batchResult.isErr) {
          _logger.warning('Failed to get batch', {
            'error': batchResult.error,
          });
          break;
        }

        final entries = batchResult.value;
        if (entries.isEmpty) break; // No more legacy entries

        for (final entry in entries) {
          // Calculate new SHA256 hash
          final newHash = _calculateSourceHash(entry.sourceText);

          // Check if an entry with this hash already exists (from rebuild)
          final existingResult = await _repository.findBySourceHash(
            newHash,
            entry.targetLanguageId,
          );

          if (existingResult.isOk) {
            // Duplicate exists - delete the legacy entry
            await _repository.delete(entry.id);
            deletedDuplicates++;
          } else {
            // No duplicate - update the hash
            final updateResult = await _repository.updateHash(entry.id, newHash);
            if (updateResult.isOk) {
              migratedCount++;
            }
          }

          processedCount++;
        }

        // Report progress
        onProgress?.call(processedCount, total);

        // Yield to UI
        await Future<void>.delayed(Duration.zero);
      }

      _logger.info('Legacy hash migration completed', {
        'migrated': migratedCount,
        'deletedDuplicates': deletedDuplicates,
        'total': processedCount,
      });

      return Ok(migratedCount + deletedDuplicates);
    } catch (e, stackTrace) {
      return Err(TmServiceException(
        'Failed to migrate legacy hashes: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Calculate SHA256 hash for source text
  String _calculateSourceHash(String sourceText) {
    final normalized = _normalizer.normalize(sourceText);
    return sha256.convert(utf8.encode(normalized)).toString();
  }
}
