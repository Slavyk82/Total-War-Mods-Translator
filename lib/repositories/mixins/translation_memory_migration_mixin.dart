import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_memory_entry.dart';

/// Mixin providing legacy hash migration operations for translation memory.
///
/// Extracts migration logic from the main repository to maintain
/// single responsibility and keep file sizes manageable.
///
/// Handles migration from legacy hash formats to SHA256:
/// - [getEntriesWithLegacyHashes]: Get entries needing migration
/// - [countLegacyHashes]: Count entries with legacy hashes
/// - [updateHash]: Update hash for a single entry
/// - [updateHashesBatch]: Batch update hashes
mixin TranslationMemoryMigrationMixin {
  /// Database instance - must be provided by implementing class
  Database get database;

  /// Table name - must be provided by implementing class
  String get tableName;

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

  /// Get all TM entries with legacy (non-SHA256) hashes
  ///
  /// Legacy hashes are shorter than 64 characters (SHA256 produces 64 hex chars).
  /// Used for migrating old entries to the new SHA256 hash format.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      getEntriesWithLegacyHashes({
    int limit = 1000,
    int offset = 0,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'length(source_hash) < 64',
        orderBy: 'id',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Count TM entries with legacy hashes
  Future<Result<int, TWMTDatabaseException>> countLegacyHashes() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE length(source_hash) < 64',
      );
      return (result.first['count'] as int?) ?? 0;
    });
  }

  /// Update the source_hash for an entry
  Future<Result<void, TWMTDatabaseException>> updateHash(
    String id,
    String newHash,
  ) async {
    return executeQuery(() async {
      await database.update(
        tableName,
        {'source_hash': newHash},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Batch update hashes for multiple entries
  Future<Result<int, TWMTDatabaseException>> updateHashesBatch(
    List<({String id, String newHash})> updates,
  ) async {
    if (updates.isEmpty) return const Ok(0);

    return executeTransaction((txn) async {
      var updatedCount = 0;
      for (final update in updates) {
        await txn.update(
          tableName,
          {'source_hash': update.newHash},
          where: 'id = ?',
          whereArgs: [update.id],
        );
        updatedCount++;
      }
      return updatedCount;
    });
  }
}
