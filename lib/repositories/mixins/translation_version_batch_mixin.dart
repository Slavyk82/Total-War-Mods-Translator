import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_version.dart';

/// Mixin providing batch operations for translation versions.
///
/// Extracts complex batch insert/upsert logic from the main repository
/// to maintain single responsibility and keep file sizes manageable.
mixin TranslationVersionBatchMixin {
  /// Database instance - must be provided by implementing class
  Database get database;

  /// Table name - must be provided by implementing class
  String get tableName;

  /// Convert entity to database map - must be provided by implementing class
  Map<String, dynamic> toMap(TranslationVersion entity);

  /// Execute a query with error handling - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeQuery<R>(
    Future<R> Function() query,
  );

  /// Execute a transaction - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeTransaction<R>(
    Future<R> Function(Transaction txn) action,
  );

  /// Insert multiple translation versions in a single transaction.
  ///
  /// More efficient than calling insert() multiple times.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> insertBatch(
      List<TranslationVersion> entities) async {
    if (entities.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      final batch = database.batch();

      for (final entity in entities) {
        final map = toMap(entity);
        batch.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      await batch.commit(noResult: true);
      return entities;
    });
  }

  /// Upsert (INSERT or UPDATE) multiple translation versions in a single transaction.
  ///
  /// For each entity:
  /// - If translation exists for (unitId, projectLanguageId), UPDATE it
  /// - If not, INSERT new translation
  ///
  /// This is significantly faster than individual operations as it uses:
  /// - Single transaction for atomicity (prevents corruption under concurrent access)
  /// - Batch query for existence checks
  /// - Single batch commit
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> upsertBatch(
      List<TranslationVersion> entities) async {
    if (entities.isEmpty) {
      return Ok([]);
    }

    return executeTransaction((txn) async {
      // Step 1: Check which translations already exist (batch query within transaction)
      final unitIds = entities.map((e) => e.unitId).toSet().toList();
      final projectLanguageIds =
          entities.map((e) => e.projectLanguageId).toSet().toList();

      // Build placeholders for IN clause
      final unitPlaceholders = List.filled(unitIds.length, '?').join(',');
      final langPlaceholders =
          List.filled(projectLanguageIds.length, '?').join(',');

      final existingMaps = await txn.rawQuery('''
        SELECT id, unit_id, project_language_id, created_at
        FROM $tableName
        WHERE unit_id IN ($unitPlaceholders)
          AND project_language_id IN ($langPlaceholders)
      ''', [...unitIds, ...projectLanguageIds]);

      // Build lookup map: (unitId, projectLanguageId) -> (id, createdAt)
      final existingLookup = <String, ({String id, int createdAt})>{};
      for (final map in existingMaps) {
        final key = '${map['unit_id']}:${map['project_language_id']}';
        existingLookup[key] = (
          id: map['id'] as String,
          createdAt: map['created_at'] as int,
        );
      }

      // Step 2: Build batch operations within transaction
      final batch = txn.batch();

      for (final entity in entities) {
        final lookupKey = '${entity.unitId}:${entity.projectLanguageId}';
        final existing = existingLookup[lookupKey];

        if (existing != null) {
          // UPDATE: Preserve original ID and createdAt
          final map = toMap(entity);
          map['id'] = existing.id; // Keep original ID
          map['created_at'] = existing.createdAt; // Keep original createdAt
          map.remove('id'); // Remove from UPDATE fields

          batch.update(
            tableName,
            map,
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        } else {
          // INSERT: Use entity's ID and timestamps
          final map = toMap(entity);
          batch.insert(
            tableName,
            map,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      // Step 3: Commit batch (within transaction for atomicity)
      await batch.commit(noResult: true);

      return entities;
    });
  }

  /// Insert a translation version within an existing transaction.
  ///
  /// This method is used for batch operations where multiple inserts
  /// need to happen within a single transaction to prevent FTS5 corruption.
  Future<void> insertWithTransaction(
      Transaction txn, TranslationVersion entity) async {
    final map = toMap(entity);
    await txn.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Upsert (INSERT or UPDATE) a translation version within an existing transaction.
  ///
  /// If translation exists for (unitId, projectLanguageId), UPDATE it.
  /// If not, INSERT new translation.
  ///
  /// This method is used for batch operations where multiple upserts
  /// need to happen within a single transaction to prevent FTS5 corruption.
  Future<void> upsertWithTransaction(
      Transaction txn, TranslationVersion entity) async {
    // Check if translation exists
    final existingMaps = await txn.query(
      tableName,
      where: 'unit_id = ? AND project_language_id = ?',
      whereArgs: [entity.unitId, entity.projectLanguageId],
      columns: ['id', 'created_at'],
      limit: 1,
    );

    if (existingMaps.isNotEmpty) {
      // UPDATE: Preserve original ID and createdAt
      final existing = existingMaps.first;
      final existingId = existing['id'] as String;
      final existingCreatedAt = existing['created_at'] as int;

      final map = toMap(entity);
      map['created_at'] = existingCreatedAt;
      map.remove('id'); // Remove ID from UPDATE fields

      await txn.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [existingId],
      );
    } else {
      // INSERT: Use entity's ID and timestamps
      final map = toMap(entity);
      await txn.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  /// Upsert translation versions with trigger-disable optimization for large batches.
  ///
  /// Designed for the TM apply flow where thousands of matches must be
  /// persisted quickly. All entities must share the same [projectLanguageId]
  /// (the FTS / cache / progress rebuild is scoped to that language).
  ///
  /// Returns counts of inserted vs updated rows plus [effectiveVersionIds]
  /// aligned by index with [entities]: each entry is the entity's own id when
  /// the row was inserted, or the pre-existing row's id when it was updated.
  /// Callers that need to reference the persisted row (e.g. for history)
  /// should use these ids, not the ids on the input entities.
  Future<Result<({int inserted, int updated, List<String> effectiveVersionIds}),
      TWMTDatabaseException>> upsertBatchOptimized({
    required List<TranslationVersion> entities,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    if (entities.isEmpty) {
      return Ok((inserted: 0, updated: 0, effectiveVersionIds: <String>[]));
    }
    // Precondition: one projectLanguageId per call (scoped rebuild).
    final projectLanguageId = entities.first.projectLanguageId;
    assert(
      entities.every((e) => e.projectLanguageId == projectLanguageId),
      'upsertBatchOptimized requires all entities to share the same projectLanguageId',
    );
    return executeTransaction((txn) async {
      final total = entities.length;
      onProgress?.call(0, total, 'Preparing bulk apply...');

      // Step 1: Batch existence query to distinguish INSERT vs UPDATE.
      final unitIds = entities.map((e) => e.unitId).toSet().toList();
      // Chunk the IN (...) list to stay clear of SQLite's default parameter cap.
      const lookupChunkSize = 500;
      final existingLookup = <String, ({String id, int createdAt})>{};
      for (var i = 0; i < unitIds.length; i += lookupChunkSize) {
        final chunk = unitIds.skip(i).take(lookupChunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(',');
        final maps = await txn.rawQuery('''
          SELECT id, unit_id, created_at
          FROM $tableName
          WHERE unit_id IN ($placeholders)
            AND project_language_id = ?
        ''', [...chunk, projectLanguageId]);
        for (final row in maps) {
          existingLookup[row['unit_id'] as String] = (
            id: row['id'] as String,
            createdAt: row['created_at'] as int,
          );
        }
      }

      final disableTriggers = entities.length > 50;
      if (disableTriggers) {
        onProgress?.call(0, total, 'Optimizing for bulk write...');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');
        await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_insert');
        await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
      }

      int inserted = 0;
      int updated = 0;
      final effectiveIds = <String>[];

      try {
        // Step 2: Batched writes, sharing the outer transaction.
        const writeChunkSize = 500;
        for (var i = 0; i < entities.length; i += writeChunkSize) {
          final chunkEnd = (i + writeChunkSize).clamp(0, entities.length);
          final chunk = entities.sublist(i, chunkEnd);
          onProgress?.call(i, total, 'Saving translations...');

          final batch = txn.batch();
          for (final entity in chunk) {
            final existing = existingLookup[entity.unitId];
            if (existing != null) {
              // UPDATE: preserve existing id and created_at.
              final map = toMap(entity);
              map['created_at'] = existing.createdAt;
              map.remove('id');
              batch.update(
                tableName,
                map,
                where: 'id = ?',
                whereArgs: [existing.id],
              );
              effectiveIds.add(existing.id);
              updated++;
            } else {
              final map = toMap(entity);
              batch.insert(
                tableName,
                map,
                conflictAlgorithm: ConflictAlgorithm.abort,
              );
              effectiveIds.add(entity.id);
              inserted++;
            }
          }
          await batch.commit(noResult: true);
        }

        if (disableTriggers) {
          // Step 3: Rebuild FTS / cache / progress in set-based SQL.
          final now = DateTime.now().millisecondsSinceEpoch;
          onProgress?.call(total, total, 'Rebuilding search index...');

          const rebuildChunkSize = 500;
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawDelete('''
              DELETE FROM translation_versions_fts
              WHERE version_id IN (
                SELECT id FROM translation_versions
                WHERE unit_id IN ($placeholders) AND project_language_id = ?
              )
            ''', [...chunk, projectLanguageId]);
          }
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawInsert('''
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT tv.translated_text, tv.validation_issues, tv.id
              FROM translation_versions tv
              WHERE tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
                AND tv.translated_text IS NOT NULL
                AND tv.translated_text != ''
            ''', [...chunk, projectLanguageId]);
          }

          onProgress?.call(total, total, 'Updating cache...');
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawUpdate('''
              UPDATE translation_view_cache
              SET translated_text = tv.translated_text,
                  status = tv.status,
                  is_manually_edited = tv.is_manually_edited,
                  version_id = tv.id,
                  version_updated_at = tv.updated_at
              FROM translation_versions tv
              WHERE translation_view_cache.unit_id = tv.unit_id
                AND translation_view_cache.project_language_id = tv.project_language_id
                AND tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
            ''', [...chunk, projectLanguageId]);
          }

          onProgress?.call(total, total, 'Updating project progress...');
          await txn.rawUpdate('''
            UPDATE project_languages
            SET progress_percent = (
              SELECT
                CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                NULLIF(COUNT(*), 0)
              FROM translation_versions tv
              INNER JOIN translation_units tu ON tv.unit_id = tu.id
              WHERE tv.project_language_id = project_languages.id
                AND tu.is_obsolete = 0
            ),
            updated_at = ?
            WHERE id = ?
          ''', [now, projectLanguageId]);
        }
      } finally {
        if (disableTriggers) {
          await txn.execute('''
            CREATE TRIGGER trg_update_project_language_progress
            AFTER UPDATE ON translation_versions
            WHEN NEW.status != OLD.status
            BEGIN
              UPDATE project_languages
              SET progress_percent = (
                SELECT
                  CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                  NULLIF(COUNT(*), 0)
                FROM translation_versions tv
                INNER JOIN translation_units tu ON tv.unit_id = tu.id
                WHERE tv.project_language_id = NEW.project_language_id
                  AND tu.is_obsolete = 0
              ),
              updated_at = strftime('%s', 'now')
              WHERE id = NEW.project_language_id;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_translation_versions_fts_insert
            AFTER INSERT ON translation_versions
            WHEN new.translated_text IS NOT NULL
            BEGIN
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              VALUES (new.translated_text, new.validation_issues, new.id);
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_translation_versions_fts_update
            AFTER UPDATE OF translated_text, validation_issues ON translation_versions
            BEGIN
              DELETE FROM translation_versions_fts WHERE version_id = old.id;
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT new.translated_text, new.validation_issues, new.id
              WHERE new.translated_text IS NOT NULL;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_update_cache_on_version_change
            AFTER UPDATE ON translation_versions
            BEGIN
              UPDATE translation_view_cache
              SET translated_text = new.translated_text,
                  status = new.status,
                  confidence_score = NULL,
                  is_manually_edited = new.is_manually_edited,
                  version_id = new.id,
                  version_updated_at = new.updated_at
              WHERE unit_id = new.unit_id
                AND project_language_id = new.project_language_id;
            END
          ''');
        }
      }

      return (inserted: inserted, updated: updated, effectiveVersionIds: effectiveIds);
    });
  }

  /// Import multiple translation versions with optimized batch operations.

  ///
  /// This method is optimized for importing large numbers of translations:
  /// - Disables triggers for batches > 50 to avoid per-row overhead
  /// - Uses batch operations for database writes
  /// - Manually updates FTS index and cache at the end
  /// - Supports progress reporting and cancellation
  ///
  /// [entities] - List of TranslationVersion entities to import
  /// [existingVersionIds] - Map of unitId to existing version ID (for updates)
  /// [onProgress] - Optional callback for progress updates (current, total, message)
  /// [isCancelled] - Optional function to check if import should be cancelled
  ///
  /// Returns a record with counts of inserted, updated, and skipped entries.
  Future<Result<({int inserted, int updated, int skipped}), TWMTDatabaseException>>
      importBatch({
    required List<TranslationVersion> entities,
    required Map<String, String> existingVersionIds,
    void Function(int current, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (entities.isEmpty) {
      return Ok((inserted: 0, updated: 0, skipped: 0));
    }

    return executeTransaction((txn) async {
      final total = entities.length;
      int inserted = 0;
      int updated = 0;
      int skipped = 0;

      // For batches > 50, temporarily disable expensive triggers
      final disableTriggers = entities.length > 50;

      if (disableTriggers) {
        onProgress?.call(0, total, 'Preparing batch operation...');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');
        await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_insert');
        await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
      }

      try {
        // Process in batches
        const batchSize = 500;
        final now = DateTime.now().millisecondsSinceEpoch;

        for (var i = 0; i < entities.length; i += batchSize) {
          // Check for cancellation at batch boundaries
          if (isCancelled?.call() == true) {
            // Return partial results
            return (inserted: inserted, updated: updated, skipped: entities.length - i + skipped);
          }

          final batchEnd = (i + batchSize).clamp(0, entities.length);
          final batchEntities = entities.sublist(i, batchEnd);

          onProgress?.call(i, total, 'Processing batch ${(i ~/ batchSize) + 1}...');

          final batch = txn.batch();

          for (final entity in batchEntities) {
            final existingId = existingVersionIds[entity.unitId];

            if (existingId != null) {
              // UPDATE existing version
              final map = toMap(entity);
              map.remove('id');
              map['updated_at'] = now;

              batch.update(
                tableName,
                map,
                where: 'id = ?',
                whereArgs: [existingId],
              );
              updated++;
            } else {
              // INSERT new version
              final map = toMap(entity);
              batch.insert(
                tableName,
                map,
                conflictAlgorithm: ConflictAlgorithm.abort,
              );
              inserted++;
            }
          }

          await batch.commit(noResult: true);
          onProgress?.call(batchEnd, total, 'Processed $batchEnd / $total entries');
        }

        if (disableTriggers) {
          // Get unit IDs and project language ID for bulk operations
          final unitIds = entities.map((e) => e.unitId).toList();
          final projectLanguageId = entities.first.projectLanguageId;

          // Manually update FTS index using bulk SQL operations
          onProgress?.call(total, total, 'Updating search index...');

          // Delete existing FTS entries for all affected versions in one query per batch
          for (var i = 0; i < unitIds.length; i += batchSize) {
            final batch = unitIds.skip(i).take(batchSize).toList();
            final placeholders = List.filled(batch.length, '?').join(',');
            await txn.rawDelete(
              '''
              DELETE FROM translation_versions_fts
              WHERE version_id IN (
                SELECT id FROM translation_versions
                WHERE unit_id IN ($placeholders) AND project_language_id = ?
              )
              ''',
              [...batch, projectLanguageId],
            );
          }

          // Insert FTS entries using INSERT...SELECT (one query per batch)
          for (var i = 0; i < unitIds.length; i += batchSize) {
            final batch = unitIds.skip(i).take(batchSize).toList();
            final placeholders = List.filled(batch.length, '?').join(',');
            await txn.rawInsert(
              '''
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT tv.translated_text, tv.validation_issues, tv.id
              FROM translation_versions tv
              WHERE tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
                AND tv.translated_text IS NOT NULL
                AND tv.translated_text != ''
              ''',
              [...batch, projectLanguageId],
            );
          }

          // Manually update cache using UPDATE...FROM (SQLite 3.33+, one query per batch)
          onProgress?.call(total, total, 'Updating cache...');
          for (var i = 0; i < unitIds.length; i += batchSize) {
            final batch = unitIds.skip(i).take(batchSize).toList();
            final placeholders = List.filled(batch.length, '?').join(',');
            await txn.rawUpdate(
              '''
              UPDATE translation_view_cache
              SET translated_text = tv.translated_text,
                  status = tv.status,
                  is_manually_edited = tv.is_manually_edited,
                  version_id = tv.id,
                  version_updated_at = tv.updated_at
              FROM translation_versions tv
              WHERE translation_view_cache.unit_id = tv.unit_id
                AND translation_view_cache.project_language_id = tv.project_language_id
                AND tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
              ''',
              [...batch, projectLanguageId],
            );
          }

          // Manually update project language progress once
          onProgress?.call(total, total, 'Updating statistics...');
          await txn.rawUpdate('''
            UPDATE project_languages
            SET progress_percent = (
              SELECT
                CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                NULLIF(COUNT(*), 0)
              FROM translation_versions tv
              INNER JOIN translation_units tu ON tv.unit_id = tu.id
              WHERE tv.project_language_id = project_languages.id
                AND tu.is_obsolete = 0
            ),
            updated_at = ?
          ''', [now]);
        }
      } finally {
        if (disableTriggers) {
          // Recreate all triggers
          await txn.execute('''
            CREATE TRIGGER trg_update_project_language_progress
            AFTER UPDATE ON translation_versions
            WHEN NEW.status != OLD.status
            BEGIN
              UPDATE project_languages
              SET progress_percent = (
                SELECT
                  CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                  NULLIF(COUNT(*), 0)
                FROM translation_versions tv
                INNER JOIN translation_units tu ON tv.unit_id = tu.id
                WHERE tv.project_language_id = NEW.project_language_id
                  AND tu.is_obsolete = 0
              ),
              updated_at = strftime('%s', 'now')
              WHERE id = NEW.project_language_id;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_translation_versions_fts_insert
            AFTER INSERT ON translation_versions
            WHEN new.translated_text IS NOT NULL
            BEGIN
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              VALUES (new.translated_text, new.validation_issues, new.id);
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_translation_versions_fts_update
            AFTER UPDATE OF translated_text, validation_issues ON translation_versions
            BEGIN
              DELETE FROM translation_versions_fts WHERE version_id = old.id;
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT new.translated_text, new.validation_issues, new.id
              WHERE new.translated_text IS NOT NULL;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_update_cache_on_version_change
            AFTER UPDATE ON translation_versions
            BEGIN
              UPDATE translation_view_cache
              SET translated_text = new.translated_text,
                  status = new.status,
                  confidence_score = NULL,
                  is_manually_edited = new.is_manually_edited,
                  version_id = new.id,
                  version_updated_at = new.updated_at
              WHERE unit_id = new.unit_id
                AND project_language_id = new.project_language_id;
            END
          ''');
        }
      }

      return (inserted: inserted, updated: updated, skipped: skipped);
    });
  }
}
