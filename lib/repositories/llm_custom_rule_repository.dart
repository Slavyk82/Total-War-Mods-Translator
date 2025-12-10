import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/llm_custom_rule.dart';
import 'base_repository.dart';

/// Repository for managing LlmCustomRule entities.
///
/// Provides CRUD operations for custom LLM translation rules,
/// including methods to retrieve only enabled rules and reorder rules.
class LlmCustomRuleRepository extends BaseRepository<LlmCustomRule> {
  @override
  String get tableName => 'llm_custom_rules';

  @override
  LlmCustomRule fromMap(Map<String, dynamic> map) {
    return LlmCustomRule.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(LlmCustomRule entity) {
    return entity.toJson();
  }

  @override
  Future<Result<LlmCustomRule, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('LLM custom rule not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Get all global rules (project_id IS NULL) ordered by sort_order.
  ///
  /// Use [getGlobalRules] or [getRulesForProject] for more specific queries.
  @override
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>> getAll() async {
    return getGlobalRules();
  }

  @override
  Future<Result<LlmCustomRule, TWMTDatabaseException>> insert(
      LlmCustomRule entity) async {
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
  Future<Result<LlmCustomRule, TWMTDatabaseException>> update(
      LlmCustomRule entity) async {
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
            'LLM custom rule not found for update: ${entity.id}');
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
            'LLM custom rule not found for deletion: $id');
      }
    });
  }

  /// Get all enabled global rules (project_id IS NULL), ordered by sort_order.
  ///
  /// Returns [Ok] with list of enabled global rules, [Err] with exception if error occurs.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>>
      getEnabledRules() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_enabled = ? AND project_id IS NULL',
        whereArgs: [1],
        orderBy: 'sort_order ASC, created_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all global rules (project_id IS NULL), ordered by sort_order.
  ///
  /// Returns [Ok] with list of global rules, [Err] with exception if error occurs.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>>
      getGlobalRules() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id IS NULL',
        orderBy: 'sort_order ASC, created_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all rules for a specific project, ordered by sort_order.
  ///
  /// Returns [Ok] with list of project rules, [Err] with exception if error occurs.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>>
      getRulesForProject(String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'sort_order ASC, created_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all enabled rules for a specific project, ordered by sort_order.
  ///
  /// Returns [Ok] with list of enabled project rules, [Err] with exception if error occurs.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>>
      getEnabledRulesForProject(String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_enabled = ? AND project_id = ?',
        whereArgs: [1, projectId],
        orderBy: 'sort_order ASC, created_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get the single rule for a project (mod-specific rules are single per project).
  ///
  /// Returns [Ok] with the rule or null if none exists, [Err] with exception if error occurs.
  Future<Result<LlmCustomRule?, TWMTDatabaseException>>
      getRuleForProject(String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
        limit: 1,
      );

      if (maps.isEmpty) return null;
      return fromMap(maps.first);
    });
  }

  /// Toggle the enabled status of a rule.
  ///
  /// Returns [Ok] with updated rule, [Err] with exception if error occurs.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> toggleEnabled(
      String id) async {
    return executeQuery(() async {
      // Get current rule
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('LLM custom rule not found with id: $id');
      }

      final rule = fromMap(maps.first);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Toggle the enabled status
      final updatedRule = rule.copyWith(
        isEnabled: !rule.isEnabled,
        updatedAt: now,
      );

      // Update in database
      await database.update(
        tableName,
        toMap(updatedRule),
        where: 'id = ?',
        whereArgs: [id],
      );

      return updatedRule;
    });
  }

  /// Reorder rules by updating their sort_order values.
  ///
  /// [ruleIds] - List of rule IDs in the desired order (index = sort_order)
  ///
  /// Returns [Ok] with void if successful, [Err] with exception if error occurs.
  Future<Result<void, TWMTDatabaseException>> reorderRules(
      List<String> ruleIds) async {
    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (var i = 0; i < ruleIds.length; i++) {
        await txn.update(
          tableName,
          {
            'sort_order': i,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [ruleIds[i]],
        );
      }
    });
  }

  /// Get the count of enabled global rules.
  ///
  /// Returns [Ok] with count, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> getEnabledCount() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE is_enabled = 1 AND project_id IS NULL',
      );

      final count = result.firstOrNull?['count'];
      return count is int ? count : 0;
    });
  }

  /// Get the count of all global rules.
  ///
  /// Returns [Ok] with count, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> getTotalCount() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_id IS NULL',
      );

      final count = result.firstOrNull?['count'];
      return count is int ? count : 0;
    });
  }

  /// Get the next available sort_order value for global rules.
  ///
  /// Useful when inserting new rules to place them at the end.
  ///
  /// Returns [Ok] with next sort_order, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> getNextSortOrder() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 as next_order FROM $tableName WHERE project_id IS NULL',
      );

      final nextOrder = result.firstOrNull?['next_order'];
      return nextOrder is int ? nextOrder : 0;
    });
  }

  /// Delete all rules for a specific project.
  ///
  /// Returns [Ok] with number of deleted rules, [Err] with exception if error occurs.
  Future<Result<int, TWMTDatabaseException>> deleteRulesForProject(
      String projectId) async {
    return executeQuery(() async {
      return await database.delete(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
    });
  }
}
