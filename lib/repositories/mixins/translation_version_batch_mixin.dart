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
}
