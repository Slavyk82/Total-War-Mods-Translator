import 'package:json_annotation/json_annotation.dart';

part 'language.g.dart';

/// Converter for SQLite INTEGER (0/1) to Dart bool
class BoolIntConverter implements JsonConverter<bool, dynamic> {
  const BoolIntConverter();

  @override
  bool fromJson(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  @override
  int toJson(bool value) => value ? 1 : 0;
}

/// Represents a supported language in the TWMT application.
///
/// Languages are reference data that define which languages can be used
/// for translation projects. Each language has a unique code (e.g., 'en', 'de')
/// and can be activated or deactivated.
@JsonSerializable()
class Language {
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

  const Language({
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
  Language copyWith({
    String? id,
    String? code,
    String? name,
    String? nativeName,
    bool? isActive,
  }) {
    return Language(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nativeName: nativeName ?? this.nativeName,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Creates a Language from JSON
  factory Language.fromJson(Map<String, dynamic> json) =>
      _$LanguageFromJson(json);

  /// Converts this Language to JSON
  Map<String, dynamic> toJson() => _$LanguageToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Language &&
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
