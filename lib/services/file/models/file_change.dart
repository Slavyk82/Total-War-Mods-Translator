/// Type of change detected in a file
enum FileChangeType {
  /// File was added in the new version
  added,

  /// File was modified (content changed)
  modified,

  /// File was deleted in the new version
  deleted,
}

/// Represents a detected change in a specific file.
///
/// Used to track individual file changes between mod versions,
/// including the type of change and hash information.
class FileChange {
  /// Path to the file that changed
  final String filePath;

  /// Type of change detected
  final FileChangeType changeType;

  /// Previous file hash (null for added files)
  final String? oldHash;

  /// New file hash (null for deleted files)
  final String? newHash;

  /// When the change was detected
  final DateTime detectedAt;

  const FileChange({
    required this.filePath,
    required this.changeType,
    this.oldHash,
    this.newHash,
    required this.detectedAt,
  });

  /// Create a change representing a newly added file
  factory FileChange.added({
    required String filePath,
    required String newHash,
    required DateTime detectedAt,
  }) {
    return FileChange(
      filePath: filePath,
      changeType: FileChangeType.added,
      oldHash: null,
      newHash: newHash,
      detectedAt: detectedAt,
    );
  }

  /// Create a change representing a modified file
  factory FileChange.modified({
    required String filePath,
    required String oldHash,
    required String newHash,
    required DateTime detectedAt,
  }) {
    return FileChange(
      filePath: filePath,
      changeType: FileChangeType.modified,
      oldHash: oldHash,
      newHash: newHash,
      detectedAt: detectedAt,
    );
  }

  /// Create a change representing a deleted file
  factory FileChange.deleted({
    required String filePath,
    required String oldHash,
    required DateTime detectedAt,
  }) {
    return FileChange(
      filePath: filePath,
      changeType: FileChangeType.deleted,
      oldHash: oldHash,
      newHash: null,
      detectedAt: detectedAt,
    );
  }

  /// Whether this is a newly added file
  bool get isAdded => changeType == FileChangeType.added;

  /// Whether this file was modified
  bool get isModified => changeType == FileChangeType.modified;

  /// Whether this file was deleted
  bool get isDeleted => changeType == FileChangeType.deleted;

  /// Get a human-readable description of the change
  String get changeDescription {
    return switch (changeType) {
      FileChangeType.added => 'Added',
      FileChangeType.modified => 'Modified',
      FileChangeType.deleted => 'Deleted',
    };
  }

  @override
  String toString() {
    return 'FileChange($changeDescription: $filePath, '
        'oldHash: $oldHash, newHash: $newHash, '
        'detectedAt: $detectedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileChange &&
        other.filePath == filePath &&
        other.changeType == changeType &&
        other.oldHash == oldHash &&
        other.newHash == newHash &&
        other.detectedAt == detectedAt;
  }

  @override
  int get hashCode =>
      filePath.hashCode ^
      changeType.hashCode ^
      oldHash.hashCode ^
      newHash.hashCode ^
      detectedAt.hashCode;
}
