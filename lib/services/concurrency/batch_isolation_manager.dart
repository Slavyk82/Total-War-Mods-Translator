import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/lock_info.dart';
import 'models/concurrency_exceptions.dart';

/// Manager for batch isolation and entry reservations
///
/// Prevents duplicate processing of translation units by multiple concurrent batches.
/// When a batch starts processing entries, it "checks them out" (reserves them).
/// Other batches skip reserved entries until they are released or timeout expires.
class BatchIsolationManager {
  final Uuid _uuid;

  /// Default reservation timeout (30 minutes)
  static const Duration defaultTimeout = Duration(minutes: 30);

  /// Maximum reservation timeout (2 hours)
  static const Duration maxTimeout = Duration(hours: 2);

  BatchIsolationManager({
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Database get _db => DatabaseService.database;

  /// Reserve (check out) translation units for batch processing
  ///
  /// Parameters:
  /// - [batchId]: Batch ID that will process the units
  /// - [unitIds]: List of translation unit IDs to reserve
  /// - [languageCode]: Target language code
  /// - [timeout]: Reservation timeout (default: 30 minutes)
  ///
  /// Returns:
  /// - [Ok]: List of successfully reserved unit IDs
  /// - [Err]: Exception if reservation failed
  ///
  /// Note: Units already reserved by other batches are skipped (not an error).
  ///
  /// Example:
  /// ```dart
  /// final result = await manager.reserveUnits(
  ///   'batch_123',
  ///   ['unit_1', 'unit_2', 'unit_3'],
  ///   'fr',
  /// );
  ///
  /// if (result is Ok) {
  ///   print('Reserved ${result.value.length} units');
  ///   // Process reserved units...
  /// }
  /// ```
  Future<Result<List<String>, ConcurrencyException>> reserveUnits(
    String batchId,
    List<String> unitIds,
    String languageCode, {
    Duration timeout = defaultTimeout,
  }) async {
    if (unitIds.isEmpty) {
      return const Ok([]);
    }

    try {
      // Clean up expired reservations first
      await _cleanupExpiredReservations();

      final reservedUnits = <String>[];
      final now = DateTime.now();
      final safeTimeout = _clampDuration(
        timeout,
        const Duration(minutes: 5),
        maxTimeout,
      );
      final expiresAt = now.add(safeTimeout);

      await _db.transaction((txn) async {
        for (final unitId in unitIds) {
          // Check if unit is already reserved
          final existing = await txn.query(
            'batch_entry_reservations',
            where: 'translation_unit_id = ? AND language_code = ? AND status = ?',
            whereArgs: [unitId, languageCode, 'active'],
            limit: 1,
          );

          if (existing.isNotEmpty) {
            // Already reserved by another batch, skip
            continue;
          }

          // Reserve the unit
          final reservationId = _uuid.v4();
          await txn.insert('batch_entry_reservations', {
            'id': reservationId,
            'batch_id': batchId,
            'translation_unit_id': unitId,
            'language_code': languageCode,
            'reserved_at': now.millisecondsSinceEpoch,
            'expires_at': expiresAt.millisecondsSinceEpoch,
            'status': 'active',
          });

          reservedUnits.add(unitId);
        }
      });

      return Ok(reservedUnits);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to reserve units: ${e.toString()}',
        code: 'RESERVE_UNITS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error reserving units: ${e.toString()}',
        code: 'RESERVE_UNITS_ERROR',
      ));
    }
  }

