import 'package:json_annotation/json_annotation.dart';

part 'rpfm_extract_result.g.dart';

/// Result of RPFM extraction operation
@JsonSerializable()
class RpfmExtractResult {
  /// Pack file path that was extracted
  final String packFilePath;

  /// Output directory where files were extracted
  final String outputDirectory;

  /// List of extracted file paths
  final List<String> extractedFiles;

  /// Number of localization files extracted
  final int localizationFileCount;

  /// Total size of extracted files in bytes
  final int totalSizeBytes;

  /// Extraction duration in milliseconds
  final int durationMs;

  /// Timestamp of extraction
  final DateTime timestamp;

  /// Any warnings during extraction
  final List<String>? warnings;

  const RpfmExtractResult({
    required this.packFilePath,
    required this.outputDirectory,
    required this.extractedFiles,
    required this.localizationFileCount,
    required this.totalSizeBytes,
    required this.durationMs,
    required this.timestamp,
    this.warnings,
  });

  factory RpfmExtractResult.fromJson(Map<String, dynamic> json) =>
      _$RpfmExtractResultFromJson(json);

  Map<String, dynamic> toJson() => _$RpfmExtractResultToJson(this);

  RpfmExtractResult copyWith({
    String? packFilePath,
    String? outputDirectory,
    List<String>? extractedFiles,
    int? localizationFileCount,
    int? totalSizeBytes,
    int? durationMs,
    DateTime? timestamp,
    List<String>? warnings,
  }) {
    return RpfmExtractResult(
      packFilePath: packFilePath ?? this.packFilePath,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      extractedFiles: extractedFiles ?? this.extractedFiles,
      localizationFileCount:
          localizationFileCount ?? this.localizationFileCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RpfmExtractResult &&
          runtimeType == other.runtimeType &&
          packFilePath == other.packFilePath &&
          outputDirectory == other.outputDirectory &&
          extractedFiles == other.extractedFiles &&
          localizationFileCount == other.localizationFileCount &&
          totalSizeBytes == other.totalSizeBytes &&
          durationMs == other.durationMs &&
          timestamp == other.timestamp &&
          warnings == other.warnings;

  @override
  int get hashCode =>
      packFilePath.hashCode ^
      outputDirectory.hashCode ^
      extractedFiles.hashCode ^
      localizationFileCount.hashCode ^
      totalSizeBytes.hashCode ^
      durationMs.hashCode ^
      timestamp.hashCode ^
      (warnings?.hashCode ?? 0);

  @override
  String toString() {
    return 'RpfmExtractResult(packFile: $packFilePath, '
        'files: ${extractedFiles.length}, locFiles: $localizationFileCount, '
        'size: ${totalSizeBytes ~/ 1024}KB, duration: ${durationMs}ms)';
  }
}
