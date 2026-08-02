import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/providers/backup/auto_backup_progress_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  AutoBackupStatus notifier() =>
      container.read(autoBackupStatusProvider.notifier);

  AutoBackupUiState state() => container.read(autoBackupStatusProvider);

  test('starts idle', () {
    expect(state(), isA<AutoBackupIdle>());
  });

  test('report moves to running and carries the progress', () {
    notifier().report(
      const BackupProgress(phase: BackupPhase.compressing, bytesDone: 99),
    );

    final s = state();
    expect(s, isA<AutoBackupRunning>());
    expect((s as AutoBackupRunning).progress.bytesDone, 99);
    expect(s.progress.phase, BackupPhase.compressing);
  });

  test('succeeded moves to done', () {
    notifier().report(
      const BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1),
    );
    notifier().succeeded();

    expect(state(), isA<AutoBackupDone>());
  });

  test('failed moves to error and carries the message', () {
    notifier().failed('disk on fire');

    final s = state();
    expect(s, isA<AutoBackupError>());
    expect((s as AutoBackupError).message, 'disk on fire');
  });

  test('dismiss returns to idle from any state', () {
    notifier().failed('nope');
    notifier().dismiss();
    expect(state(), isA<AutoBackupIdle>());

    notifier().succeeded();
    notifier().dismiss();
    expect(state(), isA<AutoBackupIdle>());
  });
}
