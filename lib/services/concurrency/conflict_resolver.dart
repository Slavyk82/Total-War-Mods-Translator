import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/conflict_resolution.dart';
import 'models/concurrency_exceptions.dart';
import 'utils/levenshtein.dart';

/// Service for detecting and resolving translation conflicts
///
/// Handles conflicts arising from:
/// - Concurrent manual edits by different users
/// - Manual editing during batch translation
/// - Version mismatches
/// - Lock timeouts
///
/// Uses similarity analysis to determine if conflicts can be auto-resolved.
class ConflictResolver {
  // ignore: unused_field
  final DatabaseService _databaseService;
  final Uuid _uuid;

  /// Default similarity threshold for auto-merge (95%)
  static const double defaultAutoMergeThreshold = 0.95;

  /// Default similarity threshold for manual review (80%)
  static const double defaultManualReviewThreshold = 0.80;

  ConflictResolver({
    DatabaseService? databaseService,
    Uuid? uuid,
  })  : _databaseService = databaseService ?? DatabaseService.instance,
        _uuid = uuid ?? const Uuid();

  Database get _db => DatabaseService.database;

  /// Detect conflict between two versions of a translation
  ///
  /// Parameters:
  /// - [translationUnitId]: Translation unit ID
  /// - [languageCode]: Language code
  /// - [currentValue]: Current value in database
  /// - [currentVersion]: Current version number
  /// - [currentSource]: Source of current value
  /// - [currentTimestamp]: Timestamp of current value
  /// - [incomingValue]: Incoming value trying to be saved
  /// - [incomingVersion]: Incoming version number
  /// - [incomingSource]: Source of incoming value
  /// - [incomingTimestamp]: Timestamp of incoming value
  /// - [conflictType]: Type of conflict
  ///
  /// Returns:
  /// - [Ok]: ConflictInfo with similarity analysis
  /// - [Err]: Exception if detection failed
  ///
  /// Example:
  /// ```dart
  /// final result = await resolver.detectConflict(
  ///   translationUnitId: 'unit_123',
  ///   languageCode: 'fr',
  ///   currentValue: 'User edited text',
  ///   currentVersion: 2,
  ///   currentSource: 'user',
  ///   currentTimestamp: DateTime.now(),
  ///   incomingValue: 'LLM edited text',
  ///   incomingVersion: 2,
  ///   incomingSource: 'llm',
  ///   incomingTimestamp: DateTime.now(),
  ///   conflictType: ConflictType.manualVsLlm,
  /// );
  ///
  /// if (result is Ok) {
  ///   final conflict = result.value;
  ///   if (conflict.canAutoResolve) {
  ///     // Apply automatic resolution
  ///   } else {
  ///     // Require manual intervention
  ///   }
  /// }
  /// ```
  Future<Result<ConflictInfo, ConcurrencyException>> detectConflict({
    required String translationUnitId,
    required String languageCode,
    required String currentValue,
    required int currentVersion,
    required String currentSource,
    required DateTime currentTimestamp,
    required String incomingValue,
    required int incomingVersion,
    required String incomingSource,
    required DateTime incomingTimestamp,
    required ConflictType conflictType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Calculate similarity score
      final similarityScore = LevenshteinDistance.similarity(currentValue, incomingValue);

      // Determine if auto-resolve is possible
      final canAutoResolve = _canAutoResolve(
        similarityScore: similarityScore,
        conflictType: conflictType,
      );

      // Suggest resolution strategy
      final suggestedStrategy = _suggestStrategy(
        similarityScore: similarityScore,
        conflictType: conflictType,
        currentTimestamp: currentTimestamp,
        incomingTimestamp: incomingTimestamp,
      );

      final conflict = ConflictInfo(
        id: _uuid.v4(),
        translationUnitId: translationUnitId,
        languageCode: languageCode,
        conflictType: conflictType,
        currentValue: currentValue,
        currentVersion: currentVersion,
        currentSource: currentSource,
        currentTimestamp: currentTimestamp,
        incomingValue: incomingValue,
        incomingVersion: incomingVersion,
        incomingSource: incomingSource,
        incomingTimestamp: incomingTimestamp,
        similarityScore: similarityScore,
        canAutoResolve: canAutoResolve,
        suggestedStrategy: suggestedStrategy,
        metadata: metadata,
      );

      return Ok(conflict);
    } catch (e) {
      return Err(ConflictResolutionException(
        'Failed to detect conflict: ${e.toString()}',
        conflictId: 'unknown',
        reason: e.toString(),
      ));
    }
  }

