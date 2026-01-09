import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/services/glossary/models/glossary.dart';

// ============================================================================
// Mock Models
// ============================================================================

/// Creates a mock project for testing
Project createMockProject({
  String? id,
  String? name,
  String? modSteamId,
  String? gameInstallationId,
  String? sourceFilePath,
  String? outputFilePath,
  int? batchSize,
  int? parallelBatches,
  int? createdAt,
  int? updatedAt,
  String? metadata,
  String? projectType,
}) {
  return Project(
    id: id ?? 'test-project-id',
    name: name ?? 'Test Project',
    modSteamId: modSteamId ?? '12345',
    gameInstallationId: gameInstallationId ?? 'game-install-id',
    sourceFilePath: sourceFilePath ?? 'C:/path/to/source.pack',
    outputFilePath: outputFilePath ?? 'C:/path/to/output',
    batchSize: batchSize ?? 25,
    parallelBatches: parallelBatches ?? 3,
    createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    metadata: metadata,
    projectType: projectType ?? 'mod',
  );
}

/// Creates a mock language for testing
Language createMockLanguage({
  String? id,
  String? name,
  String? code,
  String? nativeName,
  bool? isActive,
}) {
  return Language(
    id: id ?? 'lang-id',
    name: name ?? 'French',
    code: code ?? 'fr',
    nativeName: nativeName ?? 'Français',
    isActive: isActive ?? true,
  );
}

/// Creates a mock detected mod for testing
DetectedMod createMockDetectedMod({
  String? workshopId,
  String? name,
  String? imageUrl,
  String? packFilePath,
  bool? isAlreadyImported,
  bool? isHidden,
  int? timeUpdated,
}) {
  return DetectedMod(
    workshopId: workshopId ?? 'workshop-123',
    name: name ?? 'Test Mod',
    imageUrl: imageUrl,
    packFilePath: packFilePath ?? 'C:/path/to/mod.pack',
    isAlreadyImported: isAlreadyImported ?? false,
    isHidden: isHidden ?? false,
    timeUpdated: timeUpdated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

/// Creates a mock game installation for testing
GameInstallation createMockGameInstallation({
  String? id,
  String? gameCode,
  String? gameName,
  String? installationPath,
  String? steamAppId,
  int? createdAt,
  int? updatedAt,
}) {
  return GameInstallation(
    id: id ?? 'game-id',
    gameCode: gameCode ?? 'wh3',
    gameName: gameName ?? 'Total War: WARHAMMER III',
    installationPath: installationPath ?? 'C:/Games/TotalWar',
    steamAppId: steamAppId ?? '1142710',
    createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

/// Creates a mock glossary for testing
Glossary createMockGlossary({
  String? id,
  String? name,
  String? description,
  bool? isGlobal,
  String? gameInstallationId,
  String? targetLanguageId,
  int? entryCount,
  int? createdAt,
  int? updatedAt,
}) {
  return Glossary(
    id: id ?? 'glossary-id',
    name: name ?? 'Test Glossary',
    description: description ?? 'Test glossary description',
    isGlobal: isGlobal ?? true,
    gameInstallationId: gameInstallationId,
    targetLanguageId: targetLanguageId ?? 'fr',
    entryCount: entryCount ?? 100,
    createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

// ============================================================================
// Mock Lists for Testing
// ============================================================================

/// Creates a list of mock projects
List<Project> createMockProjectList({int count = 3}) {
  return List.generate(
    count,
    (index) => createMockProject(
      id: 'project-$index',
      name: 'Test Project $index',
      modSteamId: '${12345 + index}',
    ),
  );
}

/// Creates a list of mock languages
List<Language> createMockLanguageList() {
  return [
    createMockLanguage(id: 'en', name: 'English', code: 'en'),
    createMockLanguage(id: 'fr', name: 'French', code: 'fr'),
    createMockLanguage(id: 'de', name: 'German', code: 'de'),
    createMockLanguage(id: 'es', name: 'Spanish', code: 'es'),
  ];
}

/// Creates a list of mock detected mods
List<DetectedMod> createMockDetectedModList({int count = 5}) {
  return List.generate(
    count,
    (index) => createMockDetectedMod(
      workshopId: 'workshop-${1000 + index}',
      name: 'Test Mod $index',
      isAlreadyImported: index % 2 == 0,
    ),
  );
}

/// Creates a list of mock glossaries
List<Glossary> createMockGlossaryList({int count = 3}) {
  return List.generate(
    count,
    (index) => createMockGlossary(
      id: 'glossary-$index',
      name: 'Glossary $index',
      entryCount: 50 * (index + 1),
    ),
  );
}
