import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';

/// Result of project creation
sealed class ProjectCreationResult {}

/// Project was created successfully
class ProjectCreated extends ProjectCreationResult {
  final String projectId;
  final String projectName;
  final String packFilePath;

  ProjectCreated({
    required this.projectId,
    required this.projectName,
    required this.packFilePath,
  });
}

/// Project creation was skipped (no localization files found)
class ProjectCreationSkipped extends ProjectCreationResult {
  final String reason;

  ProjectCreationSkipped(this.reason);
}

/// Project creation failed
class ProjectCreationFailed extends ProjectCreationResult {
  final String error;

  ProjectCreationFailed(this.error);
}

/// Validation result for project creation prerequisites
sealed class ProjectValidationResult {}

/// Validation passed
class ValidationPassed extends ProjectValidationResult {
  final String schemaPath;
  final GameInstallation gameInstallation;
  final String outputFolder;

  ValidationPassed({
    required this.schemaPath,
    required this.gameInstallation,
    required this.outputFolder,
  });
}

/// Validation failed
class ValidationFailed extends ProjectValidationResult {
  final String error;

  ValidationFailed(this.error);
}

/// Service for creating translation projects from mods
///
/// Handles the business logic for creating projects from both
/// Steam Workshop mods and local .pack files.
class ModsProjectService {
  final ProjectRepository _projectRepo;
  final WorkshopModRepository _workshopModRepo;
  final LanguageRepository _languageRepo;
  final ProjectLanguageRepository _projectLanguageRepo;
  final SettingsService _settingsService;

  ModsProjectService({
    required ProjectRepository projectRepository,
    required WorkshopModRepository workshopModRepository,
    required LanguageRepository languageRepository,
    required ProjectLanguageRepository projectLanguageRepository,
    required SettingsService settingsService,
  })  : _projectRepo = projectRepository,
        _workshopModRepo = workshopModRepository,
        _languageRepo = languageRepository,
        _projectLanguageRepo = projectLanguageRepository,
        _settingsService = settingsService;

  /// Factory constructor using ServiceLocator
  factory ModsProjectService.create({
    required ProjectRepository projectRepository,
  }) {
    return ModsProjectService(
      projectRepository: projectRepository,
      workshopModRepository: ServiceLocator.get<WorkshopModRepository>(),
      languageRepository: ServiceLocator.get<LanguageRepository>(),
      projectLanguageRepository: ServiceLocator.get<ProjectLanguageRepository>(),
      settingsService: ServiceLocator.get<SettingsService>(),
    );
  }

  /// Validate prerequisites for creating a project from a workshop mod
  Future<ProjectValidationResult> validateWorkshopMod({
    required DetectedMod mod,
    required List<GameInstallation> gameInstallations,
  }) async {
    // Validate RPFM schema path
    final schemaPath = await _settingsService.getString('rpfm_schema_path');
    if (schemaPath.isEmpty) {
      return ValidationFailed(
        'RPFM schema path is not configured. Please configure it in Settings > RPFM Tool.',
      );
    }

    // Load workshop mod data
    final modResult = await _workshopModRepo.getByWorkshopId(mod.workshopId);
    if (modResult.isErr) {
      return ValidationFailed('Failed to load mod data: ${modResult.error}');
    }

    final workshopMod = modResult.unwrap();

    // Find game installation matching the mod's appId
    final matchingGame = gameInstallations.firstWhere(
      (game) =>
          game.steamAppId != null &&
          int.tryParse(game.steamAppId!) == workshopMod.appId,
      orElse: () => gameInstallations.isNotEmpty
          ? gameInstallations.first
          : throw StateError('No games found'),
    );

    if (matchingGame.installationPath == null) {
      return ValidationFailed('Game installation path is not configured');
    }

    final outputFolder = path.join(matchingGame.installationPath!, 'data');

    return ValidationPassed(
      schemaPath: schemaPath,
      gameInstallation: matchingGame,
      outputFolder: outputFolder,
    );
  }