  /// Resolve a conflict using a specified strategy
  ///
  /// Parameters:
  /// - [conflict]: ConflictInfo with version information
  /// - [strategy]: Resolution strategy to apply
  /// - [resolvedBy]: ID of user or system resolving the conflict
  /// - [config]: Configuration for resolution behavior
  ///
  /// Returns:
  /// - [Ok]: ConflictResolution with resolved text
  /// - [Err]: Exception if resolution failed
  ///
  /// Example:
  /// ```dart
  /// final result = await resolver.resolveConflict(
  ///   conflict: conflictInfo,
  ///   strategy: ResolutionStrategy.keepNewer,
  ///   resolvedBy: 'user_123',
  /// );
  /// ```
  Future<Result<ConflictResolution, ConcurrencyException>> resolveConflict({
    required ConflictInfo conflict,
    required ResolutionStrategy strategy,
    required String resolvedBy,
    ConflictResolutionConfig? config,
  }) async {
    try {
      final cfg = config ?? ConflictResolutionConfig();

      // Validate strategy is appropriate for conflict type
      if (!_isStrategyValid(conflict.conflictType, strategy)) {
        return Err(ConflictResolutionException(
          'Strategy $strategy is not valid for conflict type ${conflict.conflictType}',
          conflictId: conflict.id,
          reason: 'Invalid strategy for conflict type',
        ));
      }

      // Apply resolution strategy
      final resolvedText = _applyStrategy(
        conflict: conflict,
        strategy: strategy,
        config: cfg,
      );

      final newVersion = conflict.currentVersion > conflict.incomingVersion
          ? conflict.currentVersion + 1
          : conflict.incomingVersion + 1;

      final resolution = ConflictResolution(
        conflictId: conflict.id,
        strategy: strategy,
        resolvedValue: resolvedText,
        resolvedVersion: newVersion,
        resolvedSource: resolvedBy,
        resolvedAt: DateTime.now(),
        resolvedBy: resolvedBy,
        wasAutomatic: strategy == conflict.suggestedStrategy && conflict.canAutoResolve,
      );

      // Store resolution in database
      await _storeResolution(conflict, resolution);

      return Ok(resolution);
    } on ConcurrencyException catch (e) {
      return Err(e);
    } catch (e) {
      return Err(ConflictResolutionException(
        'Failed to resolve conflict: ${e.toString()}',
        conflictId: conflict.id,
        reason: e.toString(),
      ));
    }
  }

  /// Auto-resolve conflict if possible
  ///
  /// Attempts automatic resolution based on similarity thresholds.
  /// Only succeeds if conflict.canAutoResolve is true.
  ///
  /// Parameters:
  /// - [conflict]: ConflictInfo to resolve
  /// - [config]: Configuration for auto-resolution
  ///
  /// Returns:
  /// - [Ok]: ConflictResolution if auto-resolved
  /// - [Err]: Exception if auto-resolution not possible or failed
  Future<Result<ConflictResolution, ConcurrencyException>> autoResolve({
    required ConflictInfo conflict,
    ConflictResolutionConfig? config,
  }) async {
    if (!conflict.canAutoResolve) {
      return Err(ConflictResolutionException(
        'Conflict cannot be auto-resolved',
        conflictId: conflict.id,
        reason: 'Similarity below threshold or requires manual review',
      ));
    }

    final strategy = conflict.suggestedStrategy ?? ResolutionStrategy.manualResolve;
    return await resolveConflict(
      conflict: conflict,
      strategy: strategy,
      resolvedBy: 'system',
      config: config,
    );
  }

