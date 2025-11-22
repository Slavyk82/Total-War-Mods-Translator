import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/steam/i_steamcmd_service.dart';
import 'package:uuid/uuid.dart';

part 'mod_update_provider.g.dart';

/// Status of a mod update operation
enum ModUpdateStatus {
  pending,
  downloading,
  detectingChanges,
  updatingDatabase,
  completed,
  failed,
  cancelled,
}

/// Information about a mod update operation
class ModUpdateInfo {
  final String projectId;
  final String projectName;
  final ModUpdateStatus status;
  final double progress;
  final String? errorMessage;
  final ModVersion? newVersion;

  const ModUpdateInfo({
    required this.projectId,
    required this.projectName,
    required this.status,
    this.progress = 0.0,
    this.errorMessage,
    this.newVersion,
  });

  ModUpdateInfo copyWith({
    String? projectId,
    String? projectName,
    ModUpdateStatus? status,
    double? progress,
    String? errorMessage,
    ModVersion? newVersion,
  }) {
    return ModUpdateInfo(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      newVersion: newVersion ?? this.newVersion,
    );
  }

  bool get isInProgress =>
    status == ModUpdateStatus.downloading ||
    status == ModUpdateStatus.detectingChanges ||
    status == ModUpdateStatus.updatingDatabase;

  bool get isCompleted => status == ModUpdateStatus.completed;
  bool get isFailed => status == ModUpdateStatus.failed;
  bool get isCancelled => status == ModUpdateStatus.cancelled;
}

/// Provider for managing mod update queue and progress
@riverpod
class ModUpdateQueue extends _$ModUpdateQueue {
  final Map<String, ModUpdateInfo> _updateQueue = {};
  StreamSubscription<double>? _progressSubscription;
  String? _currentProjectId;

