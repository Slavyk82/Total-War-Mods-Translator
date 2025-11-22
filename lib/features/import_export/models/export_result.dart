import 'package:json_annotation/json_annotation.dart';

part 'export_result.g.dart';

/// Result of an export operation
@JsonSerializable()
class ExportResult {
  /// Path to exported file
  @JsonKey(name: 'file_path')
  final String filePath;

  /// Number of rows exported
  @JsonKey(name: 'row_count')
  final int rowCount;

  /// File size in bytes
  @JsonKey(name: 'file_size')
  final int fileSize;

  /// Duration of export operation in milliseconds
  @JsonKey(name: 'duration_ms')
  final int durationMs;

  /// Whether export was successful
  @JsonKey(name: 'is_success')
  final bool isSuccess;

  /// Error message (if any)
  @JsonKey(name: 'error_message')
  final String? errorMessage;

  const ExportResult({
    required this.filePath,
    required this.rowCount,
    required this.fileSize,
    required this.durationMs,
    this.isSuccess = true,
    this.errorMessage,
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

  /// Duration in human-readable format
  String get durationFormatted {
    if (durationMs < 1000) return '${durationMs}ms';
    final seconds = durationMs / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}m';
  }

  ExportResult copyWith({
    String? filePath,
    int? rowCount,
    int? fileSize,
    int? durationMs,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return ExportResult(
      filePath: filePath ?? this.filePath,
      rowCount: rowCount ?? this.rowCount,
      fileSize: fileSize ?? this.fileSize,
      durationMs: durationMs ?? this.durationMs,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory ExportResult.fromJson(Map<String, dynamic> json) =>
      _$ExportResultFromJson(json);

  Map<String, dynamic> toJson() => _$ExportResultToJson(this);
}

/// Preview of data to be exported
@JsonSerializable()
class ExportPreview {
  /// Preview rows (first 10)
  @JsonKey(name: 'preview_rows')
  final List<Map<String, String>> previewRows;

  /// Total row count
  @JsonKey(name: 'total_rows')
  final int totalRows;

  /// Estimated file size in bytes
  @JsonKey(name: 'estimated_size')
  final int estimatedSize;

  /// Column headers
  final List<String> headers;

  const ExportPreview({
    required this.previewRows,
    required this.totalRows,
    required this.estimatedSize,
    required this.headers,
  });

  /// Estimated file size in human-readable format
  String get estimatedSizeFormatted {
    if (estimatedSize < 1024) return '$estimatedSize B';
    if (estimatedSize < 1024 * 1024) {
      return '${(estimatedSize / 1024).toStringAsFixed(1)} KB';
    }
    if (estimatedSize < 1024 * 1024 * 1024) {
      return '${(estimatedSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(estimatedSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  ExportPreview copyWith({
    List<Map<String, String>>? previewRows,
    int? totalRows,
    int? estimatedSize,
    List<String>? headers,
  }) {
    return ExportPreview(
      previewRows: previewRows ?? this.previewRows,
      totalRows: totalRows ?? this.totalRows,
      estimatedSize: estimatedSize ?? this.estimatedSize,
      headers: headers ?? this.headers,
    );
  }

  factory ExportPreview.fromJson(Map<String, dynamic> json) =>
      _$ExportPreviewFromJson(json);

  Map<String, dynamic> toJson() => _$ExportPreviewToJson(this);
}
