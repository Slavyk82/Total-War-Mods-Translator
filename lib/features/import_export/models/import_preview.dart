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

  /// sha256 hash of the file content at preview time.
  ///
  /// The import workflow re-reads the file at every stage (preview, conflict
  /// detection, execution). This hash lets the executor verify the file did
  /// not change on disk between the preview the user reviewed and the actual
  /// import. Null for previews created before this field existed.
  @JsonKey(name: 'content_hash')
  final String? contentHash;

  const ImportPreview({
    required this.filePath,
    required this.headers,
    required this.previewRows,
    required this.totalRows,
    required this.fileSize,
    required this.encoding,
    this.suggestedMapping = const {},
    this.contentHash,
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
    String? contentHash,
  }) {
    return ImportPreview(
      filePath: filePath ?? this.filePath,
      headers: headers ?? this.headers,
      previewRows: previewRows ?? this.previewRows,
      totalRows: totalRows ?? this.totalRows,
      fileSize: fileSize ?? this.fileSize,
      encoding: encoding ?? this.encoding,
      suggestedMapping: suggestedMapping ?? this.suggestedMapping,
      contentHash: contentHash ?? this.contentHash,
    );
  }

  factory ImportPreview.fromJson(Map<String, dynamic> json) =>
      _$ImportPreviewFromJson(json);

  Map<String, dynamic> toJson() => _$ImportPreviewToJson(this);
}
