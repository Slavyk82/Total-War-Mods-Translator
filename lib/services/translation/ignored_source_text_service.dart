import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/repositories/ignored_source_text_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for managing ignored source texts during translation.
///
/// Provides CRUD operations for user-configurable source texts that should be
/// skipped during translation. Maintains an in-memory cache for high-performance
/// lookups since the skip filter is called frequently.
class IgnoredSourceTextService {
  final IgnoredSourceTextRepository _repository;
  final LoggingService _logging;
  final Uuid _uuid = const Uuid();

  /// In-memory cache of enabled skip texts (lowercase, trimmed).
  /// Null means cache needs to be loaded.
  Set<String>? _cachedSkipTexts;

  /// Cached SQL condition for statistics queries.
  String? _cachedSqlCondition;

  IgnoredSourceTextService({
    required IgnoredSourceTextRepository repository,
    LoggingService? logging,
  })  : _repository = repository,
        _logging = logging ?? LoggingService.instance;

  // ============================================================================
  // Cache Management
  // ============================================================================

  /// Ensure the cache is loaded.
  ///
  /// Call this during app initialization to pre-load the cache.
  Future<void> ensureCacheLoaded() async {
    if (_cachedSkipTexts != null) return;
    await refreshCache();
  }

  /// Refresh the in-memory cache from the database.
  ///
  /// Call this after any CRUD operation that modifies the data.
  Future<void> refreshCache() async {
    final result = await _repository.getEnabledTexts();
    result.when(
      ok: (texts) {
        _cachedSkipTexts = texts
            .map((t) => t.sourceText.trim().toLowerCase())
            .toSet();
        _cachedSqlCondition = _buildSqlCondition(_cachedSkipTexts!);
        _logging.debug('Refreshed ignored source texts cache',
            {'count': _cachedSkipTexts!.length});
      },
      err: (error) {
        _logging.warning('Failed to load ignored source texts cache',
            {'error': error.message});
        _cachedSkipTexts = <String>{};
        _cachedSqlCondition = '';
      },
    );
  }


  // ============================================================================
  // Skip Filter Operations (High Performance)
  // ============================================================================

  /// Check if a source text should be skipped (case-insensitive).
  ///
  /// This is the main method used by TranslationSkipFilter.
  /// Returns true if the text matches any enabled ignored source text.
  ///
  /// Note: Returns false if cache is not loaded. Call [ensureCacheLoaded]
  /// during app initialization.
  bool shouldSkip(String text) {
    if (_cachedSkipTexts == null) {
      _logging.warning('Skip filter cache not loaded, returning false');
      return false;
    }
    return _cachedSkipTexts!.contains(text.trim().toLowerCase());
  }

  /// Get the SQL condition for excluding ignored texts in statistics queries.
  ///
  /// Returns a SQL snippet like:
  /// `LOWER(TRIM(tu.source_text)) IN ('placeholder', '[placeholder]', ...)`
  ///
  /// Returns empty string if no texts are configured.
  String getSqlCondition() {
    return _cachedSqlCondition ??= _buildSqlCondition(
      IgnoredSourceTextRepository.defaultTexts
          .map((t) => t.toLowerCase())
          .toSet(),
    );
  }

