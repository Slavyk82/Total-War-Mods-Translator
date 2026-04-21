// Regression tests for `ModsProjectService._addDefaultLanguage`.
//
// Before Task 3 (Plan 5a), if the user's `default_target_language` setting
// pointed to a code that did not exist in the `languages` table (or was
// inactive), the service silently created a project without any target
// language. The navigator was forwiving about it because it always landed
// on `ProjectDetailScreen` regardless. After Task 3 the editor route now
// rejects projects with no target language and bounces the user back to the
// list, which made the latent bug user-visible.
//
// The fix adds a fallback: try the configured code first, otherwise pick the
// first active language from `LanguageRepository.getActive()`, and if no
// active language is available, skip insertion and log a warning.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/mods/services/mods_project_service.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockWorkshopModRepository extends Mock implements WorkshopModRepository {
}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockSettingsService extends Mock implements SettingsService {}

/// Test logger that records every warning call so we can assert on it.
class _RecordingLogger extends FakeLogger {
  final List<String> warnings = [];

  @override
  void warning(String message, [dynamic data]) {
    warnings.add(message);
  }
}

DetectedMod _detectedMod() => DetectedMod(
      workshopId: '999',
      name: 'Test Mod',
      packFilePath: '/tmp/test.pack',
      imageUrl: null,
      metadata: null,
      timeUpdated: 0,
      localFileLastModified: 0,
    );

GameInstallation _gameInstallation() => const GameInstallation(
      id: 'game-1',
      gameCode: 'wh3',
      gameName: 'Warhammer 3',
      installationPath: '/tmp/game',
      steamAppId: '1142710',
      createdAt: 0,
      updatedAt: 0,
    );

