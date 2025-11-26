import 'package:uuid/uuid.dart';
import '../../models/common/service_exception.dart';
import 'database_service.dart';

/// Example repository demonstrating database layer usage patterns.
///
/// This file provides reference implementations for:
/// - Basic CRUD operations
/// - Transaction usage
/// - FTS5 search
/// - View queries
/// - Cache access
/// - Error handling
///
/// Use these patterns as templates for implementing actual repositories.
class ExampleProjectRepository {
  const ExampleProjectRepository();

  static const _uuid = Uuid();

  /// Create a new project with initial language
  ///
  /// Demonstrates:
  /// - Transaction usage for multi-table operations
  /// - UUID generation
  /// - Unix timestamp handling
  /// - Error handling
  Future<String> createProject({
    required String name,
    required String gameInstallationId,
    required String languageId,
    String? modSteamId,
    int batchSize = 25,
    int parallelBatches = 3,
  }) async {
    try {
      final projectId = _uuid.v4();
      final projectLanguageId = _uuid.v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await DatabaseService.transaction((txn) async {
        // Insert project
        await txn.insert('projects', {
          'id': projectId,
          'name': name,
          'mod_steam_id': modSteamId,
          'game_installation_id': gameInstallationId,
          'status': 'draft',
          'batch_size': batchSize,
          'parallel_batches': parallelBatches,
          'created_at': timestamp,
          'updated_at': timestamp,
        });

        // Insert project language
        await txn.insert('project_languages', {
          'id': projectLanguageId,
          'project_id': projectId,
          'language_id': languageId,
          'status': 'pending',
          'progress_percent': 0.0,
          'created_at': timestamp,
          'updated_at': timestamp,
        });
      });

      return projectId;
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to create project: $name',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get project by ID
  ///
  /// Demonstrates:
  /// - Simple query with WHERE clause
  /// - Null handling for not found
  Future<Map<String, dynamic>?> getProjectById(String projectId) async {
    try {
      final results = await DatabaseService.query(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
        limit: 1,
      );

      return results.isEmpty ? null : results.first;
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get project: $projectId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get all projects for a game
  ///
  /// Demonstrates:
  /// - Query with WHERE and ORDER BY
  /// - Multiple results
  Future<List<Map<String, dynamic>>> getProjectsByGame(
    String gameInstallationId,
  ) async {
    try {
      return await DatabaseService.query(
        'projects',
        where: 'game_installation_id = ?',
        whereArgs: [gameInstallationId],
        orderBy: 'updated_at DESC',
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get projects for game: $gameInstallationId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Update project name
  ///
  /// Demonstrates:
  /// - Simple UPDATE operation
  /// - Auto-updated timestamp (via trigger)
  Future<void> updateProjectName(String projectId, String name) async {
    try {
      final updated = await DatabaseService.update(
        'projects',
        {'name': name},
        where: 'id = ?',
        whereArgs: [projectId],
      );

      if (updated == 0) {
        throw Exception('Project not found: $projectId');
      }
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to update project name: $projectId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Delete project (cascades to related data)
  ///
  /// Demonstrates:
  /// - DELETE operation
  /// - CASCADE behavior
  Future<void> deleteProject(String projectId) async {
    try {
      final deleted = await DatabaseService.delete(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
      );

      if (deleted == 0) {
        throw Exception('Project not found: $projectId');
      }
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to delete project: $projectId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Search projects by name using FTS5
  ///
  /// Demonstrates:
  /// - Full-text search (100-1000x faster than LIKE)
  /// - Raw query with JOIN
  Future<List<Map<String, dynamic>>> searchProjectsByName(
    String searchTerm,
  ) async {
    try {
      // Note: For projects, we'd typically add an FTS5 table in a future migration
      // For now, this demonstrates the pattern using LIKE
      return await DatabaseService.query(
        'projects',
        where: 'name LIKE ?',
        whereArgs: ['%$searchTerm%'],
        orderBy: 'updated_at DESC',
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to search projects: $searchTerm',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get project statistics using view
  ///
  /// Demonstrates:
  /// - Using pre-calculated view
  /// - Complex aggregated data
  Future<List<Map<String, dynamic>>> getProjectStats(String projectId) async {
    try {
      return await DatabaseService.rawQuery(
        'SELECT * FROM v_project_language_stats WHERE project_id = ?',
        [projectId],
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get project stats: $projectId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get translation cache for DataGrid display
  ///
  /// Demonstrates:
  /// - Using denormalized cache
  /// - Pagination with LIMIT/OFFSET
  Future<List<Map<String, dynamic>>> getTranslationCache({
    required String projectLanguageId,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      return await DatabaseService.query(
        'translation_view_cache',
        where: 'project_language_id = ?',
        whereArgs: [projectLanguageId],
        orderBy: 'version_updated_at DESC',
        limit: limit,
        offset: offset,
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get translation cache: $projectLanguageId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Bulk insert translation units
  ///
  /// Demonstrates:
  /// - Batch operations in transaction
  /// - Performance optimization
  Future<void> bulkInsertTranslationUnits(
    String projectId,
    List<Map<String, String>> units,
  ) async {
    try {
      await DatabaseService.transaction((txn) async {
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        for (final unit in units) {
          await txn.insert('translation_units', {
            'id': _uuid.v4(),
            'project_id': projectId,
            'key': unit['key'],
            'source_text': unit['source_text'],
            'context': unit['context'],
            'is_obsolete': 0,
            'created_at': timestamp,
            'updated_at': timestamp,
          });
        }
      });
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to bulk insert translation units',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Search translation units using FTS5
  ///
  /// Demonstrates:
  /// - FTS5 full-text search
  /// - JOIN between FTS and regular table
  Future<List<Map<String, dynamic>>> searchTranslationUnits({
    required String projectId,
    required String searchTerm,
  }) async {
    try {
      return await DatabaseService.rawQuery(
        '''
        SELECT tu.*
        FROM translation_units tu
        INNER JOIN translation_units_fts fts ON fts.rowid = tu.rowid
        WHERE tu.project_id = ? AND translation_units_fts MATCH ?
        ORDER BY tu.updated_at DESC
        ''',
        [projectId, searchTerm],
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to search translation units: $searchTerm',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get translations needing review using view
  ///
  /// Demonstrates:
  /// - Using specialized view
  /// - Filtering pre-calculated data
  Future<List<Map<String, dynamic>>> getTranslationsNeedingReview(
    String projectId,
  ) async {
    try {
      return await DatabaseService.rawQuery(
        'SELECT * FROM v_translations_needing_review WHERE project_id = ? ORDER BY updated_at DESC',
        [projectId],
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get translations needing review: $projectId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Update translation with history tracking
  ///
  /// Demonstrates:
  /// - Transaction with multiple operations
  /// - History tracking pattern
  Future<void> updateTranslation({
    required String versionId,
    required String translatedText,
    required String status,
    double? confidenceScore,
    required String changedBy,
    String? changeReason,
  }) async {
    try {
      await DatabaseService.transaction((txn) async {
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Update translation version
        await txn.update(
          'translation_versions',
          {
            'translated_text': translatedText,
            'status': status,
            'confidence_score': confidenceScore,
            'updated_at': timestamp,
          },
          where: 'id = ?',
          whereArgs: [versionId],
        );

        // Insert history record
        await txn.insert('translation_version_history', {
          'id': _uuid.v4(),
          'version_id': versionId,
          'translated_text': translatedText,
          'status': status,
          'confidence_score': confidenceScore,
          'changed_by': changedBy,
          'change_reason': changeReason,
          'created_at': timestamp,
        });
      });
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to update translation: $versionId',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get all languages
  ///
  /// Demonstrates:
  /// - Simple query on reference table
  /// - Filtering by active status
  Future<List<Map<String, dynamic>>> getActiveLanguages() async {
    try {
      return await DatabaseService.query(
        'languages',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'native_name',
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get active languages',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get setting value
  ///
  /// Demonstrates:
  /// - Settings retrieval
  /// - Type conversion
  Future<T?> getSetting<T>(String key) async {
    try {
      final results = await DatabaseService.query(
        'settings',
        columns: ['value', 'value_type'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (results.isEmpty) {
        return null;
      }

      final value = results.first['value'] as String;
      final valueType = results.first['value_type'] as String;

      switch (valueType) {
        case 'integer':
          return int.parse(value) as T;
        case 'boolean':
          return (value == '1' || value.toLowerCase() == 'true') as T;
        case 'json':
          return value as T; // Return JSON string, parse in caller
        default:
          return value as T;
      }
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to get setting: $key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Update setting value
  ///
  /// Demonstrates:
  /// - Settings update
  /// - Upsert pattern (INSERT OR REPLACE)
  Future<void> updateSetting(String key, dynamic value, String valueType) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final valueStr = value.toString();

      await DatabaseService.rawInsert(
        '''
        INSERT OR REPLACE INTO settings (id, key, value, value_type, updated_at)
        VALUES (
          COALESCE((SELECT id FROM settings WHERE key = ?), ?),
          ?, ?, ?, ?
        )
        ''',
        [key, _uuid.v4(), key, valueStr, valueType, timestamp],
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Failed to update setting: $key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
