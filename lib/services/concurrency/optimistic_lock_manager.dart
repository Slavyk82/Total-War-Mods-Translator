import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/concurrency_exceptions.dart';

/// Manager for optimistic locking using version numbers
///
/// Uses version numbers to detect concurrent modifications. Each update
/// increments the version. If the version doesn't match during update,
/// a conflict is detected.
///
/// This is lighter than pessimistic locking and works well for scenarios
/// where conflicts are rare.
class OptimisticLockManager {
  // ignore: unused_field
  final DatabaseService _databaseService;

  OptimisticLockManager({
    DatabaseService? databaseService,
  }) : _databaseService = databaseService ?? DatabaseService.instance;

  Database get _db => DatabaseService.database;

  /// Check version before update
  ///
  /// Verifies that the current version in database matches the expected version.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  /// - [expectedVersion]: Expected version number
  ///
  /// Returns:
  /// - [Ok]: Current version if it matches expected
  /// - [Err]: [VersionConflictException] if version mismatch
  ///
  /// Example:
  /// ```dart
  /// final result = await manager.checkVersion(
  ///   'translation_versions',
  ///   'trans_123',
  ///   5,
  /// );
  ///
  /// if (result is Ok) {
  ///   // Version matches, safe to update
  ///   await updateRecord();
  /// } else {
  ///   // Conflict detected, handle it
  ///   await handleConflict();
  /// }
  /// ```
  Future<Result<int, ConcurrencyException>> checkVersion(
    String tableName,
    String recordId,
    int expectedVersion,
  ) async {
    try {
      final results = await _db.query(
        tableName,
        columns: ['version'],
        where: 'id = ?',
        whereArgs: [recordId],
      );

      if (results.isEmpty) {
        return Err(ConcurrencyException(
          'Record not found',
          code: 'RECORD_NOT_FOUND',
          details: {'table': tableName, 'id': recordId},
        ));
      }

      final currentVersion = results.first['version'] as int;

      if (currentVersion != expectedVersion) {
        return Err(VersionConflictException(
          'Version conflict: expected $expectedVersion but found $currentVersion',
          resourceId: recordId,
          expectedVersion: expectedVersion,
          actualVersion: currentVersion,
        ));
      }

      return Ok(currentVersion);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to check version: ${e.toString()}',
        code: 'VERSION_CHECK_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error checking version: ${e.toString()}',
        code: 'VERSION_CHECK_ERROR',
      ));
    }
  }

  /// Update record with version check
  ///
  /// Performs an atomic update that verifies the version and increments it.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  /// - [expectedVersion]: Expected current version
  /// - [updates]: Map of fields to update
  ///
  /// Returns:
  /// - [Ok]: New version number if update succeeded
  /// - [Err]: Exception if update failed
  ///   - [VersionConflictException]: If version mismatch
  ///
  /// Example:
  /// ```dart
  /// final result = await manager.updateWithVersionCheck(
  ///   'translation_versions',
  ///   'trans_123',
  ///   5,
  ///   {'translated_text': 'New translation', 'status': 'translated'},
  /// );
  ///
  /// if (result is Ok) {
  ///   print('Updated to version ${result.value}');
  /// }
  /// ```
  Future<Result<int, ConcurrencyException>> updateWithVersionCheck(
    String tableName,
    String recordId,
    int expectedVersion,
    Map<String, dynamic> updates,
  ) async {
    try {
      final newVersion = expectedVersion + 1;

      // Add version increment and updated_at to updates
      final finalUpdates = {
        ...updates,
        'version': newVersion,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

      // Perform atomic update with version check
      final count = await _db.update(
        tableName,
        finalUpdates,
        where: 'id = ? AND version = ?',
        whereArgs: [recordId, expectedVersion],
      );

      if (count == 0) {
        // Check if record exists
        final exists = await _db.query(
          tableName,
          columns: ['version'],
          where: 'id = ?',
          whereArgs: [recordId],
        );

        if (exists.isEmpty) {
          return Err(ConcurrencyException(
            'Record not found',
            code: 'RECORD_NOT_FOUND',
            details: {'table': tableName, 'id': recordId},
          ));
        }

        final actualVersion = exists.first['version'] as int;
        return Err(VersionConflictException(
          'Version conflict during update',
          resourceId: recordId,
          expectedVersion: expectedVersion,
          actualVersion: actualVersion,
        ));
      }

      return Ok(newVersion);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to update with version check: ${e.toString()}',
        code: 'VERSION_UPDATE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error updating with version check: ${e.toString()}',
        code: 'VERSION_UPDATE_ERROR',
      ));
    }
  }

  /// Get current version of a record
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  ///
  /// Returns:
  /// - [Ok]: Current version number
  /// - [Err]: Exception if failed
  Future<Result<int, ConcurrencyException>> getCurrentVersion(
    String tableName,
    String recordId,
  ) async {
    try {
      final results = await _db.query(
        tableName,
        columns: ['version'],
        where: 'id = ?',
        whereArgs: [recordId],
      );

      if (results.isEmpty) {
        return Err(ConcurrencyException(
          'Record not found',
          code: 'RECORD_NOT_FOUND',
          details: {'table': tableName, 'id': recordId},
        ));
      }

      final version = results.first['version'] as int;
      return Ok(version);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get current version: ${e.toString()}',
        code: 'GET_VERSION_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting version: ${e.toString()}',
        code: 'GET_VERSION_ERROR',
      ));
    }
  }

  /// Increment version without other changes
  ///
  /// Useful for marking a record as "touched" without actual data changes.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  ///
  /// Returns:
  /// - [Ok]: New version number
  /// - [Err]: Exception if failed
  Future<Result<int, ConcurrencyException>> incrementVersion(
    String tableName,
    String recordId,
  ) async {
    try {
      final versionResult = await getCurrentVersion(tableName, recordId);
      if (versionResult is Err) {
        return Err(versionResult.error);
      }

      final currentVersion = (versionResult as Ok<int, ConcurrencyException>).value;
      final newVersion = currentVersion + 1;

      await _db.update(
        tableName,
        {
          'version': newVersion,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );

      return Ok(newVersion);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to increment version: ${e.toString()}',
        code: 'INCREMENT_VERSION_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error incrementing version: ${e.toString()}',
        code: 'INCREMENT_VERSION_ERROR',
      ));
    }
  }

  /// Reset version to 1 (use with caution)
  ///
  /// Should only be used when recreating a record or in migration scenarios.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  ///
  /// Returns:
  /// - [Ok]: true if reset successful
  /// - [Err]: Exception if failed
  Future<Result<bool, ConcurrencyException>> resetVersion(
    String tableName,
    String recordId,
  ) async {
    try {
      final count = await _db.update(
        tableName,
        {
          'version': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );

      return Ok(count > 0);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to reset version: ${e.toString()}',
        code: 'RESET_VERSION_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error resetting version: ${e.toString()}',
        code: 'RESET_VERSION_ERROR',
      ));
    }
  }

  /// Batch update multiple records with version checks
  ///
  /// Updates multiple records atomically within a transaction.
  /// If any version check fails, the entire batch is rolled back.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [updates]: List of (recordId, expectedVersion, updates) tuples
  ///
  /// Returns:
  /// - [Ok]: List of new version numbers (in same order as input)
  /// - [Err]: Exception if any update failed
  Future<Result<List<int>, ConcurrencyException>> batchUpdateWithVersionCheck(
    String tableName,
    List<({String recordId, int expectedVersion, Map<String, dynamic> updates})> updates,
  ) async {
    try {
      final newVersions = <int>[];

      await _db.transaction((txn) async {
        for (final update in updates) {
          final newVersion = update.expectedVersion + 1;

          final finalUpdates = {
            ...update.updates,
            'version': newVersion,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          };

          final count = await txn.update(
            tableName,
            finalUpdates,
            where: 'id = ? AND version = ?',
            whereArgs: [update.recordId, update.expectedVersion],
          );

          if (count == 0) {
            // Check actual version
            final exists = await txn.query(
              tableName,
              columns: ['version'],
              where: 'id = ?',
              whereArgs: [update.recordId],
            );

            if (exists.isEmpty) {
              throw ConcurrencyException(
                'Record not found: ${update.recordId}',
                code: 'RECORD_NOT_FOUND',
              );
            }

            final actualVersion = exists.first['version'] as int;
            throw VersionConflictException(
              'Version conflict for ${update.recordId}',
              resourceId: update.recordId,
              expectedVersion: update.expectedVersion,
              actualVersion: actualVersion,
            );
          }

          newVersions.add(newVersion);
        }
      });

      return Ok(newVersions);
    } on VersionConflictException catch (e) {
      return Err(e);
    } on ConcurrencyException catch (e) {
      return Err(e);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Batch update failed: ${e.toString()}',
        code: 'BATCH_UPDATE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error in batch update: ${e.toString()}',
        code: 'BATCH_UPDATE_ERROR',
      ));
    }
  }

  /// Check if a record has been modified since a given version
  ///
  /// Useful for detecting if a record was changed while user was editing.
  ///
  /// Parameters:
  /// - [tableName]: Table name
  /// - [recordId]: Record ID
  /// - [sinceVersion]: Version to compare against
  ///
  /// Returns:
  /// - [Ok]: true if modified, false if same version
  /// - [Err]: Exception if check failed
  Future<Result<bool, ConcurrencyException>> hasBeenModified(
    String tableName,
    String recordId,
    int sinceVersion,
  ) async {
    try {
      final versionResult = await getCurrentVersion(tableName, recordId);
      if (versionResult is Err) {
        return Err(versionResult.error);
      }

      final currentVersion = (versionResult as Ok<int, ConcurrencyException>).value;
      return Ok(currentVersion > sinceVersion);
    } catch (e) {
      return Err(ConcurrencyException(
        'Failed to check if modified: ${e.toString()}',
        code: 'CHECK_MODIFIED_FAILED',
      ));
    }
  }

  /// Get version history for a record
  ///
  /// Retrieves the version history from translation_version_history table.
  ///
  /// Parameters:
  /// - [recordId]: Record ID (translation_version_id)
  /// - [limit]: Maximum number of history entries (default: 50)
  ///
  /// Returns:
  /// - [Ok]: List of version history entries
  /// - [Err]: Exception if query failed
  Future<Result<List<Map<String, dynamic>>, ConcurrencyException>> getVersionHistory(
    String recordId, {
    int limit = 50,
  }) async {
    try {
      final results = await _db.query(
        'translation_version_history',
        where: 'translation_version_id = ?',
        whereArgs: [recordId],
        orderBy: 'version DESC',
        limit: limit,
      );

      return Ok(results);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get version history: ${e.toString()}',
        code: 'GET_HISTORY_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting history: ${e.toString()}',
        code: 'GET_HISTORY_ERROR',
      ));
    }
  }
}
