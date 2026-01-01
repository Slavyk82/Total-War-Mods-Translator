import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/service_locator.dart';
import '../services/shared/logging_service.dart';
import '../services/translation_memory/i_translation_memory_service.dart';

part 'data_migration_provider.g.dart';

/// State for data migration progress
class DataMigrationState {
  final bool isRunning;
  final bool isComplete;
  final String currentStep;
  final String progressMessage;
  final int currentProgress;
  final int totalProgress;
  final String? error;

  const DataMigrationState({
    this.isRunning = false,
    this.isComplete = false,
    this.currentStep = '',
    this.progressMessage = '',
    this.currentProgress = 0,
    this.totalProgress = 0,
    this.error,
  });

  DataMigrationState copyWith({
    bool? isRunning,
    bool? isComplete,
    String? currentStep,
    String? progressMessage,
    int? currentProgress,
    int? totalProgress,
    String? error,
  }) {
    return DataMigrationState(
      isRunning: isRunning ?? this.isRunning,
      isComplete: isComplete ?? this.isComplete,
      currentStep: currentStep ?? this.currentStep,
      progressMessage: progressMessage ?? this.progressMessage,
      currentProgress: currentProgress ?? this.currentProgress,
      totalProgress: totalProgress ?? this.totalProgress,
      error: error,
    );
  }

  double get progressPercent {
    if (totalProgress == 0) return 0;
    return (currentProgress / totalProgress).clamp(0.0, 1.0);
  }
}

/// Provider for one-time data migrations with progress tracking
@riverpod
class DataMigration extends _$DataMigration {
  static const _tmRebuildKey = 'tm_rebuild_v1_completed';
  static const _tmHashMigrationKey = 'tm_hash_migration_v1_completed';

  LoggingService get _logging => ServiceLocator.get<LoggingService>();

  @override
  DataMigrationState build() {
    return const DataMigrationState();
  }

  /// Check if any migrations are needed
  Future<bool> needsMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final rebuildDone = prefs.getBool(_tmRebuildKey) ?? false;
    final hashMigrationDone = prefs.getBool(_tmHashMigrationKey) ?? false;
    return !rebuildDone || !hashMigrationDone;
  }

  /// Run all pending migrations
  Future<void> runMigrations() async {
    if (state.isRunning) return;

    state = state.copyWith(isRunning: true, isComplete: false);

    final prefs = await SharedPreferences.getInstance();
    final tmService = ServiceLocator.get<ITranslationMemoryService>();

    try {
      // Step 1: TM Rebuild (adds missing entries with SHA256 hashes)
      final rebuildDone = prefs.getBool(_tmRebuildKey) ?? false;
      if (!rebuildDone) {
        _logging.info('Running TM rebuild');
        state = state.copyWith(
          currentStep: 'Rebuilding Translation Memory...',
          progressMessage: 'Scanning translations...',
          currentProgress: 0,
          totalProgress: 100,
        );

        final result = await tmService.rebuildFromTranslations(
          onProgress: (processed, total, added) {
            state = state.copyWith(
              progressMessage: '$processed / $total translations ($added added)',
              currentProgress: processed,
              totalProgress: total,
            );
          },
        );

        if (result.isOk) {
          await prefs.setBool(_tmRebuildKey, true);
          final stats = result.unwrap();
          _logging.info('TM rebuild completed', {
            'added': stats.added,
            'existing': stats.existing,
          });
        } else {
          throw Exception(result.unwrapErr().message);
        }
      }

      // Step 2: TM Hash Migration (converts old hashes, removes duplicates)
      final hashMigrationDone = prefs.getBool(_tmHashMigrationKey) ?? false;
      if (!hashMigrationDone) {
        _logging.info('Running TM hash migration');
        state = state.copyWith(
          currentStep: 'Migrating Translation Memory hashes...',
          progressMessage: 'Preparing...',
          currentProgress: 0,
          totalProgress: 100,
        );

        final result = await tmService.migrateLegacyHashes(
          onProgress: (processed, total) {
            state = state.copyWith(
              progressMessage: '$processed / $total entries',
              currentProgress: processed,
              totalProgress: total,
            );
          },
        );

        if (result.isOk) {
          await prefs.setBool(_tmHashMigrationKey, true);
          _logging.info('TM hash migration completed', {'processed': result.unwrap()});
        } else {
          throw Exception(result.unwrapErr().message);
        }
      }

      state = state.copyWith(
        isRunning: false,
        isComplete: true,
        currentStep: 'Migration complete',
        progressMessage: '',
      );
    } catch (e, stackTrace) {
      _logging.error('Data migration failed', e, stackTrace);
      state = state.copyWith(
        isRunning: false,
        isComplete: false,
        error: e.toString(),
      );
    }
  }
}