  /// Merge two values intelligently
  ///
  /// Attempts to combine changes from both values.
  /// Uses word-level diffing to identify non-conflicting changes.
  ///
  /// Parameters:
  /// - [currentValue]: Current value in database
  /// - [incomingValue]: Incoming value trying to be saved
  ///
  /// Returns:
  /// - [Ok]: Merged text
  /// - [Err]: Exception if merge failed
  Future<Result<String, ConcurrencyException>> mergeValues({
    required String currentValue,
    required String incomingValue,
  }) async {
    try {
      // If both values are identical, no conflict
      if (currentValue == incomingValue) {
        return Ok(currentValue);
      }

      // Word-level merge
      final currentWords = currentValue.split(RegExp(r'\s+'));
      final incomingWords = incomingValue.split(RegExp(r'\s+'));

      // If word count differs significantly, cannot auto-merge
      final maxWords = currentWords.length > incomingWords.length ? currentWords.length : incomingWords.length;
      final minWords = currentWords.length < incomingWords.length ? currentWords.length : incomingWords.length;

      if (maxWords - minWords > maxWords * 0.2) {
        return Err(ConflictResolutionException(
          'Cannot auto-merge: word count difference too large',
          conflictId: 'merge',
          reason: 'Significant structural changes in both versions',
        ));
      }

      // Calculate similarity
      final similarity = LevenshteinDistance.similarity(currentValue, incomingValue);

      // If very similar, use incoming value (prefer newer)
      if (similarity >= 0.90) {
        return Ok(incomingValue);
      }

      // Otherwise cannot merge
      return Err(ConflictResolutionException(
        'Cannot auto-merge: values too different',
        conflictId: 'merge',
        reason: 'Similarity too low for automatic merge',
      ));
    } catch (e) {
      return Err(ConflictResolutionException(
        'Merge failed: ${e.toString()}',
        conflictId: 'merge',
        reason: e.toString(),
      ));
    }
  }

