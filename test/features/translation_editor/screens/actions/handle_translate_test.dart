import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/editor_selection_notifier.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_base.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_translation.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/editor_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

const _projectId = 'project-1';
const _languageId = 'language-fr';
const _projectLanguageId = 'plang-1';

const _projectLanguage = ProjectLanguage(
  id: _projectLanguageId,
  projectId: _projectId,
  languageId: _languageId,
  createdAt: 0,
  updatedAt: 0,
);

/// Fakes the selection notifier with a fixed set of selected unit ids.
class _FakeSelection extends EditorSelection {
  _FakeSelection(this._ids);
  final Set<String> _ids;
  @override
  EditorSelectionState build() => EditorSelectionState(selectedUnitIds: _ids);
}

/// Fakes the LLM provider settings async notifier with a fixed map.
class _FakeLlmSettings extends LlmProviderSettings {
  _FakeLlmSettings(this._data);
  final Map<String, String> _data;
  @override
  Future<Map<String, String>> build() async => _data;
}

/// Composes only the translation mixin under test. The two abstract members
/// it declares (`showProviderSetupDialog`, `createAndStartBatch`) are recorded
/// here instead of pulling in the navigation-heavy EditorActionsBatch mixin.
class _TranslationActions
    with EditorActionsBase, EditorActionsTranslation {
  _TranslationActions({required this.ref, required this.context});

  @override
  final WidgetRef ref;

  @override
  final BuildContext context;

  @override
  String get projectId => _projectId;

  @override
  String get languageId => _languageId;

  int providerSetupShown = 0;
  final List<({List<String> unitIds, bool forceSkipTM})> batches = [];

  @override
  void showProviderSetupDialog() => providerSetupShown++;

  @override
  Future<void> createAndStartBatch(List<String> unitIds,
      {bool forceSkipTM = false}) async {
    batches.add((unitIds: unitIds, forceSkipTM: forceSkipTM));
  }
}

class _ActionsHarness extends ConsumerStatefulWidget {
  const _ActionsHarness({super.key});

  @override
  ConsumerState<_ActionsHarness> createState() => _ActionsHarnessState();
}

class _ActionsHarnessState extends ConsumerState<_ActionsHarness> {
  _TranslationActions buildActions() =>
      _TranslationActions(ref: ref, context: context);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _MockVersionRepo versionRepo;
  late _MockProjectLanguageRepo projectLanguageRepo;

  setUp(() {
    versionRepo = _MockVersionRepo();
    projectLanguageRepo = _MockProjectLanguageRepo();

    when(() => projectLanguageRepo.getByProject(_projectId)).thenAnswer(
      (_) async => const Ok<List<ProjectLanguage>, TWMTDatabaseException>(
        [_projectLanguage],
      ),
    );
  });

  void stubUntranslated(List<String> ids) {
    when(() => versionRepo.getUntranslatedIds(
          projectLanguageId: _projectLanguageId,
        )).thenAnswer(
      (_) async => Ok<List<String>, TWMTDatabaseException>(ids),
    );
  }

  void stubFilter(List<String> ids) {
    when(() => versionRepo.filterUntranslatedIds(
          ids: any(named: 'ids'),
          projectLanguageId: _projectLanguageId,
        )).thenAnswer(
      (_) async => Ok<List<String>, TWMTDatabaseException>(ids),
    );
  }

  // A configured provider has at least one non-empty API key.
  final configured = {'anthropic_api_key': 'sk-xxx'};
  final unconfigured = <String, String>{};

