import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../services/database/migration_service.dart';

/// Migration V7: Event Store
///
/// Creates event_store table for EventBus event persistence.
/// This enables event sourcing, audit trails, and event replay capabilities.
///
/// This migration includes:
/// - event_store table for persisting domain events
/// - Indexes for performance optimization on common queries
class MigrationV7EventStore extends Migration {
  @override
  int get version => 7;

  @override
  String get description => 'Add event_store table for event sourcing';

  @override
  Future<void> up(Transaction txn) async {
    // Create event_store table
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS event_store (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        triggered_by TEXT,
        aggregate_id TEXT,
        aggregate_type TEXT,
        correlation_id TEXT,
        causation_id TEXT,
        metadata TEXT
      )
    ''');

    // Create indexes for performance
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_event_store_type
      ON event_store(event_type)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_event_store_aggregate
      ON event_store(aggregate_id, aggregate_type)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_event_store_occurred_at
      ON event_store(occurred_at DESC)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_event_store_correlation
      ON event_store(correlation_id)
      WHERE correlation_id IS NOT NULL
    ''');
  }

  @override
  Future<void> verify(Database db) async {
    // Verify table exists
    await _verifyTableExists(db);

    // Verify indexes exist
    await _verifyIndexesExist(db);
  }

  /// Verify table exists with correct schema
  Future<void> _verifyTableExists(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='event_store'",
    );

    if (result.isEmpty) {
      throw Exception('Table event_store not found');
    }

    // Verify columns
    final columns = await db.rawQuery('PRAGMA table_info(event_store)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    final requiredColumns = {
      'id',
      'event_type',
      'payload',
      'occurred_at',
      'triggered_by',
      'aggregate_id',
      'aggregate_type',
      'correlation_id',
      'causation_id',
      'metadata',
    };

    for (final column in requiredColumns) {
      if (!columnNames.contains(column)) {
        throw Exception('Required column not found: $column');
      }
    }
  }

  /// Verify indexes exist
  Future<void> _verifyIndexesExist(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='event_store'",
    );

    final indexNames = result.map((row) => row['name'] as String).toSet();

    final requiredIndexes = [
      'idx_event_store_type',
      'idx_event_store_aggregate',
      'idx_event_store_occurred_at',
      'idx_event_store_correlation',
    ];

    for (final index in requiredIndexes) {
      if (!indexNames.contains(index)) {
        throw Exception('Required index not found: $index');
      }
    }
  }

  @override
  Future<void> down(Transaction txn) async {
    // Drop indexes
    await txn.execute('DROP INDEX IF EXISTS idx_event_store_type');
    await txn.execute('DROP INDEX IF EXISTS idx_event_store_aggregate');
    await txn.execute('DROP INDEX IF EXISTS idx_event_store_occurred_at');
    await txn.execute('DROP INDEX IF EXISTS idx_event_store_correlation');

    // Drop table
    await txn.execute('DROP TABLE IF EXISTS event_store');
  }
}
