import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../../../services/steam/models/steam_exceptions.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import 'steam_publish_providers.dart';

/// Phase of the workshop publish operation
enum PublishPhase {
  idle,
  awaitingCredentials,
  awaitingSteamGuard,
  uploading,
  savingWorkshopId,
  completed,
  error,
  cancelled,
}

/// State for the workshop publish flow
class WorkshopPublishState {
  final PublishPhase phase;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;
  final String? publishedWorkshopId;
  final bool wasUpdate;
  final List<String> steamcmdOutput;

  const WorkshopPublishState({
    this.phase = PublishPhase.idle,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
    this.publishedWorkshopId,
    this.wasUpdate = false,
    this.steamcmdOutput = const [],
  });

  WorkshopPublishState copyWith({
    PublishPhase? phase,
    double? progress,
    String? statusMessage,
    String? errorMessage,
    String? publishedWorkshopId,
    bool? wasUpdate,
    List<String>? steamcmdOutput,
    bool clearError = false,
  }) {
    return WorkshopPublishState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      publishedWorkshopId:
          publishedWorkshopId ?? this.publishedWorkshopId,
      wasUpdate: wasUpdate ?? this.wasUpdate,
      steamcmdOutput: steamcmdOutput ?? this.steamcmdOutput,
    );
  }

  bool get isActive =>
      phase == PublishPhase.uploading ||
      phase == PublishPhase.savingWorkshopId;
}

/// Notifier managing the Workshop publish flow
class WorkshopPublishNotifier extends Notifier<WorkshopPublishState> {
  StreamSubscription<double>? _progressSub;
  StreamSubscription<String>? _outputSub;
  bool _silentlyCleaned = false;

  // Cached credentials for Steam Guard retry
  String? _cachedUsername;
  String? _cachedPassword;
  WorkshopPublishParams? _cachedParams;
  String? _cachedProjectId;
  String? _cachedCompilationId;

  @override
  WorkshopPublishState build() => const WorkshopPublishState();

