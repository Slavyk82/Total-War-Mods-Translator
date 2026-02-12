import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/project_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';
import '../../../services/steam/i_workshop_publish_service.dart';
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

  // Cached credentials for Steam Guard retry
  String? _cachedUsername;
  String? _cachedPassword;
  WorkshopPublishParams? _cachedParams;
  String? _cachedProjectId;

  @override
  WorkshopPublishState build() => const WorkshopPublishState();

  /// Start publishing to Steam Workshop
  Future<void> publish({
    required WorkshopPublishParams params,
    required String username,
    required String password,
    String? steamGuardCode,
    String? projectId,
  }) async {
    final logging = ServiceLocator.get<LoggingService>();
    final service = ServiceLocator.get<IWorkshopPublishService>();

    // Cache credentials for potential Steam Guard retry
    _cachedUsername = username;
    _cachedPassword = password;
    _cachedParams = params;
    _cachedProjectId = projectId;

    state = state.copyWith(
      phase: PublishPhase.uploading,
      progress: 0.0,
      statusMessage: 'Starting upload...',
      steamcmdOutput: [],
      clearError: true,
    );

    // Listen to progress
    _progressSub?.cancel();
    _progressSub = service.progressStream.listen((progress) {
      state = state.copyWith(progress: progress);
    });

    // Listen to output
    _outputSub?.cancel();
    _outputSub = service.outputStream.listen((line) {
      state = state.copyWith(
        steamcmdOutput: [...state.steamcmdOutput, line],
        statusMessage: line,
      );
    });

    logging.info('Starting Workshop publish', {
      'title': params.title,
      'isNew': params.isNewItem,
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

    result.when(
      ok: (publishResult) async {
        // Save workshop ID to project if we have a project ID
        if (projectId != null) {
          state = state.copyWith(
            phase: PublishPhase.savingWorkshopId,
            statusMessage: 'Saving Workshop ID...',
          );

          try {
            final projectRepo = ServiceLocator.get<ProjectRepository>();
            final projectResult = await projectRepo.getById(projectId);
            if (projectResult.isOk) {
              final updated = projectResult.value.copyWith(
                publishedSteamId: publishResult.workshopId,
              );
              await projectRepo.update(updated);
            }
          } catch (e) {
            logging.warning('Failed to save Workshop ID to project: $e');
          }
        }

        state = state.copyWith(
          phase: PublishPhase.completed,
          progress: 1.0,
          publishedWorkshopId: publishResult.workshopId,
          wasUpdate: publishResult.wasUpdate,
          statusMessage: publishResult.wasUpdate
              ? 'Workshop item updated successfully!'
              : 'Workshop item published successfully!',
        );

        // Invalidate the exports list to refresh Published ID
        ref.invalidate(recentPackExportsProvider);

        logging.info('Workshop publish completed', {
          'workshopId': publishResult.workshopId,
          'wasUpdate': publishResult.wasUpdate,
        });
      },
      err: (error) {
        if (error is SteamGuardRequiredException) {
          state = state.copyWith(
            phase: PublishPhase.awaitingSteamGuard,
            statusMessage: 'Steam Guard code required',
          );
        } else {
          state = state.copyWith(
            phase: PublishPhase.error,
            errorMessage: error.message,
            statusMessage: 'Publication failed',
          );
          logging.error('Workshop publish failed: ${error.message}');
        }
      },
    );

    // Clear cached credentials on completion or non-retryable error
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
    );
  }

  /// Cancel the current publish operation
  Future<void> cancel() async {
    final service = ServiceLocator.get<IWorkshopPublishService>();
    await service.cancel();
    _progressSub?.cancel();
    _outputSub?.cancel();
    _clearCachedCredentials();

    state = state.copyWith(
      phase: PublishPhase.cancelled,
      statusMessage: 'Publication cancelled',
    );
  }

  /// Reset to idle state
  void reset() {
    _progressSub?.cancel();
    _outputSub?.cancel();
    _clearCachedCredentials();
    state = const WorkshopPublishState();
  }

  void _clearCachedCredentials() {
    _cachedUsername = null;
    _cachedPassword = null;
    _cachedParams = null;
    _cachedProjectId = null;
  }
}

/// Provider for workshop publish state
final workshopPublishProvider =
    NotifierProvider<WorkshopPublishNotifier, WorkshopPublishState>(
  WorkshopPublishNotifier.new,
);
