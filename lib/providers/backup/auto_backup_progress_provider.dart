import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/backup/backup_progress.dart';

part 'auto_backup_progress_provider.g.dart';

/// What the automatic-backup card should show.
sealed class AutoBackupUiState {
  const AutoBackupUiState();
}

/// Nothing to show.
class AutoBackupIdle extends AutoBackupUiState {
  const AutoBackupIdle();
}

/// A backup is running.
class AutoBackupRunning extends AutoBackupUiState {
  final BackupProgress progress;
  const AutoBackupRunning(this.progress);
}

/// The backup finished. The card holds this briefly, then dismisses itself.
class AutoBackupDone extends AutoBackupUiState {
  const AutoBackupDone();
}

/// The backup failed. [message] is the English service message, shown as
/// diagnostic detail under a localized title. This state is persistent: only
/// the user dismisses it.
class AutoBackupError extends AutoBackupUiState {
  final String message;
  const AutoBackupError(this.message);
}

/// App-global state of the startup auto-backup.
///
/// Kept alive because the backup outlives any single screen, and the card that
/// renders it lives in the app-level overlay stack rather than in a route.
///
/// Holds no timer: the brief "Done" hold before the card fades out is a
/// presentation concern and belongs to the widget.
@Riverpod(keepAlive: true)
class AutoBackupStatus extends _$AutoBackupStatus {
  @override
  AutoBackupUiState build() => const AutoBackupIdle();

  /// Report an observation from a running backup.
  void report(BackupProgress progress) =>
      state = AutoBackupRunning(progress);

  /// The backup completed successfully.
  void succeeded() => state = const AutoBackupDone();

  /// The backup failed with [message] (English, from the service layer).
  void failed(String message) => state = AutoBackupError(message);

  /// Return to idle — the card disappears.
  void dismiss() => state = const AutoBackupIdle();
}