  /// Start publishing to Steam Workshop
  Future<void> publish({
    required WorkshopPublishParams params,
    required String username,
    required String password,
    String? steamGuardCode,
    String? projectId,
    String? compilationId,
  }) async {
    final logging = ref.read(loggingServiceProvider);
    final service = ref.read(workshopPublishServiceProvider);
    _silentlyCleaned = false;

    // Cache credentials for potential Steam Guard retry
    _cachedUsername = username;
    _cachedPassword = password;
    _cachedParams = params;
    _cachedProjectId = projectId;
    _cachedCompilationId = compilationId;

    state = state.copyWith(
      phase: PublishPhase.uploading,
      progress: 0.0,
      statusMessage: 'Starting upload...',
      steamcmdOutput: [],
      clearError: true,
    );

    // Listen to progress (guard: skip if cleaned up or no longer uploading)
    _progressSub?.cancel();
    _progressSub = service.progressStream.listen((progress) {
      if (_silentlyCleaned || state.phase != PublishPhase.uploading) return;
      state = state.copyWith(progress: progress);
    });

    // Listen to output (guard: skip if cleaned up or no longer uploading)
    _outputSub?.cancel();
    _outputSub = service.outputStream.listen((line) {
      if (_silentlyCleaned || state.phase != PublishPhase.uploading) return;
      state = state.copyWith(
        steamcmdOutput: [...state.steamcmdOutput, line],
        statusMessage: line,
      );
    });

    logging.info('Starting Workshop publish', {
      'title': params.title,
      'publishedFileId': params.publishedFileId,
      'projectId': projectId,
    });

    final result = await service.publish(
      params: params,
      username: username,
      password: password,
      steamGuardCode: steamGuardCode,
    );

    _progressSub?.cancel();
    _outputSub?.cancel();

    // If cleaned up or reset while awaiting, the UI is gone: skip the state
    // writes below — but on a successful upload still persist the Workshop
    // ID. This notifier is app-scoped (ref stays valid after the widget is
    // disposed), and dropping the id would orphan the published item: the
    // project would still show as unpublished and a re-publish would create
    // a duplicate Workshop item.
    final cleanedWhileAwaiting = _silentlyCleaned ||
        state.phase == PublishPhase.idle ||
        state.phase == PublishPhase.cancelled;
    if (cleanedWhileAwaiting && result.isErr) {
      return;
    }

    if (result.isOk) {
      final publishResult = result.value;

      // Save workshop ID to project or compilation. The repositories return
      // Result and never throw, so failures must be read off the Result —
      // the catch below only covers unexpected throws (e.g. disposed ref).
      // A failed save is surfaced on the completed state (the upload itself
      // succeeded) so the user knows the id was not persisted locally.
      String? saveFailure;
      if (projectId != null || compilationId != null) {
        if (!cleanedWhileAwaiting) {
          state = state.copyWith(
            phase: PublishPhase.savingWorkshopId,
            statusMessage: 'Saving Workshop ID...',
          );
        }

        try {
          if (projectId != null) {
            final projectRepo = ref.read(projectRepositoryProvider);
            final projectResult = await projectRepo.getById(projectId);
            if (projectResult.isErr) {
              saveFailure = projectResult.error.message;
            } else {
              final updated = projectResult.value.copyWith(
                publishedSteamId: publishResult.workshopId,
                publishedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                updatedAt: projectResult.value.updatedAt,
              );
              final updateResult = await projectRepo.update(updated);
              if (updateResult.isErr) {
                saveFailure = updateResult.error.message;
              }
            }
          } else if (compilationId != null) {
            final compilationRepo = ref.read(compilationRepositoryProvider);
            final updateResult = await compilationRepo.updateAfterPublish(
              compilationId,
              publishResult.workshopId,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
            if (updateResult.isErr) {
              saveFailure = updateResult.error.message;
            }
          }
        } catch (e) {
          saveFailure = e.toString();
        }
        if (saveFailure != null) {
          logging.warning('Failed to save Workshop ID: $saveFailure');
        }
      }

      // Refresh the exports list regardless of UI state — the published id
      // just changed in the DB.
      ref.invalidate(publishableItemsProvider);

      // Re-check after the repo awaits: a silentCleanup() arriving while the
      // id was being saved must not resurrect a stale completed state.
      if (cleanedWhileAwaiting || _silentlyCleaned) {
        logging.info('Workshop publish completed after cleanup', {
          'workshopId': publishResult.workshopId,
          'wasUpdate': publishResult.wasUpdate,
        });
        return;
      }

      state = state.copyWith(
        phase: PublishPhase.completed,
        progress: 1.0,
        publishedWorkshopId: publishResult.workshopId,
        wasUpdate: publishResult.wasUpdate,
        statusMessage: saveFailure != null
            ? 'Workshop item ${publishResult.wasUpdate ? 'updated' : 'published'}, '
                'but the Workshop ID could not be saved locally '
                '($saveFailure). The item may still show as unpublished — '
                'set the Workshop ID manually before publishing again.'
            : (publishResult.wasUpdate
                ? 'Workshop item updated successfully!'
                : 'Workshop item published successfully!'),
      );

      logging.info('Workshop publish completed', {
        'workshopId': publishResult.workshopId,
        'wasUpdate': publishResult.wasUpdate,
      });
    } else {
      final error = result.error;
      if (error is SteamGuardRequiredException) {
        state = state.copyWith(
          phase: PublishPhase.awaitingSteamGuard,
          statusMessage: 'Steam Guard code required',
        );
      } else if (error is WorkshopItemNotFoundException) {
        state = state.copyWith(
          phase: PublishPhase.error,
          errorMessage: error.message,
          statusMessage: 'Workshop item not found',
        );
        logging.error('Workshop item not found: ${error.message}');
      } else {
        state = state.copyWith(
          phase: PublishPhase.error,
          errorMessage: error.message,
          statusMessage: 'Publication failed',
        );
        logging.error('Workshop publish failed: ${error.message}');
      }
    }

    // Clear cached credentials on completion or non-retryable error
    // (not for awaitingSteamGuard — we need them for retry)
    if (state.phase == PublishPhase.completed ||
        state.phase == PublishPhase.error) {
      _clearCachedCredentials();
    }
  }

  /// Retry publish with a Steam Guard code
  Future<void> retryWithSteamGuard(String code) async {
    if (_cachedParams == null ||
        _cachedUsername == null ||
        _cachedPassword == null) {
      state = state.copyWith(
        phase: PublishPhase.error,
        errorMessage: 'Session expired. Please try again.',
      );
      return;
    }

    await publish(
      params: _cachedParams!,
      username: _cachedUsername!,
      password: _cachedPassword!,
      steamGuardCode: code,
      projectId: _cachedProjectId,
      compilationId: _cachedCompilationId,
    );
  }

  /// Submit a Steam Guard code to the running steamcmd process
  void submitSteamGuardCode(String code) {
    final service = ref.read(workshopPublishServiceProvider);
    service.submitSteamGuardCode(code);
    state = state.copyWith(
      statusMessage: 'Steam Guard code submitted, authenticating...',
    );
  }

  /// Cancel the current publish operation
  Future<void> cancel() async {
    final service = ref.read(workshopPublishServiceProvider);
    await service.cancel();
    _progressSub?.cancel();
    _outputSub?.cancel();
    _clearCachedCredentials();

    state = state.copyWith(
      phase: PublishPhase.cancelled,
      statusMessage: 'Publication cancelled',
    );
  }

  /// Reset to idle state (only call when the widget is still mounted)
  void reset() {
    _silentlyCleaned = false;
    _progressSub?.cancel();
    _outputSub?.cancel();
    _clearCachedCredentials();
    state = const WorkshopPublishState();
  }

  /// Clean up without setting state — safe to call from widget dispose()
  /// where the element is already defunct.
  void silentCleanup() {
    // Mark cleanup so the pending `publish()` continuation and any stray
    // stream events skip their state writes (this provider is app-scoped, so
    // a write here would otherwise persist a stale error/progress state and
    // flash it when the screen is reopened). `publish()` and `reset()` set
    // the flag back to false when a new flow starts.
    _silentlyCleaned = true;
    _progressSub?.cancel();
    _progressSub = null;
    _outputSub?.cancel();
    _outputSub = null;
    _clearCachedCredentials();
    final service = ref.read(workshopPublishServiceProvider);
    service.cancel();
  }

  void _clearCachedCredentials() {
    _cachedUsername = null;
    _cachedPassword = null;
    _cachedParams = null;
    _cachedProjectId = null;
    _cachedCompilationId = null;
  }
}

/// Provider for workshop publish state
final workshopPublishProvider =
    NotifierProvider<WorkshopPublishNotifier, WorkshopPublishState>(
  WorkshopPublishNotifier.new,
);
