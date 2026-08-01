import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';

void main() {
  BackupProgress progress(int bytes) => BackupProgress(
        phase: BackupPhase.compressing,
        bytesDone: bytes,
      );

  test('formats bytes below 1 KB as plain bytes', () {
    expect(progress(0).formattedBytes, '0 B');
    expect(progress(512).formattedBytes, '512 B');
  });

  test('formats kilobytes, megabytes and gigabytes with one decimal', () {
    expect(progress(1536).formattedBytes, '1.5 KB');
    expect(progress(5 * 1024 * 1024).formattedBytes, '5.0 MB');
    expect(progress(1782579200).formattedBytes, '1.7 GB');
  });

  test('carries its phase', () {
    const p = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1);
    expect(p.phase, BackupPhase.snapshot);
  });

  test('is equatable by value so identical events can be de-duplicated', () {
    const a = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 10);
    const b = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 10);
    const c = BackupProgress(phase: BackupPhase.compressing, bytesDone: 10);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