  /// Release (check in) reserved units after processing
  ///
  /// Parameters:
  /// - [batchId]: Batch ID that reserved the units
  /// - [unitIds]: List of unit IDs to release (if empty, releases all for batch)
  /// - [languageCode]: Language code
  ///
  /// Returns:
  /// - [Ok]: Number of units released
  /// - [Err]: Exception if release failed
  Future<Result<int, ConcurrencyException>> releaseUnits(
    String batchId,
    String languageCode, {
    List<String>? unitIds,
  }) async {
    try {
      int count;

      if (unitIds == null || unitIds.isEmpty) {
        // Release all units for this batch and language
        count = await _db.update(
          'batch_entry_reservations',
          {
            'status': 'completed',
            'released_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'batch_id = ? AND language_code = ? AND status = ?',
          whereArgs: [batchId, languageCode, 'active'],
        );
      } else {
        // Release specific units
        final placeholders = unitIds.map((_) => '?').join(', ');
        count = await _db.update(
          'batch_entry_reservations',
          {
            'status': 'completed',
            'released_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'batch_id = ? AND language_code = ? AND translation_unit_id IN ($placeholders) AND status = ?',
          whereArgs: [batchId, languageCode, ...unitIds, 'active'],
        );
      }

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to release units: ${e.toString()}',
        code: 'RELEASE_UNITS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error releasing units: ${e.toString()}',
        code: 'RELEASE_UNITS_ERROR',
      ));
    }
  }

