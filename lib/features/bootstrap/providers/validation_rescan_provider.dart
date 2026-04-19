import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

part 'validation_rescan_provider.g.dart';

/// State exposed by the rescan controller to drive [ValidationRescanDialog].
class RescanState {
  final RescanPlan? plan;
  final RescanProgress? progress;
  final bool isRunning;
  final bool isDone;
  final Object? error;

  const RescanState({
    this.plan,
    this.progress,
    this.isRunning = false,
    this.isDone = false,
    this.error,
  });

  RescanState copyWith({
    RescanPlan? plan,
    RescanProgress? progress,
    bool? isRunning,
    bool? isDone,
    Object? error,
  }) =>
      RescanState(
        plan: plan ?? this.plan,
        progress: progress ?? this.progress,
        isRunning: isRunning ?? this.isRunning,
        isDone: isDone ?? this.isDone,
        error: error ?? this.error,
      );
}

/// DI hook for the rescan service. Overridable from widget tests.
@riverpod
ValidationRescanService validationRescanService(Ref ref) {
  return ValidationRescanService(
    versionRepo: ref.read(translationVersionRepositoryProvider),
    unitRepo: ref.read(translationUnitRepositoryProvider),
    validation: ref.read(validationServiceProvider),
    logger: ref.read(loggingServiceProvider),
  );
}

@riverpod
class ValidationRescanController extends _$ValidationRescanController {
  StreamSubscription<RescanProgress>? _sub;

  @override
  RescanState build() {
    ref.onDispose(() => _sub?.cancel());
    return const RescanState();
  }

  /// Compute the plan (calibration + row counts). Must be called before
  /// [start]. When `state.plan` remains null, there is no legacy data and
  /// the caller can close the dialog immediately.
  Future<void> prepare() async {
    final svc = ref.read(validationRescanServiceProvider);
    try {
      final plan = await svc.buildPlan();
      state = state.copyWith(
        plan: plan,
        isDone: plan == null,
      );
    } catch (e) {
      state = state.copyWith(error: e, isDone: true);
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