  Future<GlobalKey<_ActionsHarnessState>> pumpHarness(
    WidgetTester tester, {
    Set<String> selection = const {},
    required Map<String, String> settings,
  }) async {
    final harnessKey = GlobalKey<_ActionsHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          editorSelectionProvider.overrideWith(() => _FakeSelection(selection)),
          llmProviderSettingsProvider
              .overrideWith(() => _FakeLlmSettings(settings)),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: _ActionsHarness(key: harnessKey)),
        ),
      ),
    );
    await tester.pump();
    return harnessKey;
  }

  group('handleTranslateAll', () {
    testWidgets('shows the no-untranslated dialog and starts no batch',
        (tester) async {
      stubUntranslated([]);
      final key = await pumpHarness(tester, settings: configured);
      final actions = key.currentState!.buildActions();

      await actions.handleTranslateAll();
      await tester.pumpAndSettle();

      expect(find.text('No Untranslated Units'), findsOneWidget);
      expect(actions.batches, isEmpty);
    });

    testWidgets('opens provider setup when no provider is configured',
        (tester) async {
      stubUntranslated(['u-1']);
      final key = await pumpHarness(tester, settings: unconfigured);
      final actions = key.currentState!.buildActions();

      await actions.handleTranslateAll();
      await tester.pumpAndSettle();

      expect(actions.providerSetupShown, 1);
      expect(actions.batches, isEmpty);
    });

    testWidgets('confirming the dialog starts a batch with all untranslated ids',
        (tester) async {
      stubUntranslated(['u-1', 'u-2']);
      final key = await pumpHarness(tester, settings: configured);
      final actions = key.currentState!.buildActions();

      final future = actions.handleTranslateAll();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Translate'));
      await tester.pumpAndSettle();
      await future;

      expect(actions.batches, hasLength(1));
      expect(actions.batches.single.unitIds, ['u-1', 'u-2']);
      expect(actions.batches.single.forceSkipTM, isFalse);
    });

    testWidgets('declining the dialog starts no batch', (tester) async {
      stubUntranslated(['u-1']);
      final key = await pumpHarness(tester, settings: configured);
      final actions = key.currentState!.buildActions();

      final future = actions.handleTranslateAll();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await future;

      expect(actions.batches, isEmpty);
    });
  });

  group('handleTranslateSelected', () {
    testWidgets('shows the no-selection dialog when nothing is selected',
        (tester) async {
      final key = await pumpHarness(tester, settings: configured);
      final actions = key.currentState!.buildActions();

      await actions.handleTranslateSelected();
      await tester.pumpAndSettle();

      expect(find.text('No Selection'), findsOneWidget);
      expect(actions.batches, isEmpty);
    });

    testWidgets('shows the all-translated dialog when none remain untranslated',
        (tester) async {
      stubFilter([]);
      final key = await pumpHarness(
        tester,
        selection: {'u-1', 'u-2'},
        settings: configured,
      );
      final actions = key.currentState!.buildActions();

      await actions.handleTranslateSelected();
      await tester.pumpAndSettle();

      expect(find.text('All Selected Units Translated'), findsOneWidget);
      expect(actions.batches, isEmpty);
    });

    testWidgets('confirming starts a batch with the untranslated subset',
        (tester) async {
      stubFilter(['u-2']);
      final key = await pumpHarness(
        tester,
        selection: {'u-1', 'u-2'},
        settings: configured,
      );
      final actions = key.currentState!.buildActions();

      final future = actions.handleTranslateSelected();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Translate'));
      await tester.pumpAndSettle();
      await future;

      expect(actions.batches.single.unitIds, ['u-2']);
      expect(actions.batches.single.forceSkipTM, isFalse);
    });
  });

  group('handleForceRetranslateSelected', () {
    testWidgets('shows the no-selection dialog when nothing is selected',
        (tester) async {
      final key = await pumpHarness(tester, settings: configured);
      final actions = key.currentState!.buildActions();

      await actions.handleForceRetranslateSelected();
      await tester.pumpAndSettle();

      expect(find.text('No Selection'), findsOneWidget);
      expect(actions.batches, isEmpty);
    });

    testWidgets('confirming starts a batch that forces a TM skip',
        (tester) async {
      final key = await pumpHarness(
        tester,
        selection: {'u-1', 'u-2'},
        settings: configured,
      );
      final actions = key.currentState!.buildActions();

      final future = actions.handleForceRetranslateSelected();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Translate'));
      await tester.pumpAndSettle();
      await future;

      expect(actions.batches.single.forceSkipTM, isTrue);
      expect(actions.batches.single.unitIds, containsAll(['u-1', 'u-2']));
    });
  });
}
