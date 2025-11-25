import 'package:json_annotation/json_annotation.dart';

/// Converter for boolean values to SQLite-compatible integers
///
/// SQLite only supports num, String and Uint8List types.
/// This converter maps boolean values to integers (0/1).
///
/// Handles flexible input types (bool, int, String) for robust deserialization.
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

/// Alias for backward compatibility with older name
typedef BoolToIntConverter = BoolIntConverter;

