import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_memory_entry.dart';

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

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      var processedCount = 0;

      // Collect all source_hash + target_language_id pairs for batch lookup
      final hashPairs = entries
          .map((e) => '${e.sourceHash}:${e.targetLanguageId}')
          .toSet()
          .toList();

      // Build query to find existing entries by hash pairs
      final existingEntries = <String, TranslationMemoryEntry>{};

      // Query in chunks to avoid SQL parameter limits
      const chunkSize = 100;
      for (var i = 0; i < hashPairs.length; i += chunkSize) {
        final chunk = hashPairs.skip(i).take(chunkSize).toList();

        // Build WHERE clause for this chunk
        final conditions = chunk.map((pair) {
          final parts = pair.split(':');
          return "(source_hash = '${parts[0].replaceAll("'", "''")}' AND target_language_id = '${parts[1].replaceAll("'", "''")}')";
        }).join(' OR ');

        final maps = await txn.rawQuery(
          'SELECT * FROM $tableName WHERE $conditions',
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
      final projectFilter =
          projectId != null ? "AND tu.project_id = '$projectId'" : '';

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
        LIMIT $limit OFFSET $offset
      ''';

      final rows = await database.rawQuery(query);
      return rows;
    });
  }

  /// Count total LLM translations (for progress tracking)
  Future<Result<int, TWMTDatabaseException>> countLlmTranslations({
    String? projectId,
  }) async {
    return executeQuery(() async {
      final projectFilter =
          projectId != null ? "AND tu.project_id = '$projectId'" : '';

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

      final result = await database.rawQuery(query);
      return (result.first['count'] as int?) ?? 0;
    });
  }
}
