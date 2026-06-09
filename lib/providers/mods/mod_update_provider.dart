import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueGetter;
import 'package:path/path.dart' as path;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/services/mods/project_analysis_handler.dart';
import 'package:uuid/uuid.dart';
import '../shared/logging_providers.dart';
import '../shared/repository_providers.dart';
import '../shared/service_providers.dart';

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
    // Use a ValueGetter sentinel so callers can explicitly clear the error
    // (e.g. on retry). A plain `String?` cannot distinguish "leave unchanged"
    // from "set to null", which previously left stale errors in place.
    ValueGetter<String?>? errorMessage,
    ModVersion? newVersion,
  }) {
    return ModUpdateInfo(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
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

  // Serializes all update execution. `_updateProject` mutates the single-slot
  // `_progressSubscription`/`_currentProjectId` fields, so two invocations must
  // never overlap. Both `startUpdates()` (fire-and-forget) and `retry()` route
  // their work through `_runExclusive`, which chains tasks onto this future so
  // a retry triggered mid-download waits for the in-flight project to finish
  // instead of cancelling its progress subscription and overwriting the
  // current-project id.
  Future<void> _updateChain = Future<void>.value();

  /// Runs [action] after any in-flight update completes, guaranteeing that at
  /// most one [_updateProject] touches the shared subscription/current-id slots
  /// at a time. Returns a future that resolves when [action] has run.
  Future<void> _runExclusive(Future<void> Function() action) {
    // Swallow prior errors so one failed task can't break the chain, then run
    // the new action. We capture the resulting future as the new chain tail so
    // subsequent callers queue behind this action.
    final next = _updateChain.then((_) => action(), onError: (_) => action());
    // Keep the chain alive even if `action` throws, so the next caller still
    // runs rather than inheriting an unhandled error.
    _updateChain = next.catchError((_) {});
    return next;
  }

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

      // Run each project exclusively so a concurrent retry() can't interleave
      // and clobber this project's progress subscription / current-id.
      await _runExclusive(() => _updateProject(updateInfo.projectId));
    }
  }

  /// Update a specific project
  Future<void> _updateProject(String projectId) async {
    final steamService = ref.read(steamCmdServiceProvider);
    final versionRepo = ref.read(modVersionRepositoryProvider);
    final projectRepo = ref.read(projectRepositoryProvider);
    final gameInstallationRepo = ref.read(gameInstallationRepositoryProvider);

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

          // Locate the downloaded .pack file (same selection rule as the
          // Workshop scanner: first non-TWMT pack in the mod directory).
          final packFile = await _findDownloadedPackFile(result.downloadPath);
          if (packFile == null) {
            _updateStatusWithError(
              projectId,
              ModUpdateStatus.failed,
              'No .pack file found in downloaded mod (${result.downloadPath})',
            );
            return;
          }
          final packStat = await packFile.stat();
          final fileLastModified =
              packStat.modified.millisecondsSinceEpoch ~/ 1000;

          // Run the SAME analysis/apply pipeline as the Workshop scan: it
          // detects new/modified/removed/reactivated keys, applies them to
          // translation_units/versions, flags the project and updates the
          // analysis cache. Previously this flow inserted a placeholder
          // ModVersion (0/0/0 counts) and applied nothing.
          final analysisHandler = ProjectAnalysisHandler(
            projectRepository: projectRepo,
            analysisCacheRepository:
                ref.read(modUpdateAnalysisCacheRepositoryProvider),
            modUpdateAnalysisService:
                ref.read(modUpdateAnalysisServiceProvider),
            logger: ref.read(loggingServiceProvider),
          );
          final analysisResult = await analysisHandler.analyzeProjectChanges(
            projectId: projectId,
            packFilePath: packFile.path,
            workshopId: workshopId,
            fileLastModified: fileLastModified,
          );
          final analysis = analysisResult.analysis;
          if (analysis == null) {
            // analyzeProjectChanges already logged the cause.
            _updateStatusWithError(
              projectId,
              ModUpdateStatus.failed,
              'Change detection failed for the downloaded pack',
            );
            return;
          }

          // Update status to updating database
          _updateStatus(projectId, ModUpdateStatus.updatingDatabase);

          final newVersion = ModVersion(
            id: const Uuid().v4(),
            projectId: projectId,
            // Steam Workshop has no semantic version string: identify the
            // version by the pack's last-modified time (Workshop update time).
            versionString: packStat.modified.toIso8601String(),
            detectedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            steamUpdateTimestamp: fileLastModified,
            unitsAdded: analysis.newUnitsCount,
            unitsModified: analysis.modifiedUnitsCount,
            unitsDeleted: analysis.removedUnitsCount,
            isCurrent: false,
          );

          // Insert new version
          final insertResult = await versionRepo.insert(newVersion);

          await insertResult.when(
            ok: (version) async {
              // Mark as current version
              final markResult = await versionRepo.markAsCurrent(version.id);
              if (markResult.isErr) {
                _updateStatusWithError(
                  projectId,
                  ModUpdateStatus.failed,
                  'Failed to mark version as current: '
                  '${markResult.unwrapErr().message}',
                );
                return;
              }

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
      // If the notifier was disposed mid-download (dialog closed), don't try to
      // route the failure back through state — _updateStatusWithError would be a
      // no-op anyway, and the original error is moot once nothing is watching.
      if (!ref.mounted) return;
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

  /// Find the first non-TWMT `.pack` file in [downloadPath].
  ///
  /// Mirrors PackFileScanner's selection rule for Workshop mod directories:
  /// packs whose name contains the `_twmt_` marker are TWMT-generated
  /// translation packs, not the mod itself.
  Future<File?> _findDownloadedPackFile(String downloadPath) async {
    final dir = Directory(downloadPath);
    if (!await dir.exists()) return null;
    final packFiles = await dir
        .list()
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.pack'))
        .cast<File>()
        .toList();
    for (final packFile in packFiles) {
      final name =
          path.basenameWithoutExtension(packFile.path).toLowerCase();
      if (name.contains('_twmt_')) continue;
      return packFile;
    }
    return null;
  }

  /// Update the status of a project in the queue
  void _updateStatus(String projectId, ModUpdateStatus status) {
    // This notifier is autoDispose; these helpers run after long awaits in
    // _updateProject, by which point the only watcher (the dialog) may have
    // closed and disposed the notifier. Writing `state` then throws StateError.
    if (!ref.mounted) return;
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(status: status);
      state = Map.from(_updateQueue);
    }
  }

  /// Update the progress of a project in the queue
  void _updateProgress(String projectId, double progress) {
    if (!ref.mounted) return;
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
    if (!ref.mounted) return;
    final info = _updateQueue[projectId];
    if (info != null) {
      _updateQueue[projectId] = info.copyWith(
        status: status,
        errorMessage: () => errorMessage,
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
    if (!ref.mounted) return;
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
      final steamService = ref.read(steamCmdServiceProvider);
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
      // Clear the stale error explicitly via the ValueGetter sentinel.
      _updateQueue[projectId] = info.copyWith(
        status: ModUpdateStatus.pending,
        errorMessage: () => null,
      );
      state = Map.from(_updateQueue);

      // Queue behind any in-flight update so we don't cancel its progress
      // subscription or overwrite `_currentProjectId` mid-download.
      await _runExclusive(() => _updateProject(projectId));
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
