import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/ignored_source_text.dart';
import 'base_repository.dart';

/// Repository for managing IgnoredSourceText entities.
///
/// Provides CRUD operations for user-configurable source texts that should be
/// skipped during translation. Includes methods for reset to defaults functionality.
class IgnoredSourceTextRepository extends BaseRepository<IgnoredSourceText> {
  /// Default source texts that are seeded on first run or reset.
  ///
  /// Note: Texts fully enclosed in brackets like [placeholder] are automatically
  /// filtered by TranslationSkipFilter.isFullyBracketedText() and don't need
  /// to be listed here.
  static const defaultTexts = [
    'placeholder',
    'dummy',
  ];

  @override
  String get tableName => 'ignored_source_texts';

  @override
  IgnoredSourceText fromMap(Map<String, dynamic> map) {
    return IgnoredSourceText.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(IgnoredSourceText entity) {
    return entity.toJson();
  }

  @override
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Ignored source text not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'source_text ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> insert(
      IgnoredSourceText entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      await database.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return entity;
    });
  }

  @override
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> update(
      IgnoredSourceText entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Ignored source text not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Ignored source text not found for deletion: $id');
      }
    });
  }

  /// Get all enabled source texts, ordered alphabetically.
  ///
  /// Returns [Ok] with list of enabled texts, [Err] with exception if error occurs.
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>>
      getEnabledTexts() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_enabled = ?',
        whereArgs: [1],
        orderBy: 'source_text ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Toggle the enabled status of an ignored source text.
  ///
  /// Returns [Ok] with updated entity, [Err] with exception if error occurs.
  Future<Result<IgnoredSourceText, TWMTDatabaseException>> toggleEnabled(
      String id) async {
    return executeQuery(() async {
      // Get current entity
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Ignored source text not found with id: $id');
      }

      final entity = fromMap(maps.first);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Toggle the enabled status
      final updated = entity.copyWith(
        isEnabled: !entity.isEnabled,
        updatedAt: now,
      );

      // Update in database
      await database.update(
        tableName,
        toMap(updated),
        where: 'id = ?',
        whereArgs: [id],
      );

      return updated;
    });
  }

  /// Check if a source text already exists (case-insensitive).
  ///
  /// Returns [Ok] with true if exists, [Err] with exception if error occurs.
  Future<Result<bool, TWMTDatabaseException>> existsByText(
      String sourceText) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE LOWER(source_text) = ?',
        [sourceText.trim().toLowerCase()],
      );

      final count = result.firstOrNull?['count'];
      return count is int && count > 0;
    });
  }

  /// Check if a source text exists (case-insensitive) excluding a specific ID.
  ///
  /// Useful for update validation to allow the entity's own text.
  Future<Result<bool, TWMTDatabaseException>> existsByTextExcludingId(
      String sourceText, String excludeId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE LOWER(source_text) = ? AND id != ?',
        [sourceText.trim().toLowerCase(), excludeId],
      );

      final count = result.firstOrNull?['count'];
      return count is int && count > 0;
    });
  }

  /// Get the count of all ignored source texts.
  ///
  /// Returns [Ok] with count, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> getTotalCount() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName',
      );

      final count = result.firstOrNull?['count'];
      return count is int ? count : 0;
    });
  }

  /// Get the count of enabled ignored source texts.
  ///
  /// Returns [Ok] with count, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> getEnabledCount() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE is_enabled = 1',
      );

      final count = result.firstOrNull?['count'];
      return count is int ? count : 0;
    });
  }

  /// Delete all ignored source texts.
  ///
  /// Used for reset to defaults functionality.
  /// Returns [Ok] with number of deleted rows, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> deleteAll() async {
    return executeQuery(() async {
      return await database.delete(tableName);
    });
  }

  /// Insert default source texts.
  ///
  /// Used for reset to defaults functionality.
  /// Returns [Ok] with list of inserted entities, [Err] with exception if error occurs.
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>>
      insertDefaults() async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final entities = <IgnoredSourceText>[];

      for (final text in defaultTexts) {
        final entity = IgnoredSourceText(
          id: const Uuid().v4(),
          sourceText: text,
          isEnabled: true,
          createdAt: now,
          updatedAt: now,
        );

        await database.insert(
          tableName,
          toMap(entity),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        entities.add(entity);
      }

      return entities;
    });
  }

  /// Reset to defaults: delete all and insert default values.
  ///
  /// Returns [Ok] with list of default entities, [Err] with exception if error occurs.
  Future<Result<List<IgnoredSourceText>, TWMTDatabaseException>>
      resetToDefaults() async {
    return executeTransaction((txn) async {
      // Delete all
      await txn.delete(tableName);

      // Insert defaults
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final entities = <IgnoredSourceText>[];

      for (final text in defaultTexts) {
        final entity = IgnoredSourceText(
          id: const Uuid().v4(),
          sourceText: text,
          isEnabled: true,
          createdAt: now,
          updatedAt: now,
        );

        await txn.insert(
          tableName,
          toMap(entity),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        entities.add(entity);
      }

      return entities;
    });
  }
}
