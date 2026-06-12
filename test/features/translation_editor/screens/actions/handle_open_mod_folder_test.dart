import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_base.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_open_folder.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockProjectRepo extends Mock implements ProjectRepository {}

class _MockGameRepo extends Mock implements GameInstallationRepository {}

const _projectId = 'project-1';
const _gameInstallationId = 'game-1';

const _project = Project(
  id: _projectId,
  name: 'My Mod',
  gameInstallationId: _gameInstallationId,
  createdAt: 0,
  updatedAt: 0,
);

GameInstallation _game({String? path}) => GameInstallation(
      id: _gameInstallationId,
      gameCode: 'warhammer_3',
      gameName: 'Warhammer III',
      installationPath: path,
      createdAt: 0,
      updatedAt: 0,
    );

class _OpenFolderActions with EditorActionsBase, EditorActionsOpenFolder {
  _OpenFolderActions({required this.ref, required this.context});
  @override
  final WidgetRef ref;
  @override
  final BuildContext context;
  @override
  String get projectId => _projectId;
  @override
  String get languageId => 'language-fr';
}

class _Harness extends ConsumerStatefulWidget {
  const _Harness({super.key});
  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  _OpenFolderActions buildActions() =>
      _OpenFolderActions(ref: ref, context: context);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _MockProjectRepo projectRepo;
  late _MockGameRepo gameRepo;

  setUp(() {
    projectRepo = _MockProjectRepo();
    gameRepo = _MockGameRepo();
  });

  Future<GlobalKey<_HarnessState>> pump(WidgetTester tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          projectRepositoryProvider.overrideWithValue(projectRepo),
          gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: _Harness(key: key)),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  testWidgets('toasts an error when the project cannot be loaded',
      (tester) async {
    when(() => projectRepo.getById(_projectId)).thenAnswer(
      (_) async =>
          const Err<Project, TWMTDatabaseException>(TWMTDatabaseException('x')),
    );
    final key = await pump(tester);

    await key.currentState!.buildActions().handleOpenModFolder();
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to open mod folder'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // drain toast timer
    await tester.pumpAndSettle();
  });

  testWidgets('toasts an error when the game installation is missing',
      (tester) async {
    when(() => projectRepo.getById(_projectId)).thenAnswer(
      (_) async => const Ok<Project, TWMTDatabaseException>(_project),
    );
    when(() => gameRepo.getById(_gameInstallationId)).thenAnswer(
      (_) async => const Err<GameInstallation, TWMTDatabaseException>(
        TWMTDatabaseException('x'),
      ),
    );
    final key = await pump(tester);

    await key.currentState!.buildActions().handleOpenModFolder();
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to open mod folder'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('warns when the installation path is not configured',
      (tester) async {
    when(() => projectRepo.getById(_projectId)).thenAnswer(
      (_) async => const Ok<Project, TWMTDatabaseException>(_project),
    );
    when(() => gameRepo.getById(_gameInstallationId)).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game(path: null)),
    );
    final key = await pump(tester);

    await key.currentState!.buildActions().handleOpenModFolder();
    await tester.pumpAndSettle();

    expect(find.text('Game installation path is not configured.'),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
