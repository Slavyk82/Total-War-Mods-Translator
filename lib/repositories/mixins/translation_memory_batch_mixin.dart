import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_memory_entry.dart';
import '../../services/database/database_service.dart';

/// Mixin providing batch operations for translation memory.
///
/// Extracts complex batch insert/upsert logic from the main repository
/// to maintain single responsibility and keep file sizes manageable.
///
/// Includes:
/// - [upsertBatch]: Batch upsert of TM entries
/// - [getMissingTmTranslations]: Find LLM translations not in TM
/// - [countLlmTranslations]: Count LLM translations for progress tracking
mixin TranslationMemoryBatchMixin {
  /// Database instance - must be provided by implementing class
  Database get database;

  /// Table name - must be provided by implementing class
  String get tableName;

  /// Convert entity to database map - must be provided by implementing class
  Map<String, dynamic> toMap(TranslationMemoryEntry entity);

  /// Convert database map to entity - must be provided by implementing class
  TranslationMemoryEntry fromMap(Map<String, dynamic> map);

  /// Execute a query with error handling - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeQuery<R>(
    Future<R> Function() query,
  );

  /// Execute a transaction - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeTransaction<R>(
    Future<R> Function(Transaction txn) action,
  );

  /// Batch upsert translation memory entries.
  ///
  /// Efficiently inserts or updates multiple TM entries in a single transaction.
  /// Uses INSERT OR REPLACE with source_hash as conflict resolution key.
  ///
  /// For existing entries (same source_hash + target_language_id):
  /// - Updates translated_text, last_used_at, updated_at
  /// - Increments usage_count
  ///
  /// For new entries: Creates with provided values.
  ///
  /// [entries] - List of TM entries to upsert
  ///
  /// Returns [Ok] with number of entries processed, [Err] on failure.
  Future<Result<int, TWMTDatabaseException>> upsertBatch(
    List<TranslationMemoryEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return const Ok(0);
    }

    final result = await executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      var processedCount = 0;

      // Collect all source_hash + target_language_id pairs for batch lookup
      final hashPairs = entries
          .map((e) => '${e.sourceHash}:${e.targetLanguageId}')
          .toSet()
          .toList();

      // Build query to find existing entries by hash pairs
      final existingEntries = <String, TranslationMemoryEntry>{};

      // Query in chunks to avoid SQL parameter limits.
      // Each pair consumes 2 placeholders; SQLite's default SQLITE_MAX_VARIABLE_NUMBER
      // is 999, so 100 pairs = 200 placeholders is safely under the limit.
      const chunkSize = 100;
      for (var i = 0; i < hashPairs.length; i += chunkSize) {
        final chunk = hashPairs.skip(i).take(chunkSize).toList();

        // Build parameterised WHERE clause (one (?,?) group per pair)
        final placeholders =
            List.filled(chunk.length, '(source_hash = ? AND target_language_id = ?)')
                .join(' OR ');
        final args = <Object?>[];
        for (final pair in chunk) {
          final parts = pair.split(':');
          args.add(parts[0]);
          args.add(parts[1]);
        }

        final maps = await txn.rawQuery(
          'SELECT * FROM $tableName WHERE $placeholders',
          args,
        );

        for (final map in maps) {
          final entry = fromMap(map);
          final key = '${entry.sourceHash}:${entry.targetLanguageId}';
          existingEntries[key] = entry;
        }
      }

      // Process each entry: update existing or insert new
      for (final entry in entries) {
        final key = '${entry.sourceHash}:${entry.targetLanguageId}';
        final existing = existingEntries[key];

        if (existing != null) {
          // Update existing entry
          await txn.update(
            tableName,
            {
              'translated_text': entry.translatedText,
              'usage_count': existing.usageCount + 1,
              'last_used_at': now,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        } else {
          // Insert new entry
          final map = toMap(entry.copyWith(
            createdAt: now,
            lastUsedAt: now,
            updatedAt: now,
          ));
          await txn.insert(
            tableName,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        processedCount++;
      }

      return processedCount;
    });

    // Opportunistic WAL checkpoint to prevent unbounded WAL file growth
    // during long batch imports. 1 MB threshold keeps the WAL small without
    // checkpointing after every trivial batch.
    if (result.isOk) {
      await DatabaseService.checkpointIfNeeded(thresholdBytes: 1048576);
    }

    return result;
  }

  /// Get LLM translations that are missing from TM
  ///
  /// Returns translations that were done by LLM but not stored in TM.
  /// Used for rebuilding TM from existing translations.
  ///
  /// [projectId]: Optional project ID to limit scope
  /// [limit]: Batch size for processing
  /// [offset]: Pagination offset
  Future<Result<List<Map<String, dynamic>>, TWMTDatabaseException>>
      getMissingTmTranslations({
    String? projectId,
    int limit = 1000,
    int offset = 0,
  }) async {
    return executeQuery(() async {
      final projectFilter = projectId != null ? 'AND tu.project_id = ?' : '';
      final args = <Object?>[
        if (projectId != null) projectId,
        limit,
        offset,
      ];

      final query = '''
        SELECT DISTINCT
          tu.source_text,
          tv.translated_text,
          pl.language_id as target_language_id
        FROM translation_units tu
        INNER JOIN translation_versions tv ON tv.unit_id = tu.id
        INNER JOIN project_languages pl ON pl.id = tv.project_language_id
        WHERE tv.translation_source = 'llm'
          AND tv.translated_text IS NOT NULL
          AND tv.translated_text != ''
          $projectFilter
        ORDER BY tu.source_text
        LIMIT ? OFFSET ?
      ''';

      final rows = await database.rawQuery(query, args);
      return rows;
    });
  }

  /// Count total LLM translations (for progress tracking)
  Future<Result<int, TWMTDatabaseException>> countLlmTranslations({
    String? projectId,
  }) async {
    return executeQuery(() async {
      final projectFilter = projectId != null ? 'AND tu.project_id = ?' : '';
      final args = <Object?>[if (projectId != null) projectId];

      final query = '''
        SELECT COUNT(DISTINCT tu.source_text || '|' || pl.language_id) as count
        FROM translation_units tu
        INNER JOIN translation_versions tv ON tv.unit_id = tu.id
        INNER JOIN project_languages pl ON pl.id = tv.project_language_id
        WHERE tv.translation_source = 'llm'
          AND tv.translated_text IS NOT NULL
          AND tv.translated_text != ''
          $projectFilter
      ''';

      final result = await database.rawQuery(query, args);
      return (result.first['count'] as int?) ?? 0;
    });
  }
}