  /// Get conflict history for a translation version
  ///
  /// Parameters:
  /// - [translationVersionId]: Translation version ID
  /// - [limit]: Maximum number of conflicts to return
  ///
  /// Returns:
  /// - [Ok]: List of conflicts and their resolutions
  /// - [Err]: Exception if query failed
  Future<Result<List<Map<String, dynamic>>, ConcurrencyException>> getConflictHistory({
    required String translationVersionId,
    int limit = 50,
  }) async {
    try {
      final results = await _db.query(
        'conflict_resolutions',
        where: 'translation_version_id = ?',
        whereArgs: [translationVersionId],
        orderBy: 'detected_at DESC',
        limit: limit,
      );

      return Ok(results);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get conflict history: ${e.toString()}',
        code: 'CONFLICT_HISTORY_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting conflict history: ${e.toString()}',
        code: 'CONFLICT_HISTORY_ERROR',
      ));
    }
  }

  /// Get conflict statistics
  ///
  /// Returns counts by conflict type and resolution strategy.
  Future<Result<Map<String, dynamic>, ConcurrencyException>> getConflictStatistics() async {
    try {
      final byType = await _db.rawQuery('''
        SELECT conflict_type, COUNT(*) as count
        FROM conflict_resolutions
        GROUP BY conflict_type
      ''');

      final byStrategy = await _db.rawQuery('''
        SELECT resolution_strategy, COUNT(*) as count
        FROM conflict_resolutions
        GROUP BY resolution_strategy
      ''');

      final autoResolvedCount = await _db.rawQuery('''
        SELECT COUNT(*) as count
        FROM conflict_resolutions
        WHERE is_auto_resolved = 1
      ''');

      return Ok({
        'by_type': byType,
        'by_strategy': byStrategy,
        'auto_resolved': autoResolvedCount.first['count'],
      });
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get conflict statistics: ${e.toString()}',
        code: 'CONFLICT_STATS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting statistics: ${e.toString()}',
        code: 'CONFLICT_STATS_ERROR',
      ));
    }
  }

  /// Check for potential conflicts before updating
  ///
  /// Proactive conflict detection before committing changes.
  ///
  /// Parameters:
  /// - [translationVersionId]: Translation version ID
  /// - [currentVersion]: Current version number
  /// - [proposedText]: Text to update
  ///
  /// Returns:
  /// - [Ok]: null if no conflict, ConflictInfo if conflict detected
  /// - [Err]: Exception if check failed
  Future<Result<ConflictInfo?, ConcurrencyException>> checkForConflicts({
    required String translationVersionId,
    required int currentVersion,
    required String proposedText,
  }) async {
    try {
      // Get latest version from database
      final results = await _db.query(
        'translation_versions',
        columns: ['version', 'translated_text', 'updated_by', 'updated_at'],
        where: 'id = ?',
        whereArgs: [translationVersionId],
      );

      if (results.isEmpty) {
        return Err(ConcurrencyException(
          'Translation version not found',
          code: 'VERSION_NOT_FOUND',
        ));
      }

      final dbVersion = results.first['version'] as int;
      final dbText = results.first['translated_text'] as String?;

      // No conflict if versions match
      if (dbVersion == currentVersion) {
        return const Ok(null);
      }

      // Version mismatch - detect conflict
      if (dbText == null) {
        return const Ok(null);
      }

      final now = DateTime.now();
      final conflictResult = await detectConflict(
        translationUnitId: translationVersionId,
        languageCode: 'unknown', // Would need to be passed as parameter
        currentValue: dbText,
        currentVersion: dbVersion,
        currentSource: (results.first['updated_by'] as String?) ?? 'unknown',
        currentTimestamp: DateTime.fromMillisecondsSinceEpoch(
          (results.first['updated_at'] as int?) ?? now.millisecondsSinceEpoch,
        ),
        incomingValue: proposedText,
        incomingVersion: currentVersion,
        incomingSource: 'user',
        incomingTimestamp: now,
        conflictType: ConflictType.versionMismatch,
        metadata: {
          'translation_version_id': translationVersionId,
          'expected_version': currentVersion,
          'actual_version': dbVersion,
        },
      );

      if (conflictResult is Err) {
        return Err(conflictResult.error);
      }

      final conflict = (conflictResult as Ok<ConflictInfo, ConcurrencyException>).value;
      return Ok(conflict);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to check for conflicts: ${e.toString()}',
        code: 'CONFLICT_CHECK_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error checking conflicts: ${e.toString()}',
        code: 'CONFLICT_CHECK_ERROR',
      ));
    }
  }

  // Private helper methods

  bool _canAutoResolve({
    required double similarityScore,
    required ConflictType conflictType,
  }) {
    // Very high similarity - likely same intent
    if (similarityScore >= defaultAutoMergeThreshold) {
      return true;
    }

    // For LLM conflicts, lower threshold is acceptable
    if (conflictType == ConflictType.llmVsLlm &&
        similarityScore >= 0.90) {
      return true;
    }

    return false;
  }

  ResolutionStrategy _suggestStrategy({
    required double similarityScore,
    required ConflictType conflictType,
    required DateTime currentTimestamp,
    required DateTime incomingTimestamp,
  }) {
    // Very high similarity - always merge
    if (similarityScore >= defaultAutoMergeThreshold) {
      return ResolutionStrategy.merge;
    }

    // Use pattern matching for conflict type resolution
    return switch (conflictType) {
      ConflictType.manualVsLlm => ResolutionStrategy.keepUser,
      ConflictType.manualVsManual => ResolutionStrategy.manualResolve,
      ConflictType.llmVsLlm => ResolutionStrategy.keepNewer,
      ConflictType.versionMismatch || ConflictType.lockTimeout => ResolutionStrategy.manualResolve,
    };
  }

  bool _isStrategyValid(ConflictType type, ResolutionStrategy strategy) {
    // Manual resolve is always valid
    if (strategy == ResolutionStrategy.manualResolve) {
      return true;
    }

    // Check type-specific valid strategies using pattern matching
    return switch ((type, strategy)) {
      // manualVsLlm allows keepUser, keepLlm, or merge
      (ConflictType.manualVsLlm, ResolutionStrategy.keepUser) ||
      (ConflictType.manualVsLlm, ResolutionStrategy.keepLlm) ||
      (ConflictType.manualVsLlm, ResolutionStrategy.merge) => true,

      // manualVsManual allows keepNewer, keepOlder, or merge
      (ConflictType.manualVsManual, ResolutionStrategy.keepNewer) ||
      (ConflictType.manualVsManual, ResolutionStrategy.keepOlder) ||
      (ConflictType.manualVsManual, ResolutionStrategy.merge) => true,

      // llmVsLlm allows keepNewer, keepOlder, or merge
      (ConflictType.llmVsLlm, ResolutionStrategy.keepNewer) ||
      (ConflictType.llmVsLlm, ResolutionStrategy.keepOlder) ||
      (ConflictType.llmVsLlm, ResolutionStrategy.merge) => true,

      // versionMismatch allows keepCurrent, discard, or merge
      (ConflictType.versionMismatch, ResolutionStrategy.keepCurrent) ||
      (ConflictType.versionMismatch, ResolutionStrategy.discard) ||
      (ConflictType.versionMismatch, ResolutionStrategy.merge) => true,

      // lockTimeout allows keepCurrent or discard
      (ConflictType.lockTimeout, ResolutionStrategy.keepCurrent) ||
      (ConflictType.lockTimeout, ResolutionStrategy.discard) => true,

      // All other combinations are invalid
      _ => false,
    };
  }

  String _applyStrategy({
    required ConflictInfo conflict,
    required ResolutionStrategy strategy,
    required ConflictResolutionConfig config,
  }) {
    return switch (strategy) {
      ResolutionStrategy.keepUser =>
        // If incoming source is user, keep incoming, otherwise keep current if it's user
        conflict.incomingSource == 'user'
            ? conflict.incomingValue
            : conflict.currentValue,

      ResolutionStrategy.keepLlm =>
        // If incoming source is llm, keep incoming, otherwise keep current if it's llm
        conflict.incomingSource == 'llm' || conflict.incomingSource.startsWith('batch_')
            ? conflict.incomingValue
            : conflict.currentValue,

      ResolutionStrategy.keepNewer =>
        conflict.incomingIsNewer ? conflict.incomingValue : conflict.currentValue,

      ResolutionStrategy.keepOlder =>
        conflict.incomingIsNewer ? conflict.currentValue : conflict.incomingValue,

      ResolutionStrategy.merge =>
        // Simple merge: if very similar, use newer version
        conflict.similarityScore >= config.autoResolveSimilarityThreshold
            ? (conflict.incomingIsNewer ? conflict.incomingValue : conflict.currentValue)
            : conflict.incomingValue,

      ResolutionStrategy.manualResolve =>
        // Should not be called - manual resolution happens outside
        throw ConflictResolutionException(
          'Manual resolution requires user input',
          conflictId: conflict.id,
          reason: 'Cannot auto-apply manual resolution strategy',
        ),

      ResolutionStrategy.keepCurrent || ResolutionStrategy.discard =>
        conflict.currentValue,
    };
  }

  Future<void> _storeResolution(
    ConflictInfo conflict,
    ConflictResolution resolution,
  ) async {
    await _db.insert('conflict_resolutions', {
      'id': _uuid.v4(),
      'conflict_type': conflict.conflictType.name,
      'translation_unit_id': conflict.translationUnitId,
      'language_code': conflict.languageCode,
      'translation_version_id': conflict.metadata?['translation_version_id'],
      'current_value': conflict.currentValue,
      'current_version': conflict.currentVersion,
      'incoming_value': conflict.incomingValue,
      'incoming_version': conflict.incomingVersion,
      'resolved_value': resolution.resolvedValue,
      'resolved_version': resolution.resolvedVersion,
      'resolution_strategy': resolution.strategy.name,
      'similarity_score': conflict.similarityScore,
      'is_auto_resolved': resolution.wasAutomatic ? 1 : 0,
      'resolved_by': resolution.resolvedBy,
      'detected_at': conflict.currentTimestamp.millisecondsSinceEpoch,
      'resolved_at': resolution.resolvedAt.millisecondsSinceEpoch,
      'metadata': conflict.metadata?.toString(),
    });
  }
}
