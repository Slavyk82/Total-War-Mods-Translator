import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../services/backup/database_backup_service.dart';
import '../../../services/shared/logging_service.dart';

part 'backup_providers.g.dart';

/// Result of a backup operation.
class BackupResult {
  final bool success;
  final String message;
  final String? filePath;
  final bool requiresRestart;

  const BackupResult({
    required this.success,
    required this.message,
    this.filePath,
    this.requiresRestart = false,
  });

  factory BackupResult.exportSuccess(String filePath) {
    return BackupResult(
      success: true,
      message: 'Backup created successfully',
      filePath: filePath,
    );
  }

  factory BackupResult.importSuccess() {
    return const BackupResult(
      success: true,
      message: 'Database restored successfully. '
          'Some changes may require restarting the application.',
    );
  }

  factory BackupResult.error(String error, {bool requiresRestart = false}) {
    return BackupResult(
      success: false,
      message: error,
      requiresRestart: requiresRestart,
    );
  }
}

/// State for backup operations.
class BackupState {
  final bool isExporting;
  final bool isImporting;
  final String? progressMessage;
  final BackupResult? lastResult;

  const BackupState({
    this.isExporting = false,
    this.isImporting = false,
    this.progressMessage,
    this.lastResult,
  });

  bool get isOperationInProgress => isExporting || isImporting;

  BackupState copyWith({
    bool? isExporting,
    bool? isImporting,
    String? progressMessage,
    BackupResult? lastResult,
    bool clearProgress = false,
    bool clearResult = false,
  }) {
    return BackupState(
      isExporting: isExporting ?? this.isExporting,
      isImporting: isImporting ?? this.isImporting,
      progressMessage:
          clearProgress ? null : (progressMessage ?? this.progressMessage),
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
    );
  }
}

/// Notifier for backup operations.
@riverpod
class BackupStateNotifier extends _$BackupStateNotifier {
  late final DatabaseBackupService _backupService;
  late final LoggingService _logging;

  @override
  BackupState build() {
    _backupService = DatabaseBackupService();
    _logging = LoggingService.instance;
    return const BackupState();
  }

  /// Export the database to a backup file.
  Future<void> exportBackup(String destinationPath) async {
    if (state.isOperationInProgress) return;

    state = state.copyWith(
      isExporting: true,
      progressMessage: 'Creating backup...',
      clearResult: true,
    );

    try {
      _logging.info('Starting backup export', {'destination': destinationPath});

      final result = await _backupService.createBackup(destinationPath);

      result.when(
        ok: (filePath) {
          _logging.info('Backup export completed', {'path': filePath});
          state = state.copyWith(
            isExporting: false,
            clearProgress: true,
            lastResult: BackupResult.exportSuccess(filePath),
          );
        },
        err: (error) {
          _logging.error('Backup export failed', error);
          state = state.copyWith(
            isExporting: false,
            clearProgress: true,
            lastResult: BackupResult.error(error.message),
          );
        },
      );
    } catch (e, stackTrace) {
      _logging.error('Unexpected error during backup export', e, stackTrace);
      state = state.copyWith(
        isExporting: false,
        clearProgress: true,
        lastResult: BackupResult.error('Unexpected error: $e'),
      );
    }
  }

  /// Import a backup file and restore the database.
  Future<bool> importBackup(String sourcePath) async {
    if (state.isOperationInProgress) return false;

    state = state.copyWith(
      isImporting: true,
      progressMessage: 'Validating backup...',
      clearResult: true,
    );

    try {
      _logging.info('Starting backup import', {'source': sourcePath});

      // Validate first
      state = state.copyWith(progressMessage: 'Restoring database...');

      final result = await _backupService.restoreBackup(sourcePath);

      return result.when(
        ok: (_) {
          _logging.info('Backup import completed successfully');
          state = state.copyWith(
            isImporting: false,
            clearProgress: true,
            lastResult: BackupResult.importSuccess(),
          );
          return true;
        },
        err: (error) {
          _logging.error('Backup import failed', error);
          state = state.copyWith(
            isImporting: false,
            clearProgress: true,
            lastResult: BackupResult.error(
              error.message,
              requiresRestart: error.requiresRestart,
            ),
          );
          return false;
        },
      );
    } catch (e, stackTrace) {
      _logging.error('Unexpected error during backup import', e, stackTrace);
      state = state.copyWith(
        isImporting: false,
        clearProgress: true,
        lastResult: BackupResult.error('Unexpected error: $e'),
      );
      return false;
    }
  }

  /// Clear the last result message.
  void clearResult() {
    state = state.copyWith(clearResult: true);
  }
}
