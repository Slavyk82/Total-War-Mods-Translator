/// Which stage of a database backup is currently running.
///
/// Deliberately has no notion of a total or a fraction: neither stage can
/// produce an honest denominator. `VACUUM INTO` defragments, so its output is
/// smaller than the source database; compression progress is only observable
/// as compressed bytes written, whose total is unknown until the archive is
/// finished. See the design spec for why an estimated percentage was rejected.
enum BackupPhase {
  /// `VACUUM INTO` is writing a consistent snapshot of the database.
  snapshot,

  /// The snapshot is being compressed into the zip archive.
  compressing,
}

/// A single progress observation of a running backup.
class BackupProgress {
  final BackupPhase phase;

  /// Bytes observed on disk so far for [phase]. Monotonically non-decreasing
  /// within a phase, and reset when the phase changes.
  final int bytesDone;

  const BackupProgress({required this.phase, required this.bytesDone});

  /// [bytesDone] rendered for display, e.g. `1.7 GB`.
  String get formattedBytes {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytesDone < kb) return '$bytesDone B';
    if (bytesDone < mb) return '${(bytesDone / kb).toStringAsFixed(1)} KB';
    if (bytesDone < gb) return '${(bytesDone / mb).toStringAsFixed(1)} MB';
    return '${(bytesDone / gb).toStringAsFixed(1)} GB';
  }

  @override
  bool operator ==(Object other) =>
      other is BackupProgress &&
      other.phase == phase &&
      other.bytesDone == bytesDone;

  @override
  int get hashCode => Object.hash(phase, bytesDone);

  @override
  String toString() => 'BackupProgress(${phase.name}, $bytesDone)';
}