  /// Release units on error/cancellation
  ///
  /// Marks reservations as 'failed' instead of 'completed'.
  Future<Result<int, ConcurrencyException>> releaseUnitsOnError(
    String batchId,
    String languageCode, {
    List<String>? unitIds,
    String? errorReason,
  }) async {
    try {
      int count;

      if (unitIds == null || unitIds.isEmpty) {
        count = await _db.update(
          'batch_entry_reservations',
          {
            'status': 'failed',
            'released_at': DateTime.now().millisecondsSinceEpoch,
            if (errorReason != null) 'error_reason': errorReason,
          },
          where: 'batch_id = ? AND language_code = ? AND status = ?',
          whereArgs: [batchId, languageCode, 'active'],
        );
      } else {
        final placeholders = unitIds.map((_) => '?').join(', ');
        count = await _db.update(
          'batch_entry_reservations',
          {
            'status': 'failed',
            'released_at': DateTime.now().millisecondsSinceEpoch,
            if (errorReason != null) 'error_reason': errorReason,
          },
          where: 'batch_id = ? AND language_code = ? AND translation_unit_id IN ($placeholders) AND status = ?',
          whereArgs: [batchId, languageCode, ...unitIds, 'active'],
        );
      }

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to release units on error: ${e.toString()}',
        code: 'RELEASE_ERROR_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error releasing units on error: ${e.toString()}',
        code: 'RELEASE_ERROR_ERROR',
      ));
    }
  }

  /// Check if units are available (not reserved)
  ///
  /// Parameters:
  /// - [unitIds]: List of unit IDs to check
  /// - [languageCode]: Language code
  ///
  /// Returns:
  /// - [Ok]: List of available (non-reserved) unit IDs
  /// - [Err]: Exception if check failed
  Future<Result<List<String>, ConcurrencyException>> getAvailableUnits(
    List<String> unitIds,
    String languageCode,
  ) async {
    if (unitIds.isEmpty) {
      return const Ok([]);
    }

    try {
      // Clean up expired first
      await _cleanupExpiredReservations();

      final availableUnits = <String>[];

      await _db.transaction((txn) async {
        for (final unitId in unitIds) {
          final reserved = await txn.query(
            'batch_entry_reservations',
            where: 'translation_unit_id = ? AND language_code = ? AND status = ?',
            whereArgs: [unitId, languageCode, 'active'],
            limit: 1,
          );

          if (reserved.isEmpty) {
            availableUnits.add(unitId);
          }
        }
      });

      return Ok(availableUnits);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get available units: ${e.toString()}',
        code: 'GET_AVAILABLE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting available units: ${e.toString()}',
        code: 'GET_AVAILABLE_ERROR',
      ));
    }
  }

  /// Get reserved units for a batch
  ///
  /// Parameters:
  /// - [batchId]: Batch ID
  /// - [languageCode]: Language code (optional, if null returns all languages)
  ///
  /// Returns:
  /// - [Ok]: List of BatchReservation objects
  /// - [Err]: Exception if query failed
  Future<Result<List<BatchReservation>, ConcurrencyException>> getBatchReservations(
    String batchId, {
    String? languageCode,
  }) async {
    try {
      final List<Map<String, dynamic>> results;

      if (languageCode != null) {
        results = await _db.query(
          'batch_entry_reservations',
          where: 'batch_id = ? AND language_code = ? AND status = ?',
          whereArgs: [batchId, languageCode, 'active'],
        );
      } else {
        results = await _db.query(
          'batch_entry_reservations',
          where: 'batch_id = ? AND status = ?',
          whereArgs: [batchId, 'active'],
        );
      }

      final reservations = results.map(_parseReservation).toList();
      return Ok(reservations);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get batch reservations: ${e.toString()}',
        code: 'GET_RESERVATIONS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting reservations: ${e.toString()}',
        code: 'GET_RESERVATIONS_ERROR',
      ));
    }
  }

  /// Extend reservation timeout
  ///
  /// Useful for long-running batches that need more time.
  ///
  /// Parameters:
  /// - [batchId]: Batch ID
  /// - [languageCode]: Language code
  /// - [extension]: Additional time to add
  ///
  /// Returns:
  /// - [Ok]: Number of reservations extended
  /// - [Err]: Exception if extension failed
  Future<Result<int, ConcurrencyException>> extendReservations(
    String batchId,
    String languageCode,
    Duration extension,
  ) async {
    try {
      final safeExtension = _clampDuration(
        extension,
        const Duration(minutes: 5),
        const Duration(hours: 1),
      );

      // Get current reservations
      final results = await _db.query(
        'batch_entry_reservations',
        columns: ['id', 'expires_at'],
        where: 'batch_id = ? AND language_code = ? AND status = ?',
        whereArgs: [batchId, languageCode, 'active'],
      );

      int count = 0;

      await _db.transaction((txn) async {
        for (final row in results) {
          final currentExpiresAt = DateTime.fromMillisecondsSinceEpoch(
            row['expires_at'] as int,
          );
          final newExpiresAt = currentExpiresAt.add(safeExtension);

          await txn.update(
            'batch_entry_reservations',
            {'expires_at': newExpiresAt.millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          count++;
        }
      });

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to extend reservations: ${e.toString()}',
        code: 'EXTEND_RESERVATIONS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error extending reservations: ${e.toString()}',
        code: 'EXTEND_RESERVATIONS_ERROR',
      ));
    }
  }

  /// Clean up expired reservations
  ///
  /// Marks expired reservations as 'expired' to free them for other batches.
  Future<Result<int, ConcurrencyException>> cleanupExpiredReservations() async {
    return await _cleanupExpiredReservations();
  }

  /// Get statistics about batch reservations
  ///
  /// Returns counts by status for monitoring.
  Future<Result<Map<String, int>, ConcurrencyException>> getReservationStats() async {
    try {
      final results = await _db.rawQuery('''
        SELECT status, COUNT(*) as count
        FROM batch_entry_reservations
        GROUP BY status
      ''');

      final stats = <String, int>{};
      for (final row in results) {
        stats[row['status'] as String] = row['count'] as int;
      }

      return Ok(stats);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get reservation stats: ${e.toString()}',
        code: 'GET_STATS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting stats: ${e.toString()}',
        code: 'GET_STATS_ERROR',
      ));
    }
  }

  // Private helper methods

  Future<Result<int, ConcurrencyException>> _cleanupExpiredReservations() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final count = await _db.update(
        'batch_entry_reservations',
        {
          'status': 'expired',
          'released_at': now,
        },
        where: 'status = ? AND expires_at < ?',
        whereArgs: ['active', now],
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to cleanup expired reservations: ${e.toString()}',
        code: 'CLEANUP_EXPIRED_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error cleaning up: ${e.toString()}',
        code: 'CLEANUP_EXPIRED_ERROR',
      ));
    }
  }

  BatchReservation _parseReservation(Map<String, dynamic> row) {
    return BatchReservation(
      id: row['id'] as String,
      batchId: row['batch_id'] as String,
      translationUnitId: row['translation_unit_id'] as String,
      languageCode: row['language_code'] as String,
      reservedAt: DateTime.fromMillisecondsSinceEpoch(row['reserved_at'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int),
      status: row['status'] as String,
    );
  }

  /// Helper to clamp Duration values
  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
