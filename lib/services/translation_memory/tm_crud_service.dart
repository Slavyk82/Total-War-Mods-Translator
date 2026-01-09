import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Translation Memory CRUD service
///
/// Handles:
/// - Adding single translations with deduplication
/// - Batch adding translations
/// - Incrementing usage counts
/// - Deleting entries
/// - Language ID resolution with caching
class TmCrudService {
  final TranslationMemoryRepository _repository;
  final LanguageRepository _languageRepository;
  final TextNormalizer _normalizer;
  final LoggingService _logger;

  // Cache for language code -> ID mapping
  final Map<String, String> _languageCodeToId = {};

  TmCrudService({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TextNormalizer normalizer,
    LoggingService? logger,
  })  : _repository = repository,
        _languageRepository = languageRepository,
        _normalizer = normalizer,
        _logger = logger ?? LoggingService.instance;

  /// Resolve language code to database ID
  /// Caches results for performance
  /// Note: Language codes are normalized to lowercase for consistent lookup
  Future<String?> resolveLanguageId(String languageCode) async {
    // Normalize to lowercase for consistent lookup
    // (TranslationContext uses uppercase for DeepL API, but DB stores lowercase)
    final normalizedCode = languageCode.toLowerCase();

    // Check cache first
    if (_languageCodeToId.containsKey(normalizedCode)) {
      return _languageCodeToId[normalizedCode];
    }

    // Look up from database
    final result = await _languageRepository.getByCode(normalizedCode);
    if (result.isOk) {
      final languageId = result.unwrap().id;
      _languageCodeToId[normalizedCode] = languageId;
      return languageId;
    }

    _logger.warning('Language not found for code', {'code': normalizedCode});
    return null;
  }

