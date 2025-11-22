import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';
import 'package:twmt/services/mods/game_installation_sync_service.dart';
import 'package:twmt/providers/selected_game_provider.dart';

part 'mod_list_provider.g.dart';

/// Provides list of detected mods after scanning Workshop folder (without creating projects)
@riverpod
Future<List<DetectedMod>> detectedMods(Ref ref) async {
  final gameInstallationSyncService = ServiceLocator.get<GameInstallationSyncService>();
  final workshopScanner = ServiceLocator.get<WorkshopScannerService>();
  
  // Watch the selected game to trigger rescan when it changes
  final selectedGame = await ref.watch(selectedGameProvider.future);
  
  // If a game is selected, sync it to database and scan its Workshop folder
  if (selectedGame != null) {
    // First, sync the game from settings to database
    final syncResult = await gameInstallationSyncService.syncGame(selectedGame.code);
    
    // Only scan if sync was successful
    if (syncResult is Ok) {
      // Scan Workshop folder and return detected mods
      final scanResult = await workshopScanner.scanMods(selectedGame.code);
      return scanResult.when(
        ok: (mods) => mods,
        err: (_) => <DetectedMod>[],
      );
    }
  }
  
  // No game selected or sync failed
  return <DetectedMod>[];
}

/// Provides list of all projects from database
@riverpod
Future<List<Project>> allProjects(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  
  // Return all projects from database
  final result = await projectRepo.getAll();

  return result.when(
    ok: (projects) => projects,
    err: (_) => <Project>[],
  );
}

/// Checks if a mod has an update available
@riverpod
Future<bool> modUpdateAvailable(Ref ref, String projectId) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  
  final result = await projectRepo.getById(projectId);
  
  return result.when(
    ok: (project) => project.sourceModUpdated != null,
    err: (_) => false,
  );
}

/// Provides list of projects with available updates
@riverpod
Future<List<Project>> modsWithUpdates(Ref ref) async {
  final allProjectsList = await ref.watch(allProjectsProvider.future);
  final projectsWithUpdates = <Project>[];

  for (final project in allProjectsList) {
    if (project.modSteamId != null) {
      final hasUpdate = await ref.watch(modUpdateAvailableProvider(project.id).future);
      if (hasUpdate) {
        projectsWithUpdates.add(project);
      }
    }
  }

  return projectsWithUpdates;
}

/// Provider for update banner visibility state
@riverpod
class UpdateBannerVisible extends _$UpdateBannerVisible {
  static const String _prefsKey = 'update_banner_dismissed_timestamp';

  @override
  Future<bool> build() async {
    // Check if there are updates available
    final modsWithUpdatesList = await ref.watch(modsWithUpdatesProvider.future);

    if (modsWithUpdatesList.isEmpty) {
      return false;
    }

    // Check if user has dismissed the banner
    final prefs = await SharedPreferences.getInstance();
    final dismissedTimestamp = prefs.getInt(_prefsKey) ?? 0;

    // Show banner if it was never dismissed, or if it was dismissed more than 24 hours ago
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hoursSinceDismissal = (now - dismissedTimestamp) ~/ 3600;

    return hoursSinceDismissal >= 24 || dismissedTimestamp == 0;
  }

  /// Dismiss the banner
  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await prefs.setInt(_prefsKey, now);

    // Refresh the state
    ref.invalidateSelf();
  }

  /// Reset dismissal (show banner again)
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);

    // Refresh the state
    ref.invalidateSelf();
  }
}

