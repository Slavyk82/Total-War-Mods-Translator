import 'package:json_annotation/json_annotation.dart';

part 'import_preview.g.dart';

/// Preview of data to be imported
@JsonSerializable()
class ImportPreview {
  /// File path being imported
  @JsonKey(name: 'file_path')
  final String filePath;

  /// Detected column headers
  final List<String> headers;

  /// Preview rows (first 10)
  @JsonKey(name: 'preview_rows')
  final List<Map<String, String>> previewRows;

  /// Total row count in file
  @JsonKey(name: 'total_rows')
  final int totalRows;

  /// File size in bytes
  @JsonKey(name: 'file_size')
  final int fileSize;

  /// Detected encoding
  final String encoding;

  /// Auto-detected column mapping suggestions
  @JsonKey(name: 'suggested_mapping')
  final Map<String, String> suggestedMapping;

  const ImportPreview({
    required this.filePath,
    required this.headers,
    required this.previewRows,
    required this.totalRows,
    required this.fileSize,
    required this.encoding,
    this.suggestedMapping = const {},
  });

  /// File size in human-readable format
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  ImportPreview copyWith({
    String? filePath,
    List<String>? headers,
    List<Map<String, String>>? previewRows,
    int? totalRows,
    int? fileSize,
    String? encoding,
    Map<String, String>? suggestedMapping,
  }) {
    return ImportPreview(
      filePath: filePath ?? this.filePath,
      headers: headers ?? this.headers,
      previewRows: previewRows ?? this.previewRows,
      totalRows: totalRows ?? this.totalRows,
      fileSize: fileSize ?? this.fileSize,
      encoding: encoding ?? this.encoding,
      suggestedMapping: suggestedMapping ?? this.suggestedMapping,
    );
  }

  factory ImportPreview.fromJson(Map<String, dynamic> json) =>
      _$ImportPreviewFromJson(json);

  Map<String, dynamic> toJson() => _$ImportPreviewToJson(this);
}
