import 'package:json_annotation/json_annotation.dart';

part 'rpfm_pack_info.g.dart';

/// Information about a .pack file
@JsonSerializable()
class RpfmPackInfo {
  /// Pack file path
  final String packFilePath;

  /// Pack file name (without path)
  final String fileName;

  /// Pack file size in bytes
  final int sizeBytes;

  /// Total number of files in pack
  final int fileCount;

  /// Number of localization files (.loc)
  final int localizationFileCount;

  /// Pack format version
  final int? formatVersion;

  /// Last modified timestamp
  final DateTime lastModified;

  /// Checksum (optional)
  final String? checksum;

  const RpfmPackInfo({
    required this.packFilePath,
    required this.fileName,
    required this.sizeBytes,
    required this.fileCount,
    required this.localizationFileCount,
    this.formatVersion,
    required this.lastModified,
    this.checksum,
  });

  factory RpfmPackInfo.fromJson(Map<String, dynamic> json) =>
      _$RpfmPackInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RpfmPackInfoToJson(this);

  /// Size in megabytes (formatted)
  double get sizeMB => sizeBytes / (1024 * 1024);

  RpfmPackInfo copyWith({
    String? packFilePath,
    String? fileName,
    int? sizeBytes,
    int? fileCount,
    int? localizationFileCount,
    int? formatVersion,
    DateTime? lastModified,
    String? checksum,
  }) {
    return RpfmPackInfo(
      packFilePath: packFilePath ?? this.packFilePath,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      fileCount: fileCount ?? this.fileCount,
      localizationFileCount:
          localizationFileCount ?? this.localizationFileCount,
      formatVersion: formatVersion ?? this.formatVersion,
      lastModified: lastModified ?? this.lastModified,
      checksum: checksum ?? this.checksum,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RpfmPackInfo &&
          runtimeType == other.runtimeType &&
          packFilePath == other.packFilePath &&
          fileName == other.fileName &&
          sizeBytes == other.sizeBytes &&
          fileCount == other.fileCount &&
          localizationFileCount == other.localizationFileCount &&
          formatVersion == other.formatVersion &&
          lastModified == other.lastModified &&
          checksum == other.checksum;

  @override
  int get hashCode =>
      packFilePath.hashCode ^
      fileName.hashCode ^
      sizeBytes.hashCode ^
      fileCount.hashCode ^
      localizationFileCount.hashCode ^
      (formatVersion?.hashCode ?? 0) ^
      lastModified.hashCode ^
      (checksum?.hashCode ?? 0);

  @override
  String toString() {
    return 'RpfmPackInfo($fileName, files: $fileCount, '
        'locFiles: $localizationFileCount, size: ${sizeMB.toStringAsFixed(2)}MB)';
  }
}
