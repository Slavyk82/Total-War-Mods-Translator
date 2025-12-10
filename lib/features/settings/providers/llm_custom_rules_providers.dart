import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/domain/llm_custom_rule.dart';
import '../../../services/llm/llm_custom_rules_service.dart';
import '../../../services/service_locator.dart';

part 'llm_custom_rules_providers.g.dart';

/// Provider for LlmCustomRulesService
@riverpod
LlmCustomRulesService llmCustomRulesService(Ref ref) {
  return ServiceLocator.get<LlmCustomRulesService>();
}

/// Notifier for managing LLM custom rules
@riverpod
class LlmCustomRules extends _$LlmCustomRules {
  @override
  Future<List<LlmCustomRule>> build() async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.getAllRules();
    return result.when(
      ok: (rules) => rules,
      err: (_) => [],
    );
  }

  /// Add a new custom rule
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> addRule(String ruleText) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.addRule(ruleText);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Update an existing rule's text
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> updateRule(String id, String newRuleText) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.updateRule(id, newRuleText);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Delete a rule
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> deleteRule(String id) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.deleteRule(id);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Toggle a rule's enabled status
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> toggleEnabled(String id) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.toggleEnabled(id);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Reorder rules
  ///
  /// [ruleIds] - List of rule IDs in the desired order
  /// Returns (success, errorMessage)
  Future<(bool, String?)> reorderRules(List<String> ruleIds) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.reorderRules(ruleIds);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }
}

/// Provider for the count of enabled rules
@riverpod
Future<int> enabledRulesCount(Ref ref) async {
  final service = ref.read(llmCustomRulesServiceProvider);
  return service.getEnabledCount();
}

/// Provider for checking if there are any enabled rules
@riverpod
Future<bool> hasEnabledRules(Ref ref) async {
  final service = ref.read(llmCustomRulesServiceProvider);
  return service.hasEnabledRules();
}

// ============================================================================
// Project-Specific Rule Providers
// ============================================================================

/// Notifier for managing a project's custom rule
@riverpod
class ProjectCustomRuleNotifier extends _$ProjectCustomRuleNotifier {
  @override
  Future<LlmCustomRule?> build(String projectId) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.getRuleForProject(projectId);
    return result.when(
      ok: (rule) => rule,
      err: (_) => null,
    );
  }

  /// Set or update the project's custom rule
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> setRule(String ruleText) async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.setProjectRule(projectId, ruleText);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Delete the project's custom rule
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> deleteRule() async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.deleteProjectRule(projectId);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Toggle the rule's enabled status
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> toggleEnabled() async {
    final service = ref.read(llmCustomRulesServiceProvider);
    final result = await service.toggleProjectRuleEnabled(projectId);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }
}

/// Provider for checking if a project has an enabled rule
@riverpod
Future<bool> hasProjectRule(Ref ref, String projectId) async {
  final service = ref.read(llmCustomRulesServiceProvider);
  return service.hasEnabledProjectRule(projectId);
}