  /// Build SQL IN clause for the given texts.
  String _buildSqlCondition(Set<String> texts) {
    if (texts.isEmpty) return '';

    final escaped = texts
        .map((t) => "'${t.replaceAll("'", "''")}'")
        .join(', ');

    return 'LOWER(TRIM(tu.source_text)) IN ($escaped)';
  }

  // ============================================================================
  // CRUD Operations
  // ============================================================================

  /// Get all ignored source texts.
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>> getAll() async {
    return _repository.getAll();
  }

  /// Get all enabled ignored source texts.
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>>
      getEnabledTexts() async {
    return _repository.getEnabledTexts();
  }

  /// Get an ignored source text by ID.
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> getById(
      String id) async {
    return _repository.getById(id);
  }

  /// Add a new ignored source text.
  ///
  /// Returns error if text is empty or already exists (case-insensitive).
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> add(
      String sourceText) async {
    final trimmedText = sourceText.trim();
    if (trimmedText.isEmpty) {
      return Err(TWMTDatabaseException('Source text cannot be empty'));
    }

    // Check for duplicate (case-insensitive)
    final existsResult = await _repository.existsByText(trimmedText);
    final exists = existsResult.when(ok: (e) => e, err: (_) => false);
    if (exists) {
      return Err(TWMTDatabaseException(
          'Source text already exists (case-insensitive match)'));
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entity = IgnoredSourceText(
      id: _uuid.v4(),
      sourceText: trimmedText,
      isEnabled: true,
      createdAt: now,
      updatedAt: now,
    );

    _logging.debug('Adding ignored source text', {'text': trimmedText});

    final result = await _repository.insert(entity);
    result.when(
      ok: (_) => refreshCache(),
      err: (_) {},
    );

    return result;
  }

  /// Update an existing ignored source text.
  ///
  /// Returns error if text is empty or already exists (case-insensitive).
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> update(
    String id,
    String newSourceText,
  ) async {
    final trimmedText = newSourceText.trim();
    if (trimmedText.isEmpty) {
      return Err(TWMTDatabaseException('Source text cannot be empty'));
    }

    // Check for duplicate (case-insensitive), excluding current entity
    final existsResult =
        await _repository.existsByTextExcludingId(trimmedText, id);
    final exists = existsResult.when(ok: (e) => e, err: (_) => false);
    if (exists) {
      return Err(TWMTDatabaseException(
          'Source text already exists (case-insensitive match)'));
    }

    // Get existing entity
    final existingResult = await _repository.getById(id);
    return existingResult.when(
      ok: (existing) async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final updated = existing.copyWith(
          sourceText: trimmedText,
          updatedAt: now,
        );

        _logging.debug('Updating ignored source text',
            {'id': id, 'newText': trimmedText});

        final result = await _repository.update(updated);
        result.when(
          ok: (_) => refreshCache(),
          err: (_) {},
        );

        return result;
      },
      err: (error) => Err(error),
    );
  }

  /// Delete an ignored source text.
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    _logging.debug('Deleting ignored source text', {'id': id});

    final result = await _repository.delete(id);
    result.when(
      ok: (_) => refreshCache(),
      err: (_) {},
    );

    return result;
  }

  /// Toggle the enabled status of an ignored source text.
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> toggleEnabled(
      String id) async {
    _logging.debug('Toggling ignored source text enabled status', {'id': id});

    final result = await _repository.toggleEnabled(id);
    result.when(
      ok: (_) => refreshCache(),
      err: (_) {},
    );

    return result;
  }

  // ============================================================================
  // Reset to Defaults
  // ============================================================================

  /// Reset all ignored source texts to defaults.
  ///
  /// Deletes all existing entries and inserts the default values:
  /// - 'placeholder'
  /// - '[placeholder]'
  /// - '[unseen]'
  /// - '[do not localise]'
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>>
      resetToDefaults() async {
    _logging.info('Resetting ignored source texts to defaults');

    final result = await _repository.resetToDefaults();
    result.when(
      ok: (_) => refreshCache(),
      err: (_) {},
    );

    return result;
  }

  // ============================================================================
  // Statistics
  // ============================================================================

  /// Get the count of enabled ignored source texts.
  Future<int> getEnabledCount() async {
    final result = await _repository.getEnabledCount();
    return result.when(
      ok: (count) => count,
      err: (_) => 0,
    );
  }

  /// Get the total count of all ignored source texts.
  Future<int> getTotalCount() async {
    final result = await _repository.getTotalCount();
    return result.when(
      ok: (count) => count,
      err: (_) => 0,
    );
  }
}
