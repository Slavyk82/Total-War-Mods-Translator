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

      // Lightweight projection: the upsert path only needs `id` and `usage_count`
      // keyed by (source_hash, target_language_id). Avoid SELECT * to stop pulling
      // source_text / translated_text (each 1-2 KB) into memory for nothing.
      final existing = <String, ({String id, int usageCount})>{};

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
          'SELECT id, source_hash, target_language_id, usage_count '
          'FROM $tableName WHERE $placeholders',
          args,
        );

        for (final map in maps) {
          final key = '${map['source_hash']}:${map['target_language_id']}';
          existing[key] = (
            id: map['id'] as String,
            usageCount: map['usage_count'] as int,
          );
        }
      }

      // Process each entry: update existing or insert new
      for (final entry in entries) {
        final key = '${entry.sourceHash}:${entry.targetLanguageId}';
        final match = existing[key];

        if (match != null) {
          // Update existing entry
          await txn.update(
            tableName,
            {
              'translated_text': entry.translatedText,
              'usage_count': match.usageCount + 1,
              'last_used_at': now,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [match.id],
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

  /// Bulk-insert TMX entries with TMX import semantics.
  ///
  /// Processes [entries] in chunks inside a single transaction per chunk.
  /// For each entry:
  /// - If no row exists for `(source_hash, target_language_id)`: INSERT new row.
  /// - If a row exists and [overwriteExisting] is true: UPDATE translated_text
  ///   and updated_at; usage_count/last_used_at are preserved.
  /// - If a row exists and [overwriteExisting] is false: skip.
  ///
  /// Returns the number of rows actually written (inserted + updated).
  /// Skipped rows are reported via [onProgress] only.
  ///
  /// This replaces the per-row `findByHash` + `insert` loop, collapsing up to
  /// 2N autocommit round-trips per chunk into one batched lookup and one
  /// batched write inside a single transaction.
  Future<Result<({int persisted, int skipped}), TWMTDatabaseException>>
      bulkImportTmxEntries(
    List<TranslationMemoryEntry> entries, {
    required bool overwriteExisting,
    void Function(int processed, int total)? onProgress,
  }) async {
    if (entries.isEmpty) {
      return const Ok((persisted: 0, skipped: 0));
    }

    const chunkSize = 500;
    var persisted = 0;
    var skipped = 0;

    for (var start = 0; start < entries.length; start += chunkSize) {
      final end = (start + chunkSize < entries.length)
          ? start + chunkSize
          : entries.length;
      final chunk = entries.sublist(start, end);

      final result = await executeTransaction((txn) async {
        // Batch lookup: which (source_hash, target_language_id) pairs already exist?
        final existingIds = <String, String>{}; // hash:lang -> existing row id
        const lookupChunk = 100;
        for (var i = 0; i < chunk.length; i += lookupChunk) {
          final j = (i + lookupChunk < chunk.length)
              ? i + lookupChunk
              : chunk.length;
          final sub = chunk.sublist(i, j);
          final placeholders = List.filled(
            sub.length,
            '(source_hash = ? AND target_language_id = ?)',
          ).join(' OR ');
          final args = <Object?>[];
          for (final e in sub) {
            args.add(e.sourceHash);
            args.add(e.targetLanguageId);
          }
          final rows = await txn.rawQuery(
            'SELECT id, source_hash, target_language_id FROM $tableName '
            'WHERE $placeholders',
            args,
          );
          for (final row in rows) {
            final key =
                '${row['source_hash']}:${row['target_language_id']}';
            existingIds[key] = row['id'] as String;
          }
        }

        var chunkWrites = 0;
        var chunkSkipped = 0;
        for (final entry in chunk) {
          final key = '${entry.sourceHash}:${entry.targetLanguageId}';
          final existingId = existingIds[key];

          if (existingId != null) {
            if (!overwriteExisting) {
              chunkSkipped++;
              continue;
            }
            await txn.update(
              tableName,
              {
                'translated_text': entry.translatedText,
                'updated_at': entry.updatedAt,
              },
              where: 'id = ?',
              whereArgs: [existingId],
            );
            chunkWrites++;
          } else {
            await txn.insert(
              tableName,
              toMap(entry),
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            chunkWrites++;
          }
        }

        return (persisted: chunkWrites, skipped: chunkSkipped);
      });

      if (result.isErr) {
        return Err(result.unwrapErr());
      }
      final counts = result.unwrap();
      persisted += counts.persisted;
      skipped += counts.skipped;

      onProgress?.call(end, entries.length);
    }

    // Reuse the same WAL checkpoint policy as upsertBatch.
    await DatabaseService.checkpointIfNeeded(thresholdBytes: 1048576);

    return Ok((persisted: persisted, skipped: skipped));
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