  /// Add a translation to Translation Memory
  ///
  /// Automatically deduplicates based on source hash.
  /// If entry exists, updates usage count and last_used timestamp.
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async {
    try {
      // Validate input
      if (sourceText.trim().isEmpty) {
        return Err(
          TmAddException('Source text cannot be empty', sourceText: sourceText),
        );
      }

      if (targetText.trim().isEmpty) {
        return Err(
          TmAddException('Target text cannot be empty', sourceText: sourceText),
        );
      }

      // Calculate source hash using SHA256 for collision resistance
      final normalized = _normalizer.normalize(sourceText);
      final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

      // Resolve language codes to database IDs
      final sourceLanguageId = await resolveLanguageId(sourceLanguageCode);
      final targetLanguageId = await resolveLanguageId(targetLanguageCode);

      if (sourceLanguageId == null || targetLanguageId == null) {
        return Err(
          TmAddException(
            'Could not resolve language IDs for codes: $sourceLanguageCode, $targetLanguageCode',
            sourceText: sourceText,
          ),
        );
      }

      // Check for existing entry (deduplication)
      final existingResult = await _repository.findBySourceHash(
        sourceHash,
        targetLanguageId,
      );

      if (existingResult.isOk) {
        return _updateExistingEntry(
          existingResult.value,
          sourceText,
          targetText,
          targetLanguageId,
          sourceHash,
        );
      } else {
        // Create new entry
        return _createNewEntry(
          sourceText,
          targetText,
          sourceLanguageId,
          targetLanguageId,
          sourceHash,
        );
      }
    } catch (e, stackTrace) {
      return Err(
        TmAddException(
          'Unexpected error adding translation: ${e.toString()}',
          sourceText: sourceText,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<TranslationMemoryEntry, TmAddException>> _updateExistingEntry(
    TranslationMemoryEntry existing,
    String sourceText,
    String targetText,
    String targetLanguageId,
    String sourceHash,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final updatedEntry = TranslationMemoryEntry(
      id: existing.id,
      sourceText: sourceText,
      translatedText: targetText,
      sourceLanguageId: existing.sourceLanguageId,
      targetLanguageId: targetLanguageId,
      sourceHash: sourceHash,
      usageCount: existing.usageCount + 1,
      createdAt: existing.createdAt,
      lastUsedAt: now,
      updatedAt: now,
    );

    final updateResult = await _repository.update(updatedEntry);

    if (updateResult.isErr) {
      return Err(
        TmAddException(
          'Failed to update existing entry: ${updateResult.error}',
          sourceText: sourceText,
        ),
      );
    }

    _logger.debug('Updated existing TM entry', {'entryId': existing.id});
    return Ok(updateResult.value);
  }

  Future<Result<TranslationMemoryEntry, TmAddException>> _createNewEntry(
    String sourceText,
    String targetText,
    String sourceLanguageId,
    String targetLanguageId,
    String sourceHash,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = TranslationMemoryEntry(
      id: const Uuid().v4(),
      sourceText: sourceText,
      translatedText: targetText,
      sourceLanguageId: sourceLanguageId,
      targetLanguageId: targetLanguageId,
      sourceHash: sourceHash,
      usageCount: 0,
      createdAt: now,
      lastUsedAt: now,
      updatedAt: now,
    );

    final result = await _repository.insert(entry);

    if (result.isErr) {
      return Err(
        TmAddException(
          'Failed to create entry: ${result.error}',
          sourceText: sourceText,
        ),
      );
    }

    return Ok(result.value);
  }

  /// Add multiple translations to Translation Memory in batch
  ///
  /// Efficiently inserts or updates multiple translations in a single transaction.
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async {
    if (translations.isEmpty) {
      return const Ok(0);
    }

    try {
      // Resolve language codes to database IDs
      final sourceLanguageId = await resolveLanguageId(sourceLanguageCode);
      final targetLanguageId = await resolveLanguageId(targetLanguageCode);

      if (sourceLanguageId == null || targetLanguageId == null) {
        return Err(
          TmAddException(
            'Could not resolve language IDs for codes: $sourceLanguageCode, $targetLanguageCode',
            sourceText: 'batch',
          ),
        );
      }

      // Build list of TM entries
      final entries = _buildBatchEntries(
        translations,
        sourceLanguageId,
        targetLanguageId,
      );

      if (entries.isEmpty) {
        return const Ok(0);
      }

      // Use batch upsert
      final result = await _repository.upsertBatch(entries);

      if (result.isErr) {
        return Err(
          TmAddException(
            'Failed to batch add translations: ${result.error}',
            sourceText: 'batch',
          ),
        );
      }

      _logger.debug(
        'Batch added TM entries',
        {'count': result.value, 'targetLanguage': targetLanguageCode},
      );

      return Ok(result.value);
    } catch (e, stackTrace) {
      return Err(
        TmAddException(
          'Unexpected error in batch add: ${e.toString()}',
          sourceText: 'batch',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  List<TranslationMemoryEntry> _buildBatchEntries(
    List<({String sourceText, String targetText})> translations,
    String sourceLanguageId,
    String targetLanguageId,
  ) {
    final entries = <TranslationMemoryEntry>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final t in translations) {
      // Skip empty translations
      if (t.sourceText.trim().isEmpty || t.targetText.trim().isEmpty) {
        continue;
      }

      // Calculate source hash using SHA256 for collision resistance
      final normalized = _normalizer.normalize(t.sourceText);
      final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

      entries.add(TranslationMemoryEntry(
        id: const Uuid().v4(),
        sourceText: t.sourceText,
        translatedText: t.targetText,
        sourceLanguageId: sourceLanguageId,
        targetLanguageId: targetLanguageId,
        sourceHash: sourceHash,
        usageCount: 0,
        createdAt: now,
        lastUsedAt: now,
        updatedAt: now,
      ));
    }

    return entries;
  }

  /// Update usage statistics for a TM entry
  ///
  /// Increments usage count and updates last_used timestamp.
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({required String entryId}) async {
    try {
      _logger.debug('incrementUsageCount called', {'entryId': entryId});

      // Get current entry
      final getResult = await _repository.getById(entryId);

      if (getResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get entry: ${getResult.error}',
            error: getResult.error,
          ),
        );
      }

      final entry = getResult.value;

      // Update entry with incremented usage count
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final updatedEntry = TranslationMemoryEntry(
        id: entry.id,
        sourceText: entry.sourceText,
        translatedText: entry.translatedText,
        sourceLanguageId: entry.sourceLanguageId,
        targetLanguageId: entry.targetLanguageId,
        sourceHash: entry.sourceHash,
        usageCount: entry.usageCount + 1,
        createdAt: entry.createdAt,
        lastUsedAt: now,
        updatedAt: now,
      );

      final updateResult = await _repository.update(updatedEntry);

      if (updateResult.isErr) {
        _logger.error('incrementUsageCount failed', {
          'entryId': entryId,
          'error': updateResult.error,
        });
        return Err(
          TmServiceException(
            'Failed to update usage count: ${updateResult.error}',
            error: updateResult.error,
          ),
        );
      }

      _logger.debug('incrementUsageCount success', {
        'entryId': entryId,
        'oldCount': entry.usageCount,
        'newCount': updatedEntry.usageCount,
      });
      return Ok(updateResult.value);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error incrementing usage count: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Delete a TM entry
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async {
    try {
      final deleteResult = await _repository.delete(entryId);

      if (deleteResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to delete entry: ${deleteResult.error}',
            error: deleteResult.error,
          ),
        );
      }

      return Ok(null);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error deleting entry: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Calculate SHA256 hash for source text
  ///
  /// Used by maintenance operations for consistency.
  String calculateSourceHash(String sourceText) {
    final normalized = _normalizer.normalize(sourceText);
    return sha256.convert(utf8.encode(normalized)).toString();
  }
}
