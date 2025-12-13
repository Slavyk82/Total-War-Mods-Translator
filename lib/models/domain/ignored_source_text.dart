import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'ignored_source_text.g.dart';

/// Represents a source text pattern that should be ignored during translation.
///
/// These texts are typically placeholder or marker texts that should remain unchanged
/// and not be sent to Translation Memory or LLM translation services.
///
/// Users can configure their own ignored texts through the Settings screen.
/// The comparison is case-insensitive.
@JsonSerializable()
class IgnoredSourceText {
  /// Unique identifier (UUID)
  final String id;

  /// The source text to ignore (case-insensitive matching)
  @JsonKey(name: 'source_text')
  final String sourceText;

  /// Whether this ignored text rule is currently enabled
  @JsonKey(name: 'is_enabled')
  @BoolIntConverter()
  final bool isEnabled;

  /// Unix timestamp when the rule was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the rule was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const IgnoredSourceText({
    required this.id,
    required this.sourceText,
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the created date as DateTime
  DateTime get createdAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  /// Returns the updated date as DateTime
  DateTime get updatedAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);

  /// Creates a copy with optional new values
  IgnoredSourceText copyWith({
    String? id,
    String? sourceText,
    bool? isEnabled,
    int? createdAt,
    int? updatedAt,
  }) {
    return IgnoredSourceText(
      id: id ?? this.id,
      sourceText: sourceText ?? this.sourceText,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory IgnoredSourceText.fromJson(Map<String, dynamic> json) =>
      _$IgnoredSourceTextFromJson(json);

  Map<String, dynamic> toJson() => _$IgnoredSourceTextToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IgnoredSourceText &&
        other.id == id &&
        other.sourceText == sourceText &&
        other.isEnabled == isEnabled &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        sourceText,
        isEnabled,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'IgnoredSourceText(id: $id, sourceText: $sourceText, isEnabled: $isEnabled)';
}
