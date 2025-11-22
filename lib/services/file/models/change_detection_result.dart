/// Result of a change detection operation.
///
/// Contains information about whether a file has changed, including
/// hash comparisons, detection timestamp, and affected files.
class ChangeDetectionResult {
  /// Whether the file has changed since the previous version
  final bool hasChanged;

  /// Previous file hash (null if no previous version exists)
  final String? oldHash;

  /// New/current file hash
  final String? newHash;

  /// When the change was detected
  final DateTime detectedAt;

  /// List of affected file paths within the mod (e.g., localization files)
  final List<String> affectedFiles;

  const ChangeDetectionResult({
    required this.hasChanged,
    this.oldHash,
    this.newHash,
    required this.detectedAt,
    this.affectedFiles = const [],
  });

  /// Create a result indicating no change
  factory ChangeDetectionResult.noChange({
    required String hash,
    required DateTime detectedAt,
  }) {
    return ChangeDetectionResult(
      hasChanged: false,
      oldHash: hash,
      newHash: hash,
      detectedAt: detectedAt,
      affectedFiles: const [],
    );
  }

  /// Create a result indicating a change was detected
  factory ChangeDetectionResult.changed({
    required String oldHash,
    required String newHash,
    required DateTime detectedAt,
    List<String> affectedFiles = const [],
  }) {
    return ChangeDetectionResult(
      hasChanged: true,
      oldHash: oldHash,
      newHash: newHash,
      detectedAt: detectedAt,
      affectedFiles: affectedFiles,
    );
  }

  /// Create a result for a new file (no previous version)
  factory ChangeDetectionResult.newFile({
    required String hash,
    required DateTime detectedAt,
    List<String> affectedFiles = const [],
  }) {
    return ChangeDetectionResult(
      hasChanged: true,
      oldHash: null,
      newHash: hash,
      detectedAt: detectedAt,
      affectedFiles: affectedFiles,
    );
  }

  /// Number of affected files
  int get affectedFileCount => affectedFiles.length;

  /// Whether this is a new file (no previous hash)
  bool get isNewFile => oldHash == null && hasChanged;

  @override
  String toString() {
    if (hasChanged) {
      return 'ChangeDetectionResult(hasChanged: true, '
          'oldHash: $oldHash, newHash: $newHash, '
          'affectedFiles: ${affectedFiles.length}, '
          'detectedAt: $detectedAt)';
    } else {
      return 'ChangeDetectionResult(hasChanged: false, '
          'hash: $newHash, detectedAt: $detectedAt)';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChangeDetectionResult &&
        other.hasChanged == hasChanged &&
        other.oldHash == oldHash &&
        other.newHash == newHash &&
        other.detectedAt == detectedAt &&
        _listEquals(other.affectedFiles, affectedFiles);
  }

  @override
  int get hashCode =>
      hasChanged.hashCode ^
      oldHash.hashCode ^
      newHash.hashCode ^
      detectedAt.hashCode ^
      affectedFiles.hashCode;

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
