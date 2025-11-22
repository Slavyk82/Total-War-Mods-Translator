import 'package:json_annotation/json_annotation.dart';

part 'steamcmd_download_result.g.dart';

/// Result of a SteamCMD download operation
@JsonSerializable()
class SteamCmdDownloadResult {
  /// Workshop item ID
  final String workshopId;

  /// App ID (game)
  final int appId;

  /// Local directory where mod was downloaded
  final String downloadPath;

  /// Mod title (if available from metadata)
  final String? modTitle;

  /// Downloaded file size in bytes
  final int sizeBytes;

  /// Download duration in milliseconds
  final int durationMs;

  /// Timestamp of download
  final DateTime timestamp;

  /// Whether this was a fresh download or update
  final bool wasUpdate;

  /// Previous version timestamp (for updates)
  final DateTime? previousVersionTimestamp;

  /// List of downloaded files (relative paths)
  final List<String>? downloadedFiles;

  /// Warnings during download
  final List<String>? warnings;

  const SteamCmdDownloadResult({
    required this.workshopId,
    required this.appId,
    required this.downloadPath,
    this.modTitle,
    required this.sizeBytes,
    required this.durationMs,
    required this.timestamp,
    this.wasUpdate = false,
    this.previousVersionTimestamp,
    this.downloadedFiles,
    this.warnings,
  });

  /// Convert from JSON
  factory SteamCmdDownloadResult.fromJson(Map<String, dynamic> json) =>
      _$SteamCmdDownloadResultFromJson(json);

  /// Convert to JSON
  Map<String, dynamic> toJson() => _$SteamCmdDownloadResultToJson(this);

  /// Create a copy with updated fields
  SteamCmdDownloadResult copyWith({
    String? workshopId,
    int? appId,
    String? downloadPath,
    String? modTitle,
    int? sizeBytes,
    int? durationMs,
    DateTime? timestamp,
    bool? wasUpdate,
    DateTime? previousVersionTimestamp,
    List<String>? downloadedFiles,
    List<String>? warnings,
  }) {
    return SteamCmdDownloadResult(
      workshopId: workshopId ?? this.workshopId,
      appId: appId ?? this.appId,
      downloadPath: downloadPath ?? this.downloadPath,
      modTitle: modTitle ?? this.modTitle,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
      wasUpdate: wasUpdate ?? this.wasUpdate,
      previousVersionTimestamp:
          previousVersionTimestamp ?? this.previousVersionTimestamp,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SteamCmdDownloadResult &&
          runtimeType == other.runtimeType &&
          workshopId == other.workshopId &&
          appId == other.appId &&
          downloadPath == other.downloadPath &&
          modTitle == other.modTitle &&
          sizeBytes == other.sizeBytes &&
          durationMs == other.durationMs &&
          timestamp == other.timestamp &&
          wasUpdate == other.wasUpdate &&
          previousVersionTimestamp == other.previousVersionTimestamp;

  @override
  int get hashCode => Object.hash(
        workshopId,
        appId,
        downloadPath,
        modTitle,
        sizeBytes,
        durationMs,
        timestamp,
        wasUpdate,
        previousVersionTimestamp,
      );

  @override
  String toString() => 'SteamCmdDownloadResult(id: $workshopId, '
      'path: $downloadPath, size: ${sizeBytes ~/ 1024}KB, ${durationMs}ms)';
}
