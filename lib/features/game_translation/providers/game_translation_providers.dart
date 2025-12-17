import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../../providers/selected_game_provider.dart';
import '../../../services/game/game_localization_service.dart';
import '../../projects/providers/projects_screen_providers.dart';

/// Provider for the GameLocalizationService
final gameLocalizationServiceProvider = Provider<GameLocalizationService>((ref) {
  return GetIt.instance<GameLocalizationService>();
});

/// Provider for detected local packs for the selected game installation.
///
/// Returns a list of detected local_*.pack files in the game's data folder.
final detectedLocalPacksProvider =
    FutureProvider.autoDispose<List<DetectedLocalPack>>((ref) async {
  final selectedGame = await ref.watch(selectedGameProvider.future);
  if (selectedGame == null) return [];

  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final gameInstallationResult = await gameRepo.getByGameCode(selectedGame.code);
  if (gameInstallationResult.isErr) return [];

  final installation = gameInstallationResult.unwrap();
  if (installation.installationPath == null) return [];

  final locService = ref.watch(gameLocalizationServiceProvider);
  return await locService.detectLocalizationPacks(installation.installationPath!);
});

/// Provider for game translation projects filtered by selected game.
///
/// Only returns projects with projectType == 'game'.
final gameTranslationProjectsProvider =
    FutureProvider<List<ProjectWithDetails>>((ref) async {
  // Watch translation stats version to refresh when stats change
  ref.watch(translationStatsVersionProvider);

  final selectedGame = await ref.watch(selectedGameProvider.future);
  if (selectedGame == null) return [];

  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);

  // Get game installation for selected game
  final gameInstallationResult = await gameRepo.getByGameCode(selectedGame.code);
  if (gameInstallationResult.isErr) return [];
  final gameInstallation = gameInstallationResult.unwrap();

  // Get game translation projects for this installation
  final projectsResult =
      await projectRepo.getGameTranslationsByInstallation(gameInstallation.id);
  if (projectsResult.isErr) return [];
  final projects = projectsResult.unwrap();

  // Pre-load all languages
  final allLanguagesResult = await langRepo.getAll();
  final languagesMap = <String, dynamic>{};
  if (allLanguagesResult.isOk) {
    for (final lang in allLanguagesResult.unwrap()) {
      languagesMap[lang.id] = lang;
    }
  }

  // Build details for each project
  final List<ProjectWithDetails> projectsWithDetails = [];

  for (final project in projects) {
    // Get project languages
    final langResult = await projectLangRepo.getByProject(project.id);
    final List<ProjectLanguageWithInfo> languagesWithInfo = [];

    if (langResult.isOk) {
      for (final projLang in langResult.unwrap()) {
        final language = languagesMap[projLang.languageId];
        languagesWithInfo.add(ProjectLanguageWithInfo(
          projectLanguage: projLang,
          language: language,
        ));
      }
    }

    projectsWithDetails.add(ProjectWithDetails(
      project: project,
      gameInstallation: gameInstallation,
      languages: languagesWithInfo,
    ));
  }

  return projectsWithDetails;
});

/// Provider to check if the selected game has any detected local packs.
final hasLocalPacksProvider = FutureProvider.autoDispose<bool>((ref) async {
  final packs = await ref.watch(detectedLocalPacksProvider.future);
  return packs.isNotEmpty;
});

/// Provider for available target languages (all languages except the source).
///
/// Takes a source language code and returns all other languages.
final availableTargetLanguagesProvider =
    FutureProvider.family<List<dynamic>, String>((ref, sourceLanguageCode) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getAll();

  if (result.isErr) return [];

  final allLanguages = result.unwrap();
  // Filter out the source language
  return allLanguages
      .where((lang) => lang.code.toLowerCase() != sourceLanguageCode.toLowerCase())
      .toList();
});
