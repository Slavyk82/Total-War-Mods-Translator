import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'export_history.g.dart';

/// Export format enumeration
enum ExportFormat {
  @JsonValue('pack')
  pack,
  @JsonValue('csv')
  csv,
  @JsonValue('excel')
  excel,
  @JsonValue('tmx')
  tmx,
}

/// Represents a historical record of an export operation.
///
/// Tracks when translations were exported, what format was used,
/// and metadata about the export for auditing and reference purposes.
@JsonSerializable()
class ExportHistory {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the project that was exported
  @JsonKey(name: 'project_id')
  final String projectId;

  /// List of language codes that were exported (JSON array)
  final String languages;

  /// Export format used
  final ExportFormat format;

  /// Whether only validated translations were exported
  @JsonKey(name: 'validated_only')
  final bool validatedOnly;

  /// Path where the file was exported
  @JsonKey(name: 'output_path')
  final String outputPath;

  /// Size of the exported file in bytes
  @JsonKey(name: 'file_size')
  final int? fileSize;

  /// Number of translation entries exported
  @JsonKey(name: 'entry_count')
  final int entryCount;

  /// Unix timestamp when the export was performed
  @JsonKey(name: 'exported_at')
  final int exportedAt;

  const ExportHistory({
    required this.id,
    required this.projectId,
    required this.languages,
    required this.format,
    required this.validatedOnly,
    required this.outputPath,
    this.fileSize,
    required this.entryCount,
    required this.exportedAt,
  });

  /// Returns the list of language codes as a List of String
  List<String> get languagesList {
    try {
      final decoded = jsonDecode(languages);
      if (decoded is List) {
        return decoded.cast<String>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Returns a formatted file size string
  String get fileSizeFormatted {
    if (fileSize == null) return 'Unknown';

    if (fileSize! < 1024) {
      return '$fileSize B';
    } else if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Returns a formatted export date
  DateTime get exportDate => DateTime.fromMillisecondsSinceEpoch(exportedAt * 1000);

  /// Returns format display string
  String get formatDisplay {
    switch (format) {
      case ExportFormat.pack:
        return 'Total War .pack';
      case ExportFormat.csv:
        return 'CSV';
      case ExportFormat.excel:
        return 'Excel';
      case ExportFormat.tmx:
        return 'TMX';
    }
  }

  /// Creates a copy of this ExportHistory with the given fields replaced
  ExportHistory copyWith({
    String? id,
    String? projectId,
    String? languages,
    ExportFormat? format,
    bool? validatedOnly,
    String? outputPath,
    int? fileSize,
    int? entryCount,
    int? exportedAt,
  }) {
    return ExportHistory(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      languages: languages ?? this.languages,
      format: format ?? this.format,
      validatedOnly: validatedOnly ?? this.validatedOnly,
      outputPath: outputPath ?? this.outputPath,
      fileSize: fileSize ?? this.fileSize,
      entryCount: entryCount ?? this.entryCount,
      exportedAt: exportedAt ?? this.exportedAt,
    );
  }

  /// Creates an ExportHistory from JSON
  factory ExportHistory.fromJson(Map<String, dynamic> json) =>
      _$ExportHistoryFromJson(json);

  /// Converts this ExportHistory to JSON
  Map<String, dynamic> toJson() => _$ExportHistoryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExportHistory &&
        other.id == id &&
        other.projectId == projectId &&
        other.languages == languages &&
        other.format == format &&
        other.validatedOnly == validatedOnly &&
        other.outputPath == outputPath &&
        other.fileSize == fileSize &&
        other.entryCount == entryCount &&
        other.exportedAt == exportedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      projectId.hashCode ^
      languages.hashCode ^
      format.hashCode ^
      validatedOnly.hashCode ^
      outputPath.hashCode ^
      fileSize.hashCode ^
      entryCount.hashCode ^
      exportedAt.hashCode;

  @override
  String toString() =>
      'ExportHistory(id: $id, projectId: $projectId, format: $format, entryCount: $entryCount)';
}