  @override
  Map<String, ModUpdateInfo> build() {
    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      _progressSubscription?.cancel();
    });

    return {};
  }

  /// Add a project to the update queue
  void addToQueue(Project project) {
    if (_updateQueue.containsKey(project.id)) {
      return; // Already in queue
    }

    final updateInfo = ModUpdateInfo(
      projectId: project.id,
      projectName: project.name,
      status: ModUpdateStatus.pending,
    );

    _updateQueue[project.id] = updateInfo;
    state = Map.from(_updateQueue);
  }

  /// Add multiple projects to the update queue
  void addMultipleToQueue(List<Project> projects) {
    for (final project in projects) {
      if (!_updateQueue.containsKey(project.id)) {
        final updateInfo = ModUpdateInfo(
          projectId: project.id,
          projectName: project.name,
          status: ModUpdateStatus.pending,
        );
        _updateQueue[project.id] = updateInfo;
      }
    }
    state = Map.from(_updateQueue);
  }

  /// Start updating all queued projects
  Future<void> startUpdates() async {
    final pendingProjects = _updateQueue.values
        .where((info) => info.status == ModUpdateStatus.pending)
        .toList();

    for (final updateInfo in pendingProjects) {
      if (state[updateInfo.projectId]?.status == ModUpdateStatus.cancelled) {
        continue;
      }

      await _updateProject(updateInfo.projectId);
    }
  }

  /// Update a specific project
  Future<void> _updateProject(String projectId) async {
    final steamService = ServiceLocator.get<ISteamCmdService>();
    final versionRepo = ServiceLocator.get<ModVersionRepository>();
    final projectRepo = ServiceLocator.get<ProjectRepository>();
    final gameInstallationRepo = ServiceLocator.get<GameInstallationRepository>();

    try {
      // Update status to downloading
      _updateStatus(projectId, ModUpdateStatus.downloading);
      _currentProjectId = projectId;

      // Subscribe to progress stream
      _progressSubscription?.cancel();
      _progressSubscription = steamService.progressStream.listen((progress) {
        _updateProgress(projectId, progress);
      });

      // Get project details from repository
      final updateInfo = _updateQueue[projectId];
      if (updateInfo == null) return;

      // Fetch project from database
      final projectResult = await projectRepo.getById(projectId);
      late final Project project;
      projectResult.when(
        ok: (p) => project = p,
        err: (error) {
          throw ServiceException('Failed to load project: ${error.message}');
        },
      );

      // Get Workshop ID from project
      final workshopId = project.modSteamId;
      if (workshopId == null || workshopId.isEmpty) {
        throw ServiceException('Project does not have a Steam Workshop ID');
      }

      // Get Game Installation to retrieve App ID
      final gameInstallationResult = await gameInstallationRepo.getById(project.gameInstallationId);
      late final GameInstallation gameInstallation;
      gameInstallationResult.when(
        ok: (gi) => gameInstallation = gi,
        err: (error) {
          throw ServiceException('Failed to load game installation: ${error.message}');
        },
      );

      final steamAppIdStr = gameInstallation.steamAppId;
      if (steamAppIdStr == null || steamAppIdStr.isEmpty) {
        throw ServiceException('Game installation does not have a Steam App ID');
      }

      // Parse App ID as integer
      final appId = int.tryParse(steamAppIdStr);
      if (appId == null) {
        throw ServiceException('Invalid Steam App ID: $steamAppIdStr');
      }

      // Download mod
      final downloadResult = await steamService.downloadMod(
        workshopId: workshopId,
        appId: appId,
        forceUpdate: true,
      );

      await downloadResult.when(
        ok: (result) async {
          // Update status to detecting changes
          _updateStatus(projectId, ModUpdateStatus.detectingChanges);

          // TODO: Implement change detection logic
          // For now, create a placeholder version
          final newVersion = ModVersion(
            id: const Uuid().v4(),
            projectId: projectId,
            versionString: DateTime.now().toIso8601String(),
            detectedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            steamUpdateTimestamp: result.timestamp.millisecondsSinceEpoch ~/ 1000,
            unitsAdded: 0, // Will be calculated by change detection
            unitsModified: 0,
            unitsDeleted: 0,
            isCurrent: false,
          );

          // Update status to updating database
          _updateStatus(projectId, ModUpdateStatus.updatingDatabase);

          // Insert new version
          final insertResult = await versionRepo.insert(newVersion);

          await insertResult.when(
            ok: (version) async {
              // Mark as current version
              await versionRepo.markAsCurrent(version.id);

              // Update status to completed
              _updateStatusWithVersion(
                projectId,
                ModUpdateStatus.completed,
                version,
              );
            },
            err: (error) {
              _updateStatusWithError(
                projectId,
                ModUpdateStatus.failed,
                'Failed to save version: ${error.message}',
              );
            },
          );
        },
        err: (error) {
          _updateStatusWithError(
            projectId,
            ModUpdateStatus.failed,
            'Download failed: ${error.message}',
          );
        },
      );
    } catch (e) {
      _updateStatusWithError(
        projectId,
        ModUpdateStatus.failed,
        'Update failed: $e',
      );
    } finally {
      _progressSubscription?.cancel();
      _currentProjectId = null;
    }
  }

  /// Update the status of a project in the queue
  void _updateStatus(String projectId, ModUpdateStatus status) {
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(status: status);
      state = Map.from(_updateQueue);
    }
  }

  /// Update the progress of a project in the queue
  void _updateProgress(String projectId, double progress) {
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(progress: progress);
      state = Map.from(_updateQueue);
    }
  }

  /// Update status with error message
  void _updateStatusWithError(
    String projectId,
    ModUpdateStatus status,
    String errorMessage,
  ) {
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(
        status: status,
        errorMessage: errorMessage,
      );
      state = Map.from(_updateQueue);
    }
  }

  /// Update status with new version
  void _updateStatusWithVersion(
    String projectId,
    ModUpdateStatus status,
    ModVersion version,
  ) {
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(
        status: status,
        newVersion: version,
        progress: 1.0,
      );
      state = Map.from(_updateQueue);
    }
  }

  /// Cancel all pending updates
  void cancelAll() {
    for (final entry in _updateQueue.entries) {
      if (entry.value.isInProgress || entry.value.status == ModUpdateStatus.pending) {
        _updateQueue[entry.key] = entry.value.copyWith(
          status: ModUpdateStatus.cancelled,
        );
      }
    }
    state = Map.from(_updateQueue);

    // Cancel current download
    if (_currentProjectId != null) {
      final steamService = ServiceLocator.get<ISteamCmdService>();
      steamService.cancel();
    }
  }

  /// Clear the queue
  void clearQueue() {
    _updateQueue.clear();
    state = {};
  }

  /// Retry a failed update
  Future<void> retry(String projectId) async {
    final info = _updateQueue[projectId];
    if (info != null && (info.isFailed || info.isCancelled)) {
      _updateQueue[projectId] = info.copyWith(
        status: ModUpdateStatus.pending,
        errorMessage: null,
      );
      state = Map.from(_updateQueue);

      await _updateProject(projectId);
    }
  }

  /// Get summary of completed updates
  int get completedCount =>
      _updateQueue.values.where((info) => info.isCompleted).length;

  /// Get summary of failed updates
  int get failedCount =>
      _updateQueue.values.where((info) => info.isFailed).length;

  /// Get summary of pending updates
  int get pendingCount =>
      _updateQueue.values.where((info) => info.status == ModUpdateStatus.pending).length;

  /// Check if all updates are complete
  bool get allComplete =>
      _updateQueue.values.every(
        (info) => info.isCompleted || info.isFailed || info.isCancelled,
      );
}
