import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart' show TWMTDatabaseException;
import '../services/database/database_service.dart' show DatabaseService;

/// Base repository interface for common CRUD operations.
///
/// All repositories should implement this interface to provide
/// consistent data access patterns throughout the application.
///
/// Type parameter [T] represents the domain model type.
abstract class BaseRepository<T> {
  /// Get database instance
  Database get database => DatabaseService.database;

  /// Get a single entity by its ID
  ///
  /// Returns [Ok] with the entity if found, [Err] with exception if not found or error occurs.
  Future<Result<T, TWMTDatabaseException>> getById(String id);

  /// Get all entities
  ///
  /// Returns [Ok] with list of entities, [Err] with exception if error occurs.
  Future<Result<List<T>, TWMTDatabaseException>> getAll();

  /// Insert a new entity
  ///
  /// Returns [Ok] with the inserted entity, [Err] with exception if error occurs.
  Future<Result<T, TWMTDatabaseException>> insert(T entity);

  /// Update an existing entity
  ///
  /// Returns [Ok] with the updated entity, [Err] with exception if error occurs.
  Future<Result<T, TWMTDatabaseException>> update(T entity);

  /// Delete an entity by its ID
  ///
  /// Returns [Ok] with void if successful, [Err] with exception if error occurs.
  Future<Result<void, TWMTDatabaseException>> delete(String id);

  /// Execute a query and handle errors consistently
  ///
  /// This helper method wraps database operations with error handling.
  Future<Result<R, TWMTDatabaseException>> executeQuery<R>(
    Future<R> Function() query,
  ) async {
    // Check database initialization before executing query
    if (!DatabaseService.isInitialized) {
      return Err(
        TWMTDatabaseException(
          'Cannot access repository: DatabaseService not initialized. '
          'Ensure ServiceLocator.initialize() completes before accessing repositories.',
        ),
      );
    }

    try {
      final result = await query();
      return Ok(result);
    } on TWMTDatabaseException catch (e) {
      return Err(e);
    } catch (e, stackTrace) {
      return Err(
        TWMTDatabaseException(
          'Database operation failed: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Execute a transaction
  ///
  /// This helper method wraps transactions with error handling.
  Future<Result<R, TWMTDatabaseException>> executeTransaction<R>(
    Future<R> Function(Transaction txn) action,
  ) async {
    // Check database initialization before executing transaction
    if (!DatabaseService.isInitialized) {
      return Err(
        TWMTDatabaseException(
          'Cannot execute transaction: DatabaseService not initialized. '
          'Ensure ServiceLocator.initialize() completes before accessing repositories.',
        ),
      );
    }

    try {
      final result = await database.transaction(action);
      return Ok(result);
    } on TWMTDatabaseException catch (e) {
      return Err(e);
    } catch (e, stackTrace) {
      return Err(
        TWMTDatabaseException(
          'Transaction failed: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Convert database map to entity
  ///
  /// Each repository must implement this to convert raw database
  /// maps to their specific domain model.
  T fromMap(Map<String, dynamic> map);

  /// Convert entity to database map
  ///
  /// Each repository must implement this to convert their domain
  /// model to a database-compatible map.
  Map<String, dynamic> toMap(T entity);

  /// Get table name for this repository
  ///
  /// Each repository must specify its table name.
  String get tableName;
}
