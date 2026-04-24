import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/database/data_migrations/validation_issues_json_data_migration.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

part 'validation_rescan_provider.g.dart';

/// State exposed by the rescan controller to drive [ValidationRescanDialog].
class RescanState {
  final RescanPlan? plan;
  final RescanProgress? progress;
  final bool isRunning;
  final bool isDone;
  final Object? error;

  /// True while the legacy validation_issues JSON rewrite is running.
  final bool isNormalizing;

  /// Rows rewritten so far in the JSON normalization phase.
  final int normalizeProcessed;

  /// Total rows scheduled for the JSON normalization phase.
  final int normalizeTotal;

  const RescanState({
    this.plan,
    this.progress,
    this.isRunning = false,
    this.isDone = false,
    this.error,
    this.isNormalizing = false,
    this.normalizeProcessed = 0,
    this.normalizeTotal = 0,
  });

  RescanState copyWith({
    RescanPlan? plan,
    RescanProgress? progress,
    bool? isRunning,
    bool? isDone,
    Object? error,
    bool? isNormalizing,
    int? normalizeProcessed,
    int? normalizeTotal,
  }) =>
      RescanState(
        plan: plan ?? this.plan,
        progress: progress ?? this.progress,
        isRunning: isRunning ?? this.isRunning,
        isDone: isDone ?? this.isDone,
        error: error ?? this.error,
        isNormalizing: isNormalizing ?? this.isNormalizing,
        normalizeProcessed: normalizeProcessed ?? this.normalizeProcessed,
        normalizeTotal: normalizeTotal ?? this.normalizeTotal,
      );
}

/// DI hook for the rescan service. Overridable from widget tests.
///
/// `keepAlive: true` prevents auto-disposal between `ref.read()` and the
/// time the dialog finally calls `ref.watch()` in its build method.
@Riverpod(keepAlive: true)
ValidationRescanService validationRescanService(Ref ref) {
  return ValidationRescanService(
    versionRepo: ref.read(translationVersionRepositoryProvider),
    unitRepo: ref.read(translationUnitRepositoryProvider),
    validation: ref.read(validationServiceProvider),
    logger: ref.read(loggingServiceProvider),
  );
}

/// `keepAlive: true` is required because `prepare()` is invoked via
/// `ref.read(...notifier).prepare()` before any widget is watching the
/// provider. Without it, the provider is auto-disposed during the async
/// calibration pass inside `buildPlan()` and subsequent `state = ...`
/// assignments throw "Ref disposed".
@Riverpod(keepAlive: true)
class ValidationRescanController extends _$ValidationRescanController {
  StreamSubscription<RescanProgress>? _sub;

  @override
  RescanState build() {
    ref.onDispose(() => _sub?.cancel());
    return const RescanState();
  }

  /// Lightweight check used by the dialog host to decide whether to open
  /// the modal at all. Returns true when either the legacy JSON rewrite is
  /// pending or at least one row still sits at a pre-current schema
  /// version. Safe to call before [prepare].
  ///
  /// `ValidationIssuesJsonDataMigration.isApplied()` writes its marker
  /// opportunistically when the DB has no legacy-shaped rows; that side
  /// effect is intentional and keeps subsequent boots cheap.
  Future<bool> hasPendingWork() async {
    final logger = ref.read(loggingServiceProvider);
    try {
      final jsonApplied =
          await ValidationIssuesJsonDataMigration().isApplied();
      if (!jsonApplied) return true;
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final legacy = (await versionRepo.countLegacyValidationRows()).unwrap();
      return legacy > 0;
    } catch (e, st) {
      logger.error('ValidationRescan: hasPendingWork check failed', e, st);
      // Fail open: surface the dialog so the error is visible to the user.
      return true;
    }
  }

  /// Run the JSON normalization pass (if needed) and then the calibration /
  /// plan computation. Call this from the dialog's `initState` so the modal
  /// is already visible while the (potentially non-trivial) normalization
  /// progresses. When no rescan is needed afterwards, `isDone` is set so
  /// the dialog can close itself.
  Future<void> prepare() async {
    final logger = ref.read(loggingServiceProvider);
    try {
      // Phase 1: rewrite legacy Dart-toString JSON payloads. Supersedes the
      // former pre-runApp / DataMigrationDialog step — all validation-data
      // work now happens behind this single dialog.
      final jsonMigration = ValidationIssuesJsonDataMigration();
      if (!await jsonMigration.isApplied()) {
        logger.info('ValidationRescan: running JSON normalization');
        state = state.copyWith(isNormalizing: true);
        await jsonMigration.run(
          onProgress: (processed, total) {
            state = state.copyWith(
              normalizeProcessed: processed,
              normalizeTotal: total,
            );
          },
        );
        state = state.copyWith(isNormalizing: false);
      }

      // Phase 2: build the rescan plan (calibration + row counts).
      final svc = ref.read(validationRescanServiceProvider);
      final plan = await svc.buildPlan();
      if (plan == null) {
        logger.info('ValidationRescan: no legacy rows, closing after prepare');
      } else {
        logger.info('ValidationRescan: plan ready', {
          'total': plan.total,
          'already': plan.already,
          'isResume': plan.isResume,
          'estimatedMs': plan.estimated.inMilliseconds,
        });
      }
      state = state.copyWith(
        plan: plan,
        isDone: plan == null,
      );
    } catch (e, st) {
      logger.error('ValidationRescan: prepare failed', e, st);
      state = state.copyWith(
        error: e,
        isDone: true,
        isNormalizing: false,
      );
    }
  }

  /// Kick off the scan. Idempotent once running; safe to call twice.
  void start() {
    if (state.isRunning || state.plan == null || state.isDone) return;
    final svc = ref.read(validationRescanServiceProvider);
    state = state.copyWith(isRunning: true);
    _sub = svc.run().listen(
      (p) => state = state.copyWith(progress: p),
      onError: (Object e) =>
          state = state.copyWith(error: e, isRunning: false, isDone: true),
      onDone: () => state = state.copyWith(isRunning: false, isDone: true),
    );
  }
}
