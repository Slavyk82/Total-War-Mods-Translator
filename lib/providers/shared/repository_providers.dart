import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/domain/game_installation.dart';
import '../../models/domain/language.dart';
import '../../repositories/compilation_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/glossary_repository.dart';
import '../../repositories/language_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../../services/service_locator.dart';

part 'repository_providers.g.dart';

@Riverpod(keepAlive: true)
ProjectRepository projectRepository(Ref ref) =>
    ServiceLocator.get<ProjectRepository>();

@Riverpod(keepAlive: true)
ProjectLanguageRepository projectLanguageRepository(Ref ref) =>
    ServiceLocator.get<ProjectLanguageRepository>();

@Riverpod(keepAlive: true)
LanguageRepository languageRepository(Ref ref) =>
    ServiceLocator.get<LanguageRepository>();

@Riverpod(keepAlive: true)
GameInstallationRepository gameInstallationRepository(Ref ref) =>
    ServiceLocator.get<GameInstallationRepository>();

@Riverpod(keepAlive: true)
GlossaryRepository glossaryRepository(Ref ref) =>
    ServiceLocator.get<GlossaryRepository>();

@Riverpod(keepAlive: true)
CompilationRepository compilationRepository(Ref ref) =>
    ServiceLocator.get<CompilationRepository>();

@Riverpod(keepAlive: true)
TranslationVersionRepository translationVersionRepository(Ref ref) =>
    ServiceLocator.get<TranslationVersionRepository>();

@Riverpod(keepAlive: true)
TranslationUnitRepository translationUnitRepository(Ref ref) =>
    ServiceLocator.get<TranslationUnitRepository>();

@Riverpod(keepAlive: true)
WorkshopModRepository workshopModRepository(Ref ref) =>
    ServiceLocator.get<WorkshopModRepository>();

@riverpod
Future<List<Language>> allLanguages(Ref ref) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getAll();
  if (result.isErr) {
    throw Exception('Failed to load languages: ${result.unwrapErr().message}');
  }
  return result.unwrap();
}

@riverpod
Future<List<Language>> activeLanguages(Ref ref) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getActive();
  if (result.isErr) {
    throw Exception('Failed to load languages');
  }
  return result.unwrap();
}

@riverpod
Future<List<GameInstallation>> allGameInstallations(Ref ref) async {
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getAll();
  if (result.isErr) {
    throw Exception('Failed to load game installations');
  }
  return result.unwrap();
}
