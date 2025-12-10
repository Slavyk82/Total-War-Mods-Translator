import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/repositories/llm_custom_rule_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for managing LLM custom translation rules.
///
/// Custom rules are user-defined prompts that are appended to
/// translation requests sent to LLMs. Rules can be:
/// - **Global**: Apply to all projects (projectId is null)
/// - **Project-specific**: Apply only to a specific mod/project
class LlmCustomRulesService {
  final LlmCustomRuleRepository _repository;
  final LoggingService _logging;
  final Uuid _uuid = const Uuid();

  LlmCustomRulesService({
    required LlmCustomRuleRepository repository,
    LoggingService? logging,
  })  : _repository = repository,
        _logging = logging ?? LoggingService.instance;

  // ============================================================================
  // CRUD Operations
  // ============================================================================

  /// Get all custom rules.
  ///
  /// Returns rules ordered by sort_order.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>> getAllRules() async {
    return _repository.getAll();
  }

  /// Get a rule by ID.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> getRuleById(String id) async {
    return _repository.getById(id);
  }

  /// Get all enabled rules.
  ///
  /// Returns only rules where is_enabled = true, ordered by sort_order.
  Future<Result<List<LlmCustomRule>, TWMTDatabaseException>> getEnabledRules() async {
    return _repository.getEnabledRules();
  }

  /// Add a new custom rule.
  ///
  /// The rule is enabled by default and placed at the end of the list.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> addRule(String ruleText) async {
    final trimmedText = ruleText.trim();
    if (trimmedText.isEmpty) {
      return Err(TWMTDatabaseException('Rule text cannot be empty'));
    }

    // Get next sort order
    final sortOrderResult = await _repository.getNextSortOrder();
    final sortOrder = sortOrderResult.when(
      ok: (order) => order,
      err: (_) => 0,
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rule = LlmCustomRule(
      id: _uuid.v4(),
      ruleText: trimmedText,
      isEnabled: true,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );

    _logging.debug('Adding custom rule', {'id': rule.id, 'textPreview': rule.getPreview()});

    return _repository.insert(rule);
  }

  /// Update an existing rule's text.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> updateRule(
    String id,
    String newRuleText,
  ) async {
    final trimmedText = newRuleText.trim();
    if (trimmedText.isEmpty) {
      return Err(TWMTDatabaseException('Rule text cannot be empty'));
    }

    // Get existing rule
    final existingResult = await _repository.getById(id);
    return existingResult.when(
      ok: (existing) async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final updated = existing.copyWith(
          ruleText: trimmedText,
          updatedAt: now,
        );

        _logging.debug('Updating custom rule', {'id': id, 'textPreview': updated.getPreview()});

        return _repository.update(updated);
      },
      err: (error) => Err(error),
    );
  }

  /// Delete a rule.
  Future<Result<void, TWMTDatabaseException>> deleteRule(String id) async {
    _logging.debug('Deleting custom rule', {'id': id});
    return _repository.delete(id);
  }

  /// Toggle a rule's enabled status.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> toggleEnabled(String id) async {
    _logging.debug('Toggling custom rule enabled status', {'id': id});
    return _repository.toggleEnabled(id);
  }

  /// Reorder rules.
  ///
  /// [ruleIds] - List of rule IDs in the desired order (index = sort_order)
  Future<Result<void, TWMTDatabaseException>> reorderRules(List<String> ruleIds) async {
    _logging.debug('Reordering custom rules', {'count': ruleIds.length});
    return _repository.reorderRules(ruleIds);
  }

  // ============================================================================
  // Project-Specific Rules (Mod Rules)
  // ============================================================================

  /// Get the rule for a specific project/mod.
  ///
  /// Returns null if no rule exists for the project.
  Future<Result<LlmCustomRule?, TWMTDatabaseException>> getRuleForProject(
      String projectId) async {
    return _repository.getRuleForProject(projectId);
  }

  /// Add or update a project-specific rule.
  ///
  /// If a rule already exists for the project, it will be updated.
  /// Otherwise, a new rule will be created.
  Future<Result<LlmCustomRule, TWMTDatabaseException>> setProjectRule(
    String projectId,
    String ruleText,
  ) async {
    final trimmedText = ruleText.trim();
    if (trimmedText.isEmpty) {
      return Err(TWMTDatabaseException('Rule text cannot be empty'));
    }

    // Check if a rule already exists for this project
    final existingResult = await _repository.getRuleForProject(projectId);
    return existingResult.when(
      ok: (existing) async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        if (existing != null) {
          // Update existing rule
          final updated = existing.copyWith(
            ruleText: trimmedText,
            updatedAt: now,
          );
          _logging.debug('Updating project rule', {
            'projectId': projectId,
            'ruleId': existing.id,
          });
          return _repository.update(updated);
        } else {
          // Create new rule
          final rule = LlmCustomRule(
            id: _uuid.v4(),
            ruleText: trimmedText,
            isEnabled: true,
            sortOrder: 0,
            projectId: projectId,
            createdAt: now,
            updatedAt: now,
          );
          _logging.debug('Creating project rule', {
            'projectId': projectId,
            'ruleId': rule.id,
          });
          return _repository.insert(rule);
        }
      },
      err: (error) => Err(error),
    );
  }

  /// Delete the rule for a specific project.
  Future<Result<void, TWMTDatabaseException>> deleteProjectRule(
      String projectId) async {
    _logging.debug('Deleting project rule', {'projectId': projectId});
    final result = await _repository.deleteRulesForProject(projectId);
    return result.when(
      ok: (_) => Ok(null),
      err: (error) => Err(error),
    );
  }

  /// Toggle the enabled status of a project's rule.
  Future<Result<LlmCustomRule?, TWMTDatabaseException>> toggleProjectRuleEnabled(
      String projectId) async {
    final existingResult = await _repository.getRuleForProject(projectId);
    return existingResult.when(
      ok: (existing) async {
        if (existing == null) {
          return Ok(null);
        }
        return _repository.toggleEnabled(existing.id);
      },
      err: (error) => Err(error),
    );
  }

  // ============================================================================
  // Prompt Building
  // ============================================================================

  /// Get combined text from all enabled global rules.
  ///
  /// Returns all enabled global rules joined with newlines, suitable for
  /// appending to translation prompts. Returns empty string if no rules.
  Future<String> getCombinedRulesText() async {
    final result = await _repository.getEnabledRules();
    return result.when(
      ok: (rules) {
        if (rules.isEmpty) return '';
        return rules.map((r) => r.ruleText).join('\n');
      },
      err: (error) {
        _logging.warning('Failed to get enabled rules for prompt', {'error': error.message});
        return '';
      },
    );
  }

  /// Get combined text from all enabled rules for a specific project.
  ///
  /// This includes both global rules AND project-specific rules.
  /// Global rules come first, followed by project-specific rules.
  Future<String> getCombinedRulesTextForProject(String projectId) async {
    final globalResult = await _repository.getEnabledRules();
    final projectResult = await _repository.getEnabledRulesForProject(projectId);

    final globalRules = globalResult.when(
      ok: (rules) => rules,
      err: (_) => <LlmCustomRule>[],
    );

    final projectRules = projectResult.when(
      ok: (rules) => rules,
      err: (_) => <LlmCustomRule>[],
    );

    final allRules = [...globalRules, ...projectRules];
    if (allRules.isEmpty) return '';
    return allRules.map((r) => r.ruleText).join('\n');
  }

  /// Check if there are any enabled global rules.
  Future<bool> hasEnabledRules() async {
    final result = await _repository.getEnabledCount();
    return result.when(
      ok: (count) => count > 0,
      err: (_) => false,
    );
  }

  /// Check if a project has an enabled rule.
  Future<bool> hasEnabledProjectRule(String projectId) async {
    final result = await _repository.getRuleForProject(projectId);
    return result.when(
      ok: (rule) => rule?.isEnabled ?? false,
      err: (_) => false,
    );
  }

  // ============================================================================
  // Statistics
  // ============================================================================

  /// Get the count of enabled rules.
  Future<int> getEnabledCount() async {
    final result = await _repository.getEnabledCount();
    return result.when(
      ok: (count) => count,
      err: (_) => 0,
    );
  }

  /// Get the total count of all rules.
  Future<int> getTotalCount() async {
    final result = await _repository.getTotalCount();
    return result.when(
      ok: (count) => count,
      err: (_) => 0,
    );
  }
}
