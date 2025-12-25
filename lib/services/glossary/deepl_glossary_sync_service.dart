import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart';
import 'package:twmt/services/glossary/models/deepl_glossary_mapping.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:uuid/uuid.dart';

/// Service responsible for synchronizing TWMT glossaries with DeepL.
///
/// DeepL requires glossaries to be created on their servers before use.
/// This service handles:
/// - Creating DeepL glossaries from TWMT glossaries
/// - Tracking sync status in the database
/// - Detecting when resync is needed (glossary updated)
/// - Cleaning up old DeepL glossaries
class DeepLGlossarySyncService {
  final GlossaryRepository _glossaryRepository;
  final GlossaryDeepLService _deeplService;
  final LoggingService _logging;
  final Uuid _uuid = const Uuid();

  DeepLGlossarySyncService({
    required GlossaryRepository glossaryRepository,
    required GlossaryDeepLService deeplService,
    required LoggingService logging,
  })  : _glossaryRepository = glossaryRepository,
        _deeplService = deeplService,
        _logging = logging;

  /// Ensure a glossary is synced with DeepL for translation.
  ///
  /// This method:
  /// 1. Checks if a mapping already exists
  /// 2. If exists and up-to-date, returns the existing DeepL glossary ID
  /// 3. If exists but outdated, deletes the old one and creates new
  /// 4. If doesn't exist, creates a new DeepL glossary
  ///
  /// Returns the DeepL glossary ID to use in translations, or null if
  /// no glossary entries exist for this language pair.
  Future<Result<String?, GlossaryException>> ensureGlossarySynced({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    try {
      _logging.debug('[DeepLGlossarySyncService] Checking sync status', {
        'glossaryId': glossaryId,
        'sourceLanguage': sourceLanguageCode,
        'targetLanguage': targetLanguageCode,
      });

      // 1. Check if entries exist for this language pair
      final entryCount = await _glossaryRepository.getEntryCountForLanguage(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );

      if (entryCount == 0) {
        _logging.debug('[DeepLGlossarySyncService] No entries for language pair');
        return const Ok(null);
      }

      // 2. Check existing mapping
      final existingMapping = await _glossaryRepository.getDeepLMapping(
        twmtGlossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

      // 3. Check if resync is needed
      final needsResync = await _glossaryRepository.doesMappingNeedResync(
        twmtGlossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

      if (existingMapping != null && !needsResync) {
        _logging.debug('[DeepLGlossarySyncService] Using existing synced glossary', {
          'deeplGlossaryId': existingMapping.deeplGlossaryId,
        });
        return Ok(existingMapping.deeplGlossaryId);
      }

      // 4. Delete old DeepL glossary if exists
      if (existingMapping != null) {
        _logging.info('[DeepLGlossarySyncService] Deleting outdated DeepL glossary', {
          'deeplGlossaryId': existingMapping.deeplGlossaryId,
        });

        final deleteResult = await _deeplService.deleteDeepLGlossary(
          existingMapping.deeplGlossaryId,
        );

        // Continue even if delete fails (glossary might not exist on DeepL)
        if (deleteResult.isErr) {
          _logging.warning('[DeepLGlossarySyncService] Failed to delete old glossary', {
            'error': deleteResult.error.message,
          });
        }

        await _glossaryRepository.deleteDeepLMapping(existingMapping.id);
      }

      // 5. Create new DeepL glossary
      _logging.info('[DeepLGlossarySyncService] Creating new DeepL glossary', {
        'glossaryId': glossaryId,
        'entryCount': entryCount,
      });

      final createResult = await _deeplService.createDeepLGlossary(
        glossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

      if (createResult.isErr) {
        _logging.error('[DeepLGlossarySyncService] Failed to create DeepL glossary',
          createResult.error);
        return Err(createResult.error);
      }

      final deeplGlossaryId = createResult.value;

      // 6. Get glossary name for the mapping
      final glossary = await _glossaryRepository.getGlossaryById(glossaryId);
      final glossaryName = glossary?.name ?? 'Unknown';
      final deeplGlossaryName = '${glossaryName}_${sourceLanguageCode}_$targetLanguageCode';

      // 7. Store the mapping
      final now = DateTime.now().millisecondsSinceEpoch;
      final mapping = DeepLGlossaryMapping(
        id: _uuid.v4(),
        twmtGlossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        deeplGlossaryId: deeplGlossaryId,
        deeplGlossaryName: deeplGlossaryName,
        entryCount: entryCount,
        syncStatus: 'synced',
        syncedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await _glossaryRepository.insertDeepLMapping(mapping);

      _logging.info('[DeepLGlossarySyncService] Glossary synced successfully', {
        'deeplGlossaryId': deeplGlossaryId,
        'entryCount': entryCount,
      });

      return Ok(deeplGlossaryId);
    } catch (e, stackTrace) {
      _logging.error('[DeepLGlossarySyncService] Error syncing glossary', e, stackTrace);
      return Err(GlossarySyncException(
        'Failed to sync glossary with DeepL: $e',
        e,
      ));
    }
  }

  /// Sync multiple glossaries for a translation context.
  ///
  /// This is useful when a project uses multiple glossaries.
  /// Returns a map of glossaryId -> deeplGlossaryId for all synced glossaries.
  ///
  /// Note: DeepL only supports one glossary per translation request,
  /// so the caller should choose which one to use (e.g., most specific).
  Future<Result<Map<String, String>, GlossaryException>> syncGlossaries({
    required List<String> glossaryIds,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final results = <String, String>{};

    for (final glossaryId in glossaryIds) {
      final result = await ensureGlossarySynced(
        glossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

      if (result.isOk && result.value != null) {
        results[glossaryId] = result.value!;
      }
    }

    return Ok(results);
  }

  /// Delete all DeepL glossaries associated with a TWMT glossary.
  ///
  /// Call this when a TWMT glossary is deleted.
  Future<Result<void, GlossaryException>> deleteGlossaryMappings(
    String twmtGlossaryId,
  ) async {
    try {
      final mappings = await _glossaryRepository.getDeepLMappingsForGlossary(
        twmtGlossaryId,
      );

      for (final mapping in mappings) {
        // Delete from DeepL
        final deleteResult = await _deeplService.deleteDeepLGlossary(
          mapping.deeplGlossaryId,
        );

        if (deleteResult.isErr) {
          _logging.warning('[DeepLGlossarySyncService] Failed to delete DeepL glossary', {
            'deeplGlossaryId': mapping.deeplGlossaryId,
            'error': deleteResult.error.message,
          });
        }
      }

      // Delete all local mappings
      await _glossaryRepository.deleteDeepLMappingsForGlossary(twmtGlossaryId);

      return const Ok(null);
    } catch (e, stackTrace) {
      _logging.error('[DeepLGlossarySyncService] Error deleting glossary mappings', e, stackTrace);
      return Err(GlossarySyncException(
        'Failed to delete glossary mappings: $e',
        e,
      ));
    }
  }

  /// Get the DeepL glossary ID for a glossary if it's synced.
  ///
  /// Returns null if not synced.
  Future<String?> getDeepLGlossaryId({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final mapping = await _glossaryRepository.getDeepLMapping(
      twmtGlossaryId: glossaryId,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );
    return mapping?.deeplGlossaryId;
  }

  /// Check if a glossary is synced with DeepL.
  Future<bool> isGlossarySynced({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final mapping = await _glossaryRepository.getDeepLMapping(
      twmtGlossaryId: glossaryId,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );
    return mapping != null && mapping.isSynced;
  }

  /// Get all sync mappings for display.
  Future<List<DeepLGlossaryMapping>> getAllMappings() async {
    return _glossaryRepository.getAllDeepLMappings();
  }

  /// Force resync a specific glossary.
  ///
  /// Deletes the existing DeepL glossary and creates a new one.
  Future<Result<String?, GlossaryException>> forceResync({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    // Delete existing mapping first
    final existingMapping = await _glossaryRepository.getDeepLMapping(
      twmtGlossaryId: glossaryId,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );

    if (existingMapping != null) {
      await _deeplService.deleteDeepLGlossary(existingMapping.deeplGlossaryId);
      await _glossaryRepository.deleteDeepLMapping(existingMapping.id);
    }

    // Now sync as if it's new
    return ensureGlossarySynced(
      glossaryId: glossaryId,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );
  }
}
