import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/domain/github_release.dart';
import '../../../services/updates/app_update_service.dart';
import '../../../services/service_locator.dart';

part 'update_providers.g.dart';

/// Current application version from pubspec.yaml.
const String appVersion = '1.0.0';

/// Provider for the update service.
@riverpod
AppUpdateService appUpdateService(Ref ref) {
  return ServiceLocator.get<AppUpdateService>();
}

/// State for update checking.
class UpdateCheckState {
  final bool isChecking;
  final GitHubRelease? availableUpdate;
  final String? error;
  final DateTime? lastChecked;

  const UpdateCheckState({
    this.isChecking = false,
    this.availableUpdate,
    this.error,
    this.lastChecked,
  });

  UpdateCheckState copyWith({
    bool? isChecking,
    GitHubRelease? availableUpdate,
    String? error,
    DateTime? lastChecked,
    bool clearUpdate = false,
    bool clearError = false,
  }) {
    return UpdateCheckState(
      isChecking: isChecking ?? this.isChecking,
      availableUpdate: clearUpdate ? null : (availableUpdate ?? this.availableUpdate),
      error: clearError ? null : (error ?? this.error),
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  bool get hasUpdate => availableUpdate != null;
}

/// Notifier for checking app updates.
@riverpod
class UpdateChecker extends _$UpdateChecker {
  @override
  UpdateCheckState build() {
    return const UpdateCheckState();
  }

  /// Check for updates manually.
  Future<void> checkForUpdates() async {
    state = state.copyWith(isChecking: true, clearError: true);

    try {
      final service = ref.read(appUpdateServiceProvider);
      final result = await service.checkForUpdate(appVersion);

      result.when(
        ok: (release) {
          state = state.copyWith(
            isChecking: false,
            availableUpdate: release,
            lastChecked: DateTime.now(),
            clearUpdate: release == null,
          );
        },
        err: (error) {
          state = state.copyWith(
            isChecking: false,
            error: error.message,
            lastChecked: DateTime.now(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        error: 'Failed to check for updates: $e',
        lastChecked: DateTime.now(),
      );
    }
  }

  /// Dismiss the update notification.
  void dismissUpdate() {
    state = state.copyWith(clearUpdate: true);
  }
}

/// State for downloading updates.
class UpdateDownloadState {
  final bool isDownloading;
  final double progress;
  final String? downloadedPath;
  final String? error;

  const UpdateDownloadState({
    this.isDownloading = false,
    this.progress = 0.0,
    this.downloadedPath,
    this.error,
  });

  UpdateDownloadState copyWith({
    bool? isDownloading,
    double? progress,
    String? downloadedPath,
    String? error,
    bool clearPath = false,
    bool clearError = false,
  }) {
    return UpdateDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      downloadedPath: clearPath ? null : (downloadedPath ?? this.downloadedPath),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for downloading updates.
@riverpod
class UpdateDownloader extends _$UpdateDownloader {
  @override
  UpdateDownloadState build() {
    return const UpdateDownloadState();
  }

  /// Download the update installer.
  Future<void> downloadUpdate(GitHubRelease release) async {
    final asset = release.windowsInstaller;
    if (asset == null || asset.isEmpty) {
      state = state.copyWith(error: 'No Windows installer available');
      return;
    }

    state = state.copyWith(
      isDownloading: true,
      progress: 0.0,
      clearError: true,
      clearPath: true,
    );

    try {
      final service = ref.read(appUpdateServiceProvider);
      final result = await service.downloadInstaller(
        asset,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );

      result.when(
        ok: (path) {
          state = state.copyWith(
            isDownloading: false,
            progress: 1.0,
            downloadedPath: path,
          );
        },
        err: (error) {
          state = state.copyWith(
            isDownloading: false,
            error: error.message,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        error: 'Download failed: $e',
      );
    }
  }

  /// Launch the installer and exit the app.
  Future<void> installUpdate() async {
    final path = state.downloadedPath;
    if (path == null) {
      state = state.copyWith(error: 'No installer downloaded');
      return;
    }

    try {
      final service = ref.read(appUpdateServiceProvider);
      final result = await service.launchInstaller(path);

      result.when(
        ok: (_) {
          // Exit the app after launching installer
          exit(0);
        },
        err: (error) {
          state = state.copyWith(error: error.message);
        },
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to launch installer: $e');
    }
  }

  /// Reset download state.
  void reset() {
    state = const UpdateDownloadState();
  }
}

/// Provider that checks for updates on startup.
@riverpod
Future<void> autoUpdateCheck(Ref ref) async {
  // Small delay to not block app startup
  await Future.delayed(const Duration(seconds: 3));
  await ref.read(updateCheckerProvider.notifier).checkForUpdates();
}
