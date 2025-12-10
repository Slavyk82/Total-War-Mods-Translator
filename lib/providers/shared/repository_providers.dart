import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/domain/game_installation.dart';
import '../../models/domain/language.dart';
import '../../repositories/compilation_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/language_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../../services/service_locator.dart';

/// Shared repository providers - use these throughout the application
/// instead of defining local providers.
///
/// All providers use ServiceLocator singletons to avoid creating
/// new instances on each read.

// -----------------------------------------------------------------------------
// Repository Providers
// -----------------------------------------------------------------------------

/// Provider for project repository.
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ServiceLocator.get<ProjectRepository>();
});

/// Provider for project language repository.
final projectLanguageRepositoryProvider =
    Provider<ProjectLanguageRepository>((ref) {
  return ServiceLocator.get<ProjectLanguageRepository>();
});

/// Provider for language repository.
final languageRepositoryProvider = Provider<LanguageRepository>((ref) {
  return ServiceLocator.get<LanguageRepository>();
});

/// Provider for game installation repository.
final gameInstallationRepositoryProvider =
    Provider<GameInstallationRepository>((ref) {
  return ServiceLocator.get<GameInstallationRepository>();
});

/// Provider for compilation repository.
final compilationRepositoryProvider = Provider<CompilationRepository>((ref) {
  return ServiceLocator.get<CompilationRepository>();
});

/// Provider for translation version repository.
final translationVersionRepositoryProvider =
    Provider<TranslationVersionRepository>((ref) {
  return ServiceLocator.get<TranslationVersionRepository>();
});

/// Provider for translation unit repository.
final translationUnitRepositoryProvider =
    Provider<TranslationUnitRepository>((ref) {
  return ServiceLocator.get<TranslationUnitRepository>();
});

/// Provider for workshop mod repository.
final workshopModRepositoryProvider = Provider<WorkshopModRepository>((ref) {
  return ServiceLocator.get<WorkshopModRepository>();
});

// -----------------------------------------------------------------------------
// Common Data Providers
// -----------------------------------------------------------------------------

/// Provider for all languages (including inactive).
final allLanguagesProvider = FutureProvider<List<Language>>((ref) async {
  try {
    final langRepo = ref.watch(languageRepositoryProvider);
    final result = await langRepo.getAll();

    if (result.isErr) {
      final error = result.unwrapErr();
      throw Exception('Failed to load languages: ${error.message}');
    }

    return result.unwrap();
  } catch (e) {
    throw Exception('Error loading languages: $e');
  }
});

/// Provider for active languages only.
final activeLanguagesProvider = FutureProvider<List<Language>>((ref) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getActive();

  if (result.isErr) {
    throw Exception('Failed to load languages');
  }

  return result.unwrap();
});

/// Provider for all game installations.
final allGameInstallationsProvider =
    FutureProvider<List<GameInstallation>>((ref) async {
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getAll();

  if (result.isErr) {
    throw Exception('Failed to load game installations');
  }

  return result.unwrap();
});
