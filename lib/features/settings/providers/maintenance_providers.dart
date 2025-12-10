import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../repositories/mod_update_analysis_cache_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';

part 'maintenance_providers.g.dart';

/// Result of a maintenance operation.
class MaintenanceResult {
  final bool success;
  final String message;
  final int? fixedToPending;
  final int? fixedToTranslated;
  final int? totalAnalyzed;

  const MaintenanceResult({
    required this.success,
    required this.message,
    this.fixedToPending,
    this.fixedToTranslated,
    this.totalAnalyzed,
  });

  factory MaintenanceResult.success({
    required int fixedToPending,
    required int fixedToTranslated,
    required int total,
  }) {
    final totalFixed = fixedToPending + fixedToTranslated;
    final message = totalFixed == 0
        ? 'Analysis complete. All translations have consistent status.'
        : 'Fixed $totalFixed inconsistencies out of $total translations. '
            '($fixedToPending set to pending, $fixedToTranslated set to translated)';

    return MaintenanceResult(
      success: true,
      message: message,
      fixedToPending: fixedToPending,
      fixedToTranslated: fixedToTranslated,
      totalAnalyzed: total,
    );
  }

  factory MaintenanceResult.error(String error) {
    return MaintenanceResult(
      success: false,
      message: 'Analysis failed: $error',
    );
  }
}

/// State for maintenance operations.
class MaintenanceState {
  final bool isReanalyzing;
  final String? progressMessage;
  final MaintenanceResult? lastResult;

  const MaintenanceState({
    this.isReanalyzing = false,
    this.progressMessage,
    this.lastResult,
  });

  MaintenanceState copyWith({
    bool? isReanalyzing,
    String? progressMessage,
    MaintenanceResult? lastResult,
    bool clearProgress = false,
    bool clearResult = false,
  }) {
    return MaintenanceState(
      isReanalyzing: isReanalyzing ?? this.isReanalyzing,
      progressMessage:
          clearProgress ? null : (progressMessage ?? this.progressMessage),
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
    );
  }
}

/// Notifier for maintenance operations.
@riverpod
class MaintenanceStateNotifier extends _$MaintenanceStateNotifier {
  LoggingService get _logging => ServiceLocator.get<LoggingService>();

  @override
  MaintenanceState build() {
    return const MaintenanceState();
  }

  /// Reanalyze all translation statuses to fix inconsistencies.
  Future<void> reanalyzeAllTranslations() async {
    if (state.isReanalyzing) return;

    state = state.copyWith(
      isReanalyzing: true,
      progressMessage: 'Analyzing translation statuses...',
      clearResult: true,
    );

    try {
      _logging.info('Starting translation status reanalysis');

      final repository = ServiceLocator.get<TranslationVersionRepository>();

      // First, count inconsistencies
      state = state.copyWith(
        progressMessage: 'Counting inconsistencies...',
      );

      final countResult = await repository.countInconsistentStatuses();
      if (countResult.isErr) {
        throw Exception(countResult.unwrapErr().message);
      }

      final counts = countResult.unwrap();
      final totalInconsistent =
          counts.pendingWithText + counts.nonPendingWithoutText;

      _logging.info(
        'Found $totalInconsistent inconsistent statuses',
        {
          'pendingWithText': counts.pendingWithText,
          'nonPendingWithoutText': counts.nonPendingWithoutText,
        },
      );

      // Perform the reanalysis
      state = state.copyWith(
        progressMessage: 'Fixing $totalInconsistent inconsistencies...',
      );

      final result = await repository.reanalyzeAllStatuses();

      if (result.isErr) {
        throw Exception(result.unwrapErr().message);
      }

      final stats = result.unwrap();

      _logging.info(
        'Translation reanalysis complete',
        {
          'fixedToPending': stats.fixedToPending,
          'fixedToTranslated': stats.fixedToTranslated,
          'total': stats.total,
        },
      );

      state = state.copyWith(
        isReanalyzing: false,
        clearProgress: true,
        lastResult: MaintenanceResult.success(
          fixedToPending: stats.fixedToPending,
          fixedToTranslated: stats.fixedToTranslated,
          total: stats.total,
        ),
      );
    } catch (e, stackTrace) {
      _logging.error('Translation reanalysis failed', e, stackTrace);

      state = state.copyWith(
        isReanalyzing: false,
        clearProgress: true,
        lastResult: MaintenanceResult.error(e.toString()),
      );
    }
  }

  /// Clear the last result message.
  void clearResult() {
    state = state.copyWith(clearResult: true);
  }

  /// Clear all stale mod update analysis cache entries.
  /// This removes entries that have hasChanges=true but whose changes
  /// have already been applied (or should have been).
  Future<void> clearStaleAnalysisCache() async {
    if (state.isReanalyzing) return;

    state = state.copyWith(
      isReanalyzing: true,
      progressMessage: 'Clearing stale analysis cache...',
      clearResult: true,
    );

    try {
      _logging.info('Clearing stale mod update analysis cache');

      final cacheRepo = ServiceLocator.get<ModUpdateAnalysisCacheRepository>();
      final result = await cacheRepo.deleteAllWithChanges();

      if (result.isErr) {
        throw Exception(result.unwrapErr().message);
      }

      final deletedCount = result.unwrap();

      _logging.info('Cleared $deletedCount stale analysis cache entries');

      state = state.copyWith(
        isReanalyzing: false,
        clearProgress: true,
        lastResult: MaintenanceResult(
          success: true,
          message: deletedCount > 0
              ? 'Cleared $deletedCount stale analysis cache entries. '
                  'The next mod scan will re-analyze changes.'
              : 'No stale cache entries found.',
        ),
      );
    } catch (e, stackTrace) {
      _logging.error('Failed to clear analysis cache', e, stackTrace);

      state = state.copyWith(
        isReanalyzing: false,
        clearProgress: true,
        lastResult: MaintenanceResult.error(e.toString()),
      );
    }
  }
}