Language _lang({
  required String id,
  required String code,
  bool isActive = true,
}) {
  return Language(
    id: id,
    code: code,
    name: code.toUpperCase(),
    nativeName: code,
    isActive: isActive,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Project(
      id: '',
      name: '',
      gameInstallationId: '',
      sourceFilePath: '',
      outputFilePath: '',
      batchSize: 25,
      parallelBatches: 3,
      createdAt: 0,
      updatedAt: 0,
    ));
    registerFallbackValue(const ProjectLanguage(
      id: '',
      projectId: '',
      languageId: '',
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  late _MockProjectRepository projectRepo;
  late _MockWorkshopModRepository workshopRepo;
  late _MockLanguageRepository languageRepo;
  late _MockProjectLanguageRepository projectLanguageRepo;
  late _MockSettingsService settingsService;
  late _RecordingLogger logger;
  late ModsProjectService service;

  setUp(() {
    projectRepo = _MockProjectRepository();
    workshopRepo = _MockWorkshopModRepository();
    languageRepo = _MockLanguageRepository();
    projectLanguageRepo = _MockProjectLanguageRepository();
    settingsService = _MockSettingsService();
    logger = _RecordingLogger();

    // Default project insert succeeds; individual tests override when needed.
    when(() => projectRepo.insert(any())).thenAnswer(
      (invocation) async =>
          Ok<Project, TWMTDatabaseException>(invocation.positionalArguments.first as Project),
    );

    // Default ProjectLanguage insert succeeds.
    when(() => projectLanguageRepo.insert(any())).thenAnswer(
      (invocation) async => Ok<ProjectLanguage, TWMTDatabaseException>(
        invocation.positionalArguments.first as ProjectLanguage,
      ),
    );

    service = ModsProjectService.create(
      projectRepository: projectRepo,
      workshopModRepository: workshopRepo,
      languageRepository: languageRepo,
      projectLanguageRepository: projectLanguageRepo,
      settingsService: settingsService,
      logger: logger,
    );
  });

  group('ModsProjectService._addDefaultLanguage', () {
    test(
      'inserts the configured default when it exists and is active',
      () async {
        when(() => settingsService.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'fr');
        when(() => languageRepo.getByCode('fr')).thenAnswer(
          (_) async => Ok<Language, TWMTDatabaseException>(
            _lang(id: 'lang-fr', code: 'fr'),
          ),
        );

        final projectId = await service.createProjectFromMod(
          mod: _detectedMod(),
          gameInstallation: _gameInstallation(),
          outputFolder: '/tmp/out',
        );

        expect(projectId, isNotNull);

        // Captures the inserted ProjectLanguage and asserts its languageId
        // matches the configured default.
        final captured = verify(() => projectLanguageRepo.insert(captureAny()))
            .captured
            .cast<ProjectLanguage>();
        expect(captured, hasLength(1));
        expect(captured.single.languageId, 'lang-fr');
        // No fallback → no warning.
        expect(logger.warnings, isEmpty);
        // getActive should not even be consulted when the direct lookup wins.
        verifyNever(() => languageRepo.getActive());
      },
    );

    test(
      'falls back to first active language when configured default is missing',
      () async {
        when(() => settingsService.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'xx');
        when(() => languageRepo.getByCode('xx')).thenAnswer(
          (_) async => Err<Language, TWMTDatabaseException>(
            TWMTDatabaseException('Language not found with code: xx'),
          ),
        );
        when(() => languageRepo.getActive()).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([
            _lang(id: 'lang-en', code: 'en'),
            _lang(id: 'lang-de', code: 'de'),
          ]),
        );

        final projectId = await service.createProjectFromMod(
          mod: _detectedMod(),
          gameInstallation: _gameInstallation(),
          outputFolder: '/tmp/out',
        );

        expect(projectId, isNotNull);

        final captured = verify(() => projectLanguageRepo.insert(captureAny()))
            .captured
            .cast<ProjectLanguage>();
        expect(captured, hasLength(1));
        expect(captured.single.languageId, 'lang-en');
        expect(logger.warnings, hasLength(1));
        expect(logger.warnings.single, contains('"xx"'));
        expect(logger.warnings.single, contains('"en"'));
      },
    );

    test(
      'falls back when configured default exists but is inactive',
      () async {
        when(() => settingsService.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'legacy');
        when(() => languageRepo.getByCode('legacy')).thenAnswer(
          (_) async => Ok<Language, TWMTDatabaseException>(
            _lang(id: 'lang-legacy', code: 'legacy', isActive: false),
          ),
        );
        when(() => languageRepo.getActive()).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([
            _lang(id: 'lang-en', code: 'en'),
          ]),
        );

        final projectId = await service.createProjectFromMod(
          mod: _detectedMod(),
          gameInstallation: _gameInstallation(),
          outputFolder: '/tmp/out',
        );

        expect(projectId, isNotNull);

        final captured = verify(() => projectLanguageRepo.insert(captureAny()))
            .captured
            .cast<ProjectLanguage>();
        expect(captured, hasLength(1));
        expect(captured.single.languageId, 'lang-en');
        expect(logger.warnings, hasLength(1));
      },
    );

    test(
      'no-ops and warns when there is no active language available',
      () async {
        when(() => settingsService.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'xx');
        when(() => languageRepo.getByCode('xx')).thenAnswer(
          (_) async => Err<Language, TWMTDatabaseException>(
            TWMTDatabaseException('Language not found with code: xx'),
          ),
        );
        when(() => languageRepo.getActive()).thenAnswer(
          (_) async =>
              Ok<List<Language>, TWMTDatabaseException>(const <Language>[]),
        );

        final projectId = await service.createProjectFromMod(
          mod: _detectedMod(),
          gameInstallation: _gameInstallation(),
          outputFolder: '/tmp/out',
        );

        // Project itself is still created; only the project_language row is
        // skipped with a warning.
        expect(projectId, isNotNull);
        verifyNever(() => projectLanguageRepo.insert(any()));
        expect(logger.warnings, hasLength(1));
        expect(
          logger.warnings.single,
          contains('No active language available'),
        );
      },
    );

    test(
      'service accepts an ILoggingService',
      () {
        // Compile-time guard: a FakeLogger (no recording) should satisfy the
        // constructor just like the RecordingLogger subclass.
        final ILoggingService any = FakeLogger();
        final s = ModsProjectService.create(
          projectRepository: projectRepo,
          workshopModRepository: workshopRepo,
          languageRepository: languageRepo,
          projectLanguageRepository: projectLanguageRepo,
          settingsService: settingsService,
          logger: any,
        );
        expect(s, isNotNull);
      },
    );
  });
}
