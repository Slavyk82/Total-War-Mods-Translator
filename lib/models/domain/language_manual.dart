import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'language_manual.g.dart';

/// Represents a supported language in the TWMT application.
///
/// Languages are reference data that define which languages can be used
/// for translation projects. Each language has a unique code (e.g., 'en', 'de')
/// and can be activated or deactivated.
@JsonSerializable()
class LanguageManual {
  /// Unique identifier (UUID)
  final String id;

  /// ISO 639-1 language code (e.g., 'en', 'de', 'zh')
  final String code;

  /// Language name in English (e.g., 'German', 'English')
  final String name;

  /// Language name in its native form (e.g., 'Deutsch', 'English', '中文')
  @JsonKey(name: 'native_name')
  final String nativeName;

  /// Whether this language is currently active/enabled
  @JsonKey(name: 'is_active')
  @BoolIntConverter()
  final bool isActive;

  const LanguageManual({
    required this.id,
    required this.code,
    required this.name,
    required this.nativeName,
    this.isActive = true,
  });

  /// Returns true if the language is currently active
  bool get isEnabled => isActive;

  /// Returns a display name that includes both English and native names
  /// Example: "German (Deutsch)"
  String get displayName => '$name ($nativeName)';

  /// Creates a copy of this Language with the given fields replaced
  LanguageManual copyWith({
    String? id,
    String? code,
    String? name,
    String? nativeName,
    bool? isActive,
  }) {
    return LanguageManual(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nativeName: nativeName ?? this.nativeName,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Creates a Language from JSON
  factory LanguageManual.fromJson(Map<String, dynamic> json) =>
      _$LanguageManualFromJson(json);

  /// Converts this Language to JSON
  Map<String, dynamic> toJson() => _$LanguageManualToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LanguageManual &&
        other.id == id &&
        other.code == code &&
        other.name == name &&
        other.nativeName == nativeName &&
        other.isActive == isActive;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      code.hashCode ^
      name.hashCode ^
      nativeName.hashCode ^
      isActive.hashCode;

  @override
  String toString() {
    return 'Language(id: $id, code: $code, name: $name, nativeName: $nativeName, isActive: $isActive)';
  }
}
