/// Domain model for mod scan cache entry
///
/// Stores the result of RPFM-CLI pack file scanning to avoid
/// re-scanning mods that haven't been modified since last scan.
class ModScanCache {
  /// Internal UUID
  final String id;

  /// Path to the pack file
  final String packFilePath;

  /// File last modified timestamp (Unix epoch seconds from OS)
  final int fileLastModified;

  /// Whether the pack file contains .loc files
  final bool hasLocFiles;

  /// When this cache entry was created/updated
  final int scannedAt;

  const ModScanCache({
    required this.id,
    required this.packFilePath,
    required this.fileLastModified,
    required this.hasLocFiles,
    required this.scannedAt,
  });

  /// Convert from JSON map (database)
  factory ModScanCache.fromJson(Map<String, dynamic> json) {
    return ModScanCache(
      id: json['id'] as String,
      packFilePath: json['pack_file_path'] as String,
      fileLastModified: json['file_last_modified'] as int,
      hasLocFiles: (json['has_loc_files'] as int) == 1,
      scannedAt: json['scanned_at'] as int,
    );
  }

  /// Convert to JSON map (database)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pack_file_path': packFilePath,
      'file_last_modified': fileLastModified,
      'has_loc_files': hasLocFiles ? 1 : 0,
      'scanned_at': scannedAt,
    };
  }

  /// Create copy with updated fields
  ModScanCache copyWith({
    String? id,
    String? packFilePath,
    int? fileLastModified,
    bool? hasLocFiles,
    int? scannedAt,
  }) {
    return ModScanCache(
      id: id ?? this.id,
      packFilePath: packFilePath ?? this.packFilePath,
      fileLastModified: fileLastModified ?? this.fileLastModified,
      hasLocFiles: hasLocFiles ?? this.hasLocFiles,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  /// Check if the cache entry is still valid for a given file modification time
  bool isValidFor(int currentFileLastModified) {
    return fileLastModified == currentFileLastModified;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModScanCache &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          packFilePath == other.packFilePath;

  @override
  int get hashCode => Object.hash(id, packFilePath);

  @override
  String toString() =>
      'ModScanCache(id: $id, packFilePath: $packFilePath, hasLocFiles: $hasLocFiles, fileLastModified: $fileLastModified)';
}

