import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../services/database/migration_service.dart';

/// Migration V6: LLM Provider Models Management
///
/// Creates infrastructure for managing multiple LLM models per provider
/// with support for enabling/disabling models, marking defaults, and archiving
/// models that are no longer available from the provider's API.
///
/// This migration includes:
/// - llm_provider_models table for storing fetched models
/// - Indexes for performance optimization
/// - Trigger to ensure only one default model per provider
/// - Support for model archival when models become unavailable
class MigrationV6LlmProviderModels extends Migration {
  @override
  int get version => 6;

  @override
  String get description =>
      'Add LLM provider models management with archival support';

  @override
  Future<void> up(Transaction txn) async {
    // Create llm_provider_models table
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS llm_provider_models (
        id TEXT PRIMARY KEY,
        provider_code TEXT NOT NULL,
        model_id TEXT NOT NULL,
        display_name TEXT,
        is_enabled INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_fetched_at INTEGER NOT NULL,
        UNIQUE(provider_code, model_id)
      )
    ''');

    // Create indexes for performance
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_llm_models_provider
      ON llm_provider_models(provider_code)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_llm_models_enabled
      ON llm_provider_models(provider_code, is_enabled)
      WHERE is_archived = 0
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_llm_models_default
      ON llm_provider_models(provider_code, is_default)
      WHERE is_archived = 0
    ''');