  /// Validate prerequisites for creating a project from a local pack file
  Future<ProjectValidationResult> validateLocalPack({
    required String packFilePath,
    required ConfiguredGame selectedGame,
    required List<GameInstallation> gameInstallations,
  }) async {
    // Validate RPFM schema path
    final schemaPath = await _settingsService.getString('rpfm_schema_path');
    if (schemaPath.isEmpty) {
      return ValidationFailed(
        'RPFM schema path is not configured. Please configure it in Settings > RPFM Tool.',
      );
    }

    // Find game installation matching the selected game
    final matchingGame = gameInstallations.firstWhere(
      (game) => game.gameCode == selectedGame.code,
      orElse: () => gameInstallations.isNotEmpty
          ? gameInstallations.first
          : throw StateError('No games found'),
    );

    if (matchingGame.installationPath == null) {
      return ValidationFailed('Game installation path is not configured');
    }

    final outputFolder = path.join(matchingGame.installationPath!, 'data');

    return ValidationPassed(
      schemaPath: schemaPath,
      gameInstallation: matchingGame,
      outputFolder: outputFolder,
    );
  }

  /// Create a project from a detected workshop mod
  ///
  /// Returns the project ID if created successfully, null otherwise.
  Future<String?> createProjectFromMod({
    required DetectedMod mod,
    required GameInstallation gameInstallation,
    required String outputFolder,
  }) async {
    const uuid = Uuid();
    final projectId = uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final metadata = ProjectMetadata(
      modTitle: mod.name,
      modImageUrl: mod.imageUrl,
    );

    final project = Project(
      id: projectId,
      name: mod.name,
      modSteamId: mod.workshopId,
      gameInstallationId: gameInstallation.id,
      sourceFilePath: mod.packFilePath,
      outputFilePath: outputFolder,
      batchSize: 25,
      parallelBatches: 3,
      createdAt: now,
      updatedAt: now,
      metadata: metadata.toJsonString(),
    );

    final createResult = await _projectRepo.insert(project);
    if (createResult.isErr) {
      return null;
    }

    // Add favorite language to the project
    await _addDefaultLanguage(projectId, now, uuid);

    return projectId;
  }

  /// Create a project from a local pack file
  ///
  /// Returns the project ID if created successfully, null otherwise.
  Future<String?> createProjectFromLocalPack({
    required String packFilePath,
    required String projectName,
    required GameInstallation gameInstallation,
    required String outputFolder,
  }) async {
    const uuid = Uuid();
    final projectId = uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final metadata = ProjectMetadata(
      modTitle: projectName,
      modImageUrl: null,
    );

    final project = Project(
      id: projectId,
      name: projectName,
      modSteamId: null, // Not linked to Steam Workshop
      gameInstallationId: gameInstallation.id,
      sourceFilePath: packFilePath,
      outputFilePath: outputFolder,
      batchSize: 25,
      parallelBatches: 3,
      createdAt: now,
      updatedAt: now,
      metadata: metadata.toJsonString(),
    );

    final createResult = await _projectRepo.insert(project);
    if (createResult.isErr) {
      return null;
    }

    // Add favorite language to the project
    await _addDefaultLanguage(projectId, now, uuid);

    return projectId;
  }

  /// Delete a project (used when initialization fails)
  Future<void> deleteProject(String projectId) async {
    await _projectRepo.delete(projectId);
  }

  /// Add the user's default target language to a project
  Future<void> _addDefaultLanguage(String projectId, int now, Uuid uuid) async {
    final favoriteLanguageCode = await _settingsService.getString(
      SettingsKeys.defaultTargetLanguage,
      defaultValue: SettingsKeys.defaultTargetLanguageValue,
    );

    final languageResult = await _languageRepo.getByCode(favoriteLanguageCode);
    if (languageResult.isOk) {
      final language = languageResult.unwrap();
      final projectLanguage = ProjectLanguage(
        id: uuid.v4(),
        projectId: projectId,
        languageId: language.id,
        createdAt: now,
        updatedAt: now,
      );
      await _projectLanguageRepo.insert(projectLanguage);
    }
  }
}
