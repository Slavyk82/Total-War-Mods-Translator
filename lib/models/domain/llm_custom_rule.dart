import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'llm_custom_rule.g.dart';

/// Represents a custom rule for LLM translation prompts.
///
/// Custom rules allow users to add specific instructions that will be included
/// in the LLM translation prompts. These can be used to enforce specific
/// translation conventions, terminology preferences, or style guidelines.
///
/// Rules can be either:
/// - **Global**: Apply to all projects (projectId is null)
/// - **Project-specific**: Apply only to a specific mod/project (projectId is set)
@JsonSerializable()
class LlmCustomRule {
  /// Unique identifier (UUID)
  final String id;

  /// The rule text to be included in the LLM prompt
  @JsonKey(name: 'rule_text')
  final String ruleText;

  /// Whether this rule is currently enabled
  @JsonKey(name: 'is_enabled')
  @BoolIntConverter()
  final bool isEnabled;

  /// Sort order for displaying/applying rules (lower = higher priority)
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  /// Project ID this rule is associated with (null for global rules)
  @JsonKey(name: 'project_id')
  final String? projectId;

  /// Unix timestamp when the rule was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the rule was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const LlmCustomRule({
    required this.id,
    required this.ruleText,
    this.isEnabled = true,
    this.sortOrder = 0,
    this.projectId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if this is a global rule (not project-specific)
  bool get isGlobal => projectId == null;

  /// Returns the created date as DateTime
  DateTime get createdAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  /// Returns the updated date as DateTime
  DateTime get updatedAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);

  /// Returns a preview of the rule text (truncated if too long)
  String getPreview([int maxLength = 50]) {
    if (ruleText.length <= maxLength) {
      return ruleText;
    }
    return '${ruleText.substring(0, maxLength)}...';
  }

  /// Creates a copy with optional new values
  LlmCustomRule copyWith({
    String? id,
    String? ruleText,
    bool? isEnabled,
    int? sortOrder,
    String? projectId,
    bool clearProjectId = false,
    int? createdAt,
    int? updatedAt,
  }) {
    return LlmCustomRule(
      id: id ?? this.id,
      ruleText: ruleText ?? this.ruleText,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory LlmCustomRule.fromJson(Map<String, dynamic> json) =>
      _$LlmCustomRuleFromJson(json);

  Map<String, dynamic> toJson() => _$LlmCustomRuleToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LlmCustomRule &&
        other.id == id &&
        other.ruleText == ruleText &&
        other.isEnabled == isEnabled &&
        other.sortOrder == sortOrder &&
        other.projectId == projectId &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        ruleText,
        isEnabled,
        sortOrder,
        projectId,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'LlmCustomRule(id: $id, ruleText: ${getPreview(30)}, isEnabled: $isEnabled, sortOrder: $sortOrder)';
}