    // Create trigger to ensure only one default model per provider
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_llm_models_single_default
      BEFORE UPDATE OF is_default ON llm_provider_models
      WHEN NEW.is_default = 1
      BEGIN
        UPDATE llm_provider_models
        SET is_default = 0
        WHERE provider_code = NEW.provider_code
          AND id != NEW.id
          AND is_default = 1;
      END
    ''');

    // Create trigger to auto-update updated_at timestamp
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_llm_models_updated_at
      AFTER UPDATE ON llm_provider_models
      FOR EACH ROW
      BEGIN
        UPDATE llm_provider_models
        SET updated_at = strftime('%s', 'now')
        WHERE id = NEW.id;
      END
    ''');

    // Create trigger to prevent enabling archived models
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_llm_models_prevent_enable_archived
      BEFORE UPDATE OF is_enabled ON llm_provider_models
      WHEN NEW.is_enabled = 1 AND NEW.is_archived = 1
      BEGIN
        SELECT RAISE(ABORT, 'Cannot enable archived model');
      END
    ''');

    // Create trigger to prevent setting archived models as default
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_llm_models_prevent_default_archived
      BEFORE UPDATE OF is_default ON llm_provider_models
      WHEN NEW.is_default = 1 AND NEW.is_archived = 1
      BEGIN
        SELECT RAISE(ABORT, 'Cannot set archived model as default');
      END
    ''');
  }

  @override
  Future<void> verify(Database db) async {
    // Verify table exists
    await _verifyTableExists(db);

    // Verify indexes exist
    await _verifyIndexesExist(db);

    // Verify triggers exist
    await _verifyTriggersExist(db);

    // Verify constraints work
    await _verifyConstraints(db);
  }

  /// Verify table exists with correct schema
  Future<void> _verifyTableExists(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='llm_provider_models'",
    );

    if (result.isEmpty) {
      throw Exception('Table llm_provider_models not found');
    }

    // Verify columns
    final columns = await db.rawQuery('PRAGMA table_info(llm_provider_models)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    final requiredColumns = {
      'id',
      'provider_code',
      'model_id',
      'display_name',
      'is_enabled',
      'is_default',
      'is_archived',
      'created_at',
      'updated_at',
      'last_fetched_at',
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
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='llm_provider_models'",
    );

    final indexNames = result.map((row) => row['name'] as String).toSet();

    final requiredIndexes = [
      'idx_llm_models_provider',
      'idx_llm_models_enabled',
      'idx_llm_models_default',
    ];

    for (final index in requiredIndexes) {
      if (!indexNames.contains(index)) {
        throw Exception('Required index not found: $index');
      }
    }
  }

  /// Verify triggers exist
  Future<void> _verifyTriggersExist(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='llm_provider_models'",
    );

    final triggerNames = result.map((row) => row['name'] as String).toSet();

    final requiredTriggers = [
      'trg_llm_models_single_default',
      'trg_llm_models_updated_at',
      'trg_llm_models_prevent_enable_archived',
      'trg_llm_models_prevent_default_archived',
    ];

    for (final trigger in requiredTriggers) {
      if (!triggerNames.contains(trigger)) {
        throw Exception('Required trigger not found: $trigger');
      }
    }
  }

  /// Verify constraints work correctly
  Future<void> _verifyConstraints(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Test 1: Insert two models for same provider
    await db.insert('llm_provider_models', {
      'id': 'test_model_1',
      'provider_code': 'test_provider',
      'model_id': 'model-1',
      'is_enabled': 0,
      'is_default': 0,
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
      'last_fetched_at': now,
    });

    await db.insert('llm_provider_models', {
      'id': 'test_model_2',
      'provider_code': 'test_provider',
      'model_id': 'model-2',
      'is_enabled': 0,
      'is_default': 0,
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
      'last_fetched_at': now,
    });

    // Test 2: Set first as default
    await db.update(
      'llm_provider_models',
      {'is_default': 1},
      where: 'id = ?',
      whereArgs: ['test_model_1'],
    );

    // Test 3: Set second as default (should unset first)
    await db.update(
      'llm_provider_models',
      {'is_default': 1},
      where: 'id = ?',
      whereArgs: ['test_model_2'],
    );

    // Verify only one default
    final defaults = await db.query(
      'llm_provider_models',
      where: 'provider_code = ? AND is_default = 1',
      whereArgs: ['test_provider'],
    );

    if (defaults.length != 1 || defaults.first['id'] != 'test_model_2') {
      throw Exception(
          'Single default constraint not working: found ${defaults.length} defaults');
    }

    // Test 4: Archive a model
    await db.update(
      'llm_provider_models',
      {'is_archived': 1},
      where: 'id = ?',
      whereArgs: ['test_model_1'],
    );

    // Test 5: Try to enable archived model (should fail)
    try {
      await db.update(
        'llm_provider_models',
        {'is_enabled': 1},
        where: 'id = ?',
        whereArgs: ['test_model_1'],
      );
      throw Exception('Archived model enable constraint not working');
    } catch (e) {
      if (!e.toString().contains('Cannot enable archived model')) {
        throw Exception('Wrong error for archived model enable: $e');
      }
    }

    // Test 6: Try to set archived model as default (should fail)
    try {
      await db.update(
        'llm_provider_models',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: ['test_model_1'],
      );
      throw Exception('Archived model default constraint not working');
    } catch (e) {
      if (!e.toString().contains('Cannot set archived model as default')) {
        throw Exception('Wrong error for archived model default: $e');
      }
    }

    // Clean up test data
    await db.delete(
      'llm_provider_models',
      where: 'provider_code = ?',
      whereArgs: ['test_provider'],
    );
  }

  @override
  Future<void> down(Transaction txn) async {
    // Drop triggers
    await txn.execute(
        'DROP TRIGGER IF EXISTS trg_llm_models_single_default');
    await txn.execute(
        'DROP TRIGGER IF EXISTS trg_llm_models_updated_at');
    await txn.execute(
        'DROP TRIGGER IF EXISTS trg_llm_models_prevent_enable_archived');
    await txn.execute(
        'DROP TRIGGER IF EXISTS trg_llm_models_prevent_default_archived');

    // Drop indexes
    await txn.execute('DROP INDEX IF EXISTS idx_llm_models_provider');
    await txn.execute('DROP INDEX IF EXISTS idx_llm_models_enabled');
    await txn.execute('DROP INDEX IF EXISTS idx_llm_models_default');

    // Drop table
    await txn.execute('DROP TABLE IF EXISTS llm_provider_models');
  }
}
