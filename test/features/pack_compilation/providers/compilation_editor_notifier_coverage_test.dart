// Coverage for [CompilationEditorNotifier] beyond `saveCompilation`:
// the easy state mutations, `updateLanguage`, `cancelCompilation`, and the
// large `generatePack` flow (happy path + early-return / failure branches).
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;

import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';
import 'package:twmt/features/pack_compilation/providers/compilation_conflict_providers.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/events/activity_event.dart';
import 'package:twmt/providers/activity_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/i_pack_image_generator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockCompilationRepository extends Mock implements CompilationRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockLocFileService extends Mock implements ILocFileService {}

class _MockRpfmService extends Mock implements IRpfmService {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockPackImageGeneratorService extends Mock
    implements IPackImageGeneratorService {}

class _MockActivityLogger extends Mock implements ActivityLogger {}

class _FakeCompilation extends Fake implements Compilation {}

/// Overrides [compilationConflictAnalysisProvider] to expose a fixed analysis
/// so `_buildExcludedKeysByProject` has data to iterate.
class _FixedAnalysisNotifier extends CompilationConflictAnalysis {
  _FixedAnalysisNotifier(this._result);
  final ConflictAnalysisResult _result;
  @override
  AsyncValue<ConflictAnalysisResult?> build() => AsyncData(_result);
}

ConflictEntry _entry(String projectId) => ConflictEntry(
      projectId: projectId,
      projectName: projectId,
      unitId: 'unit-$projectId',
      sourceText: 'src',
    );

CompilationConflict _conflict(String id, String key) => CompilationConflict(
      id: id,
      key: key,
      conflictType: CompilationConflictType.keyCollisionDifferentSource,
      firstEntry: _entry('proj-1'),
      secondEntry: _entry('proj-2'),
    );

Language _language() => const Language(
      id: 'lang-fr',
      code: 'fr',
      name: 'French',
      nativeName: 'Francais',
    );

Project _project(String id) => Project(
      id: id,
      name: 'Project $id',
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCompilation());
    registerFallbackValue(ActivityEventType.packCompiled);
  });

  late _MockCompilationRepository compilationRepo;
  late _MockLanguageRepository languageRepo;
  late _MockProjectRepository projectRepo;
  late _MockGameInstallationRepository gameRepo;
  late _MockLocFileService locFileService;
  late _MockRpfmService rpfmService;
  late _MockSettingsService settingsService;
  late _MockPackImageGeneratorService imageGenerator;
  late _MockActivityLogger activityLogger;
  late Directory gameDir;
  late Directory tsvSourceDir;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
      languageRepositoryProvider.overrideWithValue(languageRepo),
      projectRepositoryProvider.overrideWithValue(projectRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
      locFileServiceProvider.overrideWithValue(locFileService),
      rpfmServiceProvider.overrideWithValue(rpfmService),
      settingsServiceProvider.overrideWithValue(settingsService),
      packImageGeneratorServiceProvider.overrideWithValue(imageGenerator),
      activityLoggerProvider.overrideWithValue(activityLogger),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    compilationRepo = _MockCompilationRepository();
    languageRepo = _MockLanguageRepository();
    projectRepo = _MockProjectRepository();
    gameRepo = _MockGameInstallationRepository();
    locFileService = _MockLocFileService();
    rpfmService = _MockRpfmService();
    settingsService = _MockSettingsService();
    imageGenerator = _MockPackImageGeneratorService();
    activityLogger = _MockActivityLogger();

    gameDir = Directory.systemTemp.createTempSync('twmt_game_');
    tsvSourceDir = Directory.systemTemp.createTempSync('twmt_tsv_');
    addTearDown(() {
      if (gameDir.existsSync()) gameDir.deleteSync(recursive: true);
      if (tsvSourceDir.existsSync()) tsvSourceDir.deleteSync(recursive: true);
    });

    // Default: updateLanguage looks up the language to derive a prefix.
    when(() => languageRepo.getById(any())).thenAnswer(
      (_) async => Ok<Language, TWMTDatabaseException>(_language()),
    );
    when(() => settingsService.getPackPrefix()).thenAnswer((_) async => '!!!');
  });

  /// Fill the form so `canCompile` passes (2 projects, name, prefix, etc.).
  Future<void> fillForm(ProviderContainer container) async {
    final notifier = container.read(compilationEditorProvider.notifier);
    notifier
      ..updateName('My compilation')
      ..updatePackName('my_pack');
    await notifier.updateLanguage('lang-fr');
    notifier
      ..updatePrefix('!!!_fr_compilation_twmt_')
      ..toggleProject('proj-1')
      ..toggleProject('proj-2');
  }

  GeneratedLocFile genFile(String name, String internalPath) {
    final file = File(path.join(tsvSourceDir.path, name));
    file.writeAsStringSync('Loc\tKey\tText\nmeta\trow\there\nk1\tv1\n');
    return GeneratedLocFile(tsvPath: file.path, internalPath: internalPath);
  }

  // ----- Easy state mutations -----------------------------------------------

  group('state mutations', () {
    test('reset / updaters / toggles / clearMessages', () async {
      final container = makeContainer();
      final n = container.read(compilationEditorProvider.notifier);

      n
        ..updateName('Name')
        ..updatePrefix('pre_')
        ..updatePackName('pack');
      expect(container.read(compilationEditorProvider).name, 'Name');
      expect(container.read(compilationEditorProvider).prefix, 'pre_');
      expect(container.read(compilationEditorProvider).packName, 'pack');

      n.toggleProject('a');
      expect(container.read(compilationEditorProvider).selectedProjectIds,
          {'a'});
      n.toggleProject('a'); // remove
      expect(container.read(compilationEditorProvider).selectedProjectIds,
          isEmpty);

      n
        ..toggleProject('a')
        ..toggleProject('b')
        ..deselectAllProjects();
      expect(container.read(compilationEditorProvider).selectedProjectIds,
          isEmpty);

      n.clearMessages();
      expect(container.read(compilationEditorProvider).errorMessage, isNull);

      expect(container.read(compilationEditorProvider).generatePackImage,
          isTrue);
      n.toggleGeneratePackImage();
      expect(container.read(compilationEditorProvider).generatePackImage,
          isFalse);

      n.reset();
      expect(container.read(compilationEditorProvider).name, isEmpty);
    });

    test('loadCompilation hydrates state from details', () {
      final container = makeContainer();
      container.read(compilationEditorProvider.notifier).loadCompilation(
            CompilationWithDetails(
              compilation: Compilation(
                id: 'comp-9',
                name: 'Loaded',
                prefix: 'pfx_',
                packName: 'packy',
                gameInstallationId: 'install-wh3',
                languageId: 'lang-fr',
                createdAt: 0,
                updatedAt: 0,
              ),
              projects: [_project('proj-1')],
              projectCount: 1,
            ),
          );
      final state = container.read(compilationEditorProvider);
      expect(state.compilationId, 'comp-9');
      expect(state.name, 'Loaded');
      expect(state.selectedProjectIds, {'proj-1'});
    });
  });

  group('updateLanguage', () {
    test('null clears prefix + projects', () async {
      final container = makeContainer();
      final n = container.read(compilationEditorProvider.notifier);
      n
        ..updatePrefix('something')
        ..toggleProject('a');
      await n.updateLanguage(null);
      final state = container.read(compilationEditorProvider);
      expect(state.selectedLanguageId, isNull);
      expect(state.prefix, isEmpty);
      expect(state.selectedProjectIds, isEmpty);
    });

    test('non-null Ok derives prefix from language code + marker', () async {
      final container = makeContainer();
      await container
          .read(compilationEditorProvider.notifier)
          .updateLanguage('lang-fr');
      final state = container.read(compilationEditorProvider);
      expect(state.selectedLanguageId, 'lang-fr');
      expect(state.prefix, '!!!_fr_compilation_twmt_');
    });

    test('non-null Err keeps the existing prefix', () async {
      when(() => languageRepo.getById(any())).thenAnswer(
        (_) async => const Err<Language, TWMTDatabaseException>(
          TWMTDatabaseException('missing'),
        ),
      );
      final container = makeContainer();
      final n = container.read(compilationEditorProvider.notifier);
      n.updatePrefix('keep_me_');
      await n.updateLanguage('lang-fr');
      expect(container.read(compilationEditorProvider).prefix, 'keep_me_');
    });
  });

  group('cancelCompilation', () {
    test('no-op when not compiling', () async {
      final container = makeContainer();
      await container.read(compilationEditorProvider.notifier).cancelCompilation();
      expect(container.read(compilationEditorProvider).isCancelled, isFalse);
      verifyNever(() => rpfmService.cancel());
    });
  });

  // ----- generatePack -------------------------------------------------------

  group('generatePack', () {
    test('returns null early when canCompile is false', () async {
      final container = makeContainer();
      // Only one project -> canCompile false (needs >= 2).
      final n = container.read(compilationEditorProvider.notifier);
      n
        ..updateName('n')
        ..updatePackName('p')
        ..updatePrefix('pre_')
        ..toggleProject('proj-1');
      final result = await n.generatePack('install-wh3');
      expect(result, isNull);
      verifyNever(() => compilationRepo.insert(any()));
    });

    test('happy path generates pack and reports success', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        return Ok<List<GeneratedLocFile>, FileServiceException>(
          [genFile('$pid.tsv', 'text/db/$pid.loc')],
        );
      });
      when(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((inv) async {
        // Drive the progress callback once.
        final cb = inv.namedArguments[#onProgress] as PackProgressCallback?;
        cb?.call(1, 2, 'file.loc');
        return const Ok<String, RpfmServiceException>('ok');
      });
      when(() => imageGenerator.ensurePackImage(
            packFileName: any(named: 'packFileName'),
            gameDataPath: any(named: 'gameDataPath'),
            languageCode: any(named: 'languageCode'),
            generateImage: any(named: 'generateImage'),
            useAppIcon: any(named: 'useAppIcon'),
          )).thenAnswer(
        (_) async => const Ok<String?, FileServiceException>(null),
      );
      when(() => compilationRepo.updateAfterGeneration(any(), any())).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(
          Compilation(
            id: 'c',
            name: 'n',
            prefix: 'p',
            packName: 'pn',
            gameInstallationId: 'install-wh3',
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => activityLogger.log(any(),
          projectId: any(named: 'projectId'),
          gameCode: any(named: 'gameCode'),
          payload: any(named: 'payload'))).thenAnswer((_) async {});

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNotNull);
      final state = container.read(compilationEditorProvider);
      expect(state.successMessage, contains('Pack generated'));
      expect(state.isCompiling, isFalse);
      expect(state.progress, 1.0);
    });

    test('with generatePackImage toggled on calls the image generator',
        () async {
      final container = makeContainer();
      await fillForm(container);
      // Default generatePackImage is true, so leave it on.

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        return Ok<List<GeneratedLocFile>, FileServiceException>(
          [genFile('$pid.tsv', 'text/db/$pid.loc')],
        );
      });
      when(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Ok<String, RpfmServiceException>('ok'),
      );
      when(() => imageGenerator.ensurePackImage(
            packFileName: any(named: 'packFileName'),
            gameDataPath: any(named: 'gameDataPath'),
            languageCode: any(named: 'languageCode'),
            generateImage: any(named: 'generateImage'),
            useAppIcon: any(named: 'useAppIcon'),
          )).thenAnswer(
        (_) async => const Ok<String?, FileServiceException>(null),
      );
      when(() => compilationRepo.updateAfterGeneration(any(), any())).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(
          Compilation(
            id: 'c',
            name: 'n',
            prefix: 'p',
            packName: 'pn',
            gameInstallationId: 'install-wh3',
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => activityLogger.log(any(),
          projectId: any(named: 'projectId'),
          gameCode: any(named: 'gameCode'),
          payload: any(named: 'payload'))).thenAnswer((_) async {});

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNotNull);
      verify(() => imageGenerator.ensurePackImage(
            packFileName: any(named: 'packFileName'),
            gameDataPath: any(named: 'gameDataPath'),
            languageCode: any(named: 'languageCode'),
            generateImage: any(named: 'generateImage'),
            useAppIcon: any(named: 'useAppIcon'),
          )).called(1);
    });

    test('nothing-to-compile when no loc files generated', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      // Empty list for one project, Err for the other -> total 0.
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        if (pid == 'proj-1') {
          return const Ok<List<GeneratedLocFile>, FileServiceException>([]);
        }
        return const Err<List<GeneratedLocFile>, FileServiceException>(
          FileServiceException('boom'),
        );
      });

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      final state = container.read(compilationEditorProvider);
      expect(state.errorMessage, contains('nothing to compile'));
      expect(state.isCompiling, isFalse);
      verifyNever(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          ));
    });

    test('game installation load failure surfaces error', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => const Err<GameInstallation, TWMTDatabaseException>(
          TWMTDatabaseException('no game'),
        ),
      );

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      final state = container.read(compilationEditorProvider);
      expect(state.errorMessage, contains('Failed to load game installation'));
      expect(state.isCompiling, isFalse);
    });

    test('language load failure surfaces error', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      // updateLanguage during fillForm already used the Ok stub; now make the
      // language lookup inside generatePack fail.
      when(() => languageRepo.getById('lang-fr')).thenAnswer(
        (_) async => const Err<Language, TWMTDatabaseException>(
          TWMTDatabaseException('no lang'),
        ),
      );

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      expect(container.read(compilationEditorProvider).errorMessage,
          contains('Failed to load language'));
    });

    test('createPack failure routes through catch block', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        return Ok<List<GeneratedLocFile>, FileServiceException>(
          [genFile('$pid.tsv', 'text/db/$pid.loc')],
        );
      });
      when(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Err<String, RpfmServiceException>(
          RpfmServiceException('rpfm exploded'),
        ),
      );

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      final state = container.read(compilationEditorProvider);
      expect(state.errorMessage, contains('Failed to create pack file'));
      expect(state.isCompiling, isFalse);
      expect(state.progress, 0.0);
    });

    test('save failure aborts before generation', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Err<void, TWMTDatabaseException>(
          TWMTDatabaseException('locked'),
        ),
      );

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      verifyNever(() => gameRepo.getById(any()));
    });

    test('updateAfterGeneration failure routes through catch block', () async {
      final container = makeContainer();
      await fillForm(container);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        return Ok<List<GeneratedLocFile>, FileServiceException>(
          [genFile('$pid.tsv', 'text/db/$pid.loc')],
        );
      });
      when(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Ok<String, RpfmServiceException>('ok'),
      );
      // generatePackImage default true -> stub the image generator too.
      when(() => imageGenerator.ensurePackImage(
            packFileName: any(named: 'packFileName'),
            gameDataPath: any(named: 'gameDataPath'),
            languageCode: any(named: 'languageCode'),
            generateImage: any(named: 'generateImage'),
            useAppIcon: any(named: 'useAppIcon'),
          )).thenAnswer(
        (_) async => const Ok<String?, FileServiceException>(null),
      );
      when(() => compilationRepo.updateAfterGeneration(any(), any())).thenAnswer(
        (_) async => const Err<Compilation, TWMTDatabaseException>(
          TWMTDatabaseException('cannot record'),
        ),
      );

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNull);
      expect(container.read(compilationEditorProvider).errorMessage,
          contains('Failed to record generated pack'));
    });

    test('applies conflict resolutions (useFirst/useSecond/skip)', () async {
      final analysis = ConflictAnalysisResult(
        conflicts: [
          _conflict('c-first', 'KEY_A'),
          _conflict('c-second', 'KEY_B'),
          _conflict('c-skip', 'KEY_C'),
        ],
        summary: const ConflictSummary(
          totalCount: 3,
          keyCollisionCount: 3,
          translationConflictCount: 0,
          duplicateCount: 0,
        ),
        analyzedAt: 0,
        analyzedProjectIds: const ['proj-1', 'proj-2'],
        languageId: 'lang-fr',
      );
      final container = ProviderContainer(overrides: [
        compilationRepositoryProvider.overrideWithValue(compilationRepo),
        languageRepositoryProvider.overrideWithValue(languageRepo),
        projectRepositoryProvider.overrideWithValue(projectRepo),
        gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
        locFileServiceProvider.overrideWithValue(locFileService),
        rpfmServiceProvider.overrideWithValue(rpfmService),
        settingsServiceProvider.overrideWithValue(settingsService),
        packImageGeneratorServiceProvider.overrideWithValue(imageGenerator),
        activityLoggerProvider.overrideWithValue(activityLogger),
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        compilationConflictAnalysisProvider
            .overrideWith(() => _FixedAnalysisNotifier(analysis)),
      ]);
      addTearDown(container.dispose);

      // Keep the auto-dispose conflict providers alive for the whole flow;
      // otherwise they reset to defaults across the `await` in generatePack.
      container.listen(compilationConflictAnalysisProvider, (prev, next) {});
      container.listen(
          compilationConflictResolutionsStateProvider, (prev, next) {});

      await fillForm(container);
      // Resolve each conflict differently to exercise all three switch arms.
      container
          .read(compilationConflictResolutionsStateProvider.notifier)
          .setResolution('c-first', CompilationConflictResolution.useFirst,
              'proj-1');
      container
          .read(compilationConflictResolutionsStateProvider.notifier)
          .setResolution('c-second', CompilationConflictResolution.useSecond,
              'proj-2');
      container
          .read(compilationConflictResolutionsStateProvider.notifier)
          .setResolution(
              'c-skip', CompilationConflictResolution.skip, null);

      when(() => compilationRepo.insert(any())).thenAnswer(
        (inv) async => Ok<Compilation, TWMTDatabaseException>(
          inv.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          GameInstallation(
            id: 'install-wh3',
            gameCode: 'wh3',
            gameName: 'WH3',
            installationPath: gameDir.path,
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => projectRepo.getById(any())).thenAnswer(
        (inv) async => Ok<Project, TWMTDatabaseException>(
          _project(inv.positionalArguments.first as String),
        ),
      );
      when(() => locFileService.generateLocFilesGroupedBySource(
            projectId: any(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: any(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).thenAnswer((inv) async {
        final pid = inv.namedArguments[#projectId] as String;
        return Ok<List<GeneratedLocFile>, FileServiceException>(
          [genFile('$pid.tsv', 'text/db/$pid.loc')],
        );
      });
      when(() => rpfmService.createPack(
            inputDirectory: any(named: 'inputDirectory'),
            outputPackPath: any(named: 'outputPackPath'),
            languageCode: any(named: 'languageCode'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Ok<String, RpfmServiceException>('ok'),
      );
      when(() => imageGenerator.ensurePackImage(
            packFileName: any(named: 'packFileName'),
            gameDataPath: any(named: 'gameDataPath'),
            languageCode: any(named: 'languageCode'),
            generateImage: any(named: 'generateImage'),
            useAppIcon: any(named: 'useAppIcon'),
          )).thenAnswer(
        (_) async => const Ok<String?, FileServiceException>(null),
      );
      when(() => compilationRepo.updateAfterGeneration(any(), any())).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(
          Compilation(
            id: 'c',
            name: 'n',
            prefix: 'p',
            packName: 'pn',
            gameInstallationId: 'install-wh3',
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
      when(() => activityLogger.log(any(),
          projectId: any(named: 'projectId'),
          gameCode: any(named: 'gameCode'),
          payload: any(named: 'payload'))).thenAnswer((_) async {});

      final result = await container
          .read(compilationEditorProvider.notifier)
          .generatePack('install-wh3');

      expect(result, isNotNull);
      // proj-1 loses KEY_B (useSecond) and KEY_C (skip);
      // proj-2 loses KEY_A (useFirst) and KEY_C (skip).
      final captured = verify(() =>
          locFileService.generateLocFilesGroupedBySource(
            projectId: captureAny(named: 'projectId'),
            languageCode: any(named: 'languageCode'),
            validatedOnly: any(named: 'validatedOnly'),
            excludeKeys: captureAny(named: 'excludeKeys'),
            prefix: any(named: 'prefix'),
          )).captured;
      final excludedByProject = <String, Set<String>>{};
      for (var i = 0; i < captured.length; i += 2) {
        excludedByProject[captured[i] as String] =
            captured[i + 1] as Set<String>;
      }
      expect(excludedByProject['proj-1'], {'KEY_B', 'KEY_C'});
      expect(excludedByProject['proj-2'], {'KEY_A', 'KEY_C'});
    });
  });
}
