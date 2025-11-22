import 'package:json_annotation/json_annotation.dart';

part 'setting.g.dart';

/// Setting value type enumeration
enum SettingValueType {
  @JsonValue('string')
  string,
  @JsonValue('integer')
  integer,
  @JsonValue('boolean')
  boolean,
  @JsonValue('json')
  json,
}

/// Represents a configuration setting in the TWMT application.
///
/// Settings store user preferences and application configuration.
/// Values are stored as strings but have a type indicator to enable
/// proper parsing and validation.
@JsonSerializable()
class Setting {
  /// Unique identifier (UUID)
  final String id;

  /// Setting key (unique identifier for the setting)
  final String key;

  /// Setting value stored as string
  final String value;

  /// Type of the value for proper parsing
  @JsonKey(name: 'value_type')
  final SettingValueType valueType;

  /// Unix timestamp when the setting was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const Setting({
    required this.id,
    required this.key,
    required this.value,
    this.valueType = SettingValueType.string,
    required this.updatedAt,
  });

  /// Returns true if the value type is string
  bool get isString => valueType == SettingValueType.string;

  /// Returns true if the value type is integer
  bool get isInteger => valueType == SettingValueType.integer;

  /// Returns true if the value type is boolean
  bool get isBoolean => valueType == SettingValueType.boolean;

  /// Returns true if the value type is JSON
  bool get isJson => valueType == SettingValueType.json;

  /// Parses the value as an integer (returns null if parsing fails)
  int? get intValue {
    if (!isInteger) return null;
    return int.tryParse(value);
  }

  /// Parses the value as a boolean (returns null if parsing fails)
  bool? get boolValue {
    if (!isBoolean) return null;
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }

  /// Returns the value as a string (always available)
  String get stringValue => value;

  /// Returns the value type as a display string
  String get valueTypeDisplay {
    switch (valueType) {
      case SettingValueType.string:
        return 'Text';
      case SettingValueType.integer:
        return 'Number';
      case SettingValueType.boolean:
        return 'Yes/No';
      case SettingValueType.json:
        return 'JSON';
    }
  }

  /// Returns a formatted display of the setting
  String get displayValue {
    switch (valueType) {
      case SettingValueType.boolean:
        return boolValue == true ? 'Yes' : 'No';
      case SettingValueType.integer:
        return intValue?.toString() ?? value;
      case SettingValueType.string:
      case SettingValueType.json:
        return value;
    }
  }

  /// Returns a preview of the value (truncated if too long)
  String getValuePreview([int maxLength = 50]) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  /// Returns the updated date as DateTime
  DateTime get updatedAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);

  /// Creates a Setting with a string value
  factory Setting.string({
    required String id,
    required String key,
    required String value,
    required int updatedAt,
  }) =>
      Setting(
        id: id,
        key: key,
        value: value,
        valueType: SettingValueType.string,
        updatedAt: updatedAt,
      );

  /// Creates a Setting with an integer value
  factory Setting.integer({
    required String id,
    required String key,
    required int value,
    required int updatedAt,
  }) =>
      Setting(
        id: id,
        key: key,
        value: value.toString(),
        valueType: SettingValueType.integer,
        updatedAt: updatedAt,
      );

  /// Creates a Setting with a boolean value
  factory Setting.boolean({
    required String id,
    required String key,
    required bool value,
    required int updatedAt,
  }) =>
      Setting(
        id: id,
        key: key,
        value: value ? 'true' : 'false',
        valueType: SettingValueType.boolean,
        updatedAt: updatedAt,
      );

  /// Creates a Setting with a JSON value
  factory Setting.json({
    required String id,
    required String key,
    required String value,
    required int updatedAt,
  }) =>
      Setting(
        id: id,
        key: key,
        value: value,
        valueType: SettingValueType.json,
        updatedAt: updatedAt,
      );

  /// Creates a copy with optional new values
  Setting copyWith({
    String? id,
    String? key,
    String? value,
    SettingValueType? valueType,
    int? updatedAt,
  }) {
    return Setting(
      id: id ?? this.id,
      key: key ?? this.key,
      value: value ?? this.value,
      valueType: valueType ?? this.valueType,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Setting.fromJson(Map<String, dynamic> json) =>
      _$SettingFromJson(json);

  Map<String, dynamic> toJson() => _$SettingToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Setting &&
        other.id == id &&
        other.key == key &&
        other.value == value &&
        other.valueType == valueType &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      key.hashCode ^
      value.hashCode ^
      valueType.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Setting(id: $id, key: $key, value: $value, valueType: $valueType, updatedAt: $updatedAt)';
  }
}
