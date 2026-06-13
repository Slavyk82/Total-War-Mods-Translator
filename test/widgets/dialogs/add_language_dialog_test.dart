// Widget coverage tests for lib/widgets/dialogs/add_language_dialog.dart.
//
// The dialog reads `allLanguagesProvider` for the candidate list, filters out
// inactive / already-added languages, lets the user toggle a multi-select, and
// on confirm writes one `project_language` (plus a translation_version per unit)
// per selected language through the repositories. These tests render every UI
// state (loading, error, empty/all-added, populated), exercise selection, and
// drive the confirm success / failure / rollback paths.
import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/projects_data_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/dialogs/add_language_dialog.dart';

import '../../helpers/test_bootstrap.dart';

class _MockProjectLanguageRepo extends Mock implements ProjectLanguageRepository {}

class _MockTranslationUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockTranslationVersionRepo extends Mock
    implements TranslationVersionRepository {}

/// No-op provisioning service so `_addLanguages` never touches the real DB via
/// `ServiceLocator.get<GlossaryAutoProvisioningService>()`. The superclass
/// constructor falls back to `ServiceLocator.get<ILoggingService>()` for its
/// logger, which TestBootstrap registers before this is constructed.
class _FakeProvisioningService extends GlossaryAutoProvisioningService {
  @override
  Future<void> provisionForProject({
    required String projectId,
    required List<String> targetLanguageIds,
  }) async {}
}

/// Replaces `projectsWithDetailsProvider`'s notifier so the confirm path's
/// `refreshProject` call is a harmless no-op (the real build() hits the DB).
class _FakeProjectsNotifier extends ProjectsWithDetailsNotifier {
  @override
  Future<List<ProjectWithDetails>> build() async => const [];

  @override
  Future<void> refreshProject(String projectId) async {}
}

const _projectId = 'project-1';

Language _lang(String id, String code, String name,
        {bool isActive = true}) =>
    Language(
      id: id,
      code: code,
      name: name,
      nativeName: name,
      isActive: isActive,
    );

final _languages = [
  _lang('lang-fr', 'fr', 'French'),
  _lang('lang-de', 'de', 'German'),
  _lang('lang-es', 'es', 'Spanish'),
  _lang('lang-it', 'it', 'Italian', isActive: false), // filtered (inactive)
];

TranslationUnit _unit(String id) => TranslationUnit(
      id: id,
      projectId: _projectId,
      key: 'key-$id',
      sourceText: 'src-$id',
      createdAt: 1700000000,
      updatedAt: 1700000000,
    );

void main() {
  late _MockProjectLanguageRepo projectLangRepo;
  late _MockTranslationUnitRepo unitRepo;
  late _MockTranslationVersionRepo versionRepo;

  setUpAll(() {
    registerFallbackValue(
      const ProjectLanguage(
        id: 'fb',
        projectId: 'fb',
        languageId: 'fb',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    registerFallbackValue(<TranslationVersion>[]);
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    GetIt.I.registerSingleton<GlossaryAutoProvisioningService>(
      _FakeProvisioningService(),
    );

    projectLangRepo = _MockProjectLanguageRepo();
    unitRepo = _MockTranslationUnitRepo();
    versionRepo = _MockTranslationVersionRepo();

    // Sensible success defaults; individual tests override as needed.
    when(() => unitRepo.getByProject(any()))
        .thenAnswer((_) async => Ok([_unit('u1'), _unit('u2')]));
    when(() => projectLangRepo.insert(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments.first as ProjectLanguage),
    );
    when(() => projectLangRepo.delete(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => versionRepo.insertBatch(any()))
        .thenAnswer((_) async => const Ok(<TranslationVersion>[]));
  });

  /// Pump the dialog under a nested Navigator + Overlay so the FluentToast's
  /// `Overlay.of(...)` resolves, on a tall surface to avoid Column overflow.
  /// [languagesAsync] supplies the `allLanguagesProvider` override.
  Future<void> pumpDialog(
    WidgetTester tester, {
    Future<List<Language>> Function()? languages,
    List<String> existing = const [],
    List<Override> overrides = const [],
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectLanguageRepositoryProvider.overrideWithValue(projectLangRepo),
          translationUnitRepositoryProvider.overrideWithValue(unitRepo),
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
          allLanguagesProvider.overrideWith(
            (ref) async => (languages ?? () async => _languages)(),
          ),
          projectsWithDetailsProvider.overrideWith(_FakeProjectsNotifier.new),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (navContext) => Center(
                        child: ElevatedButton(
                          onPressed: () => showDialog<void>(
                            context: navContext,
                            useRootNavigator: false,
                            builder: (_) => AddLanguageDialog(
                              projectId: _projectId,
                              existingLanguageIds: existing,
                            ),
                          ),
                          child: const Text('open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('renders the title, subtitle and available (active) languages',
      (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.projects.addLanguage.title), findsOneWidget);
    expect(find.text(t.projects.addLanguage.subtitle), findsOneWidget);
    // Active languages appear by displayName ("Name (nativeName)").
    expect(find.text('French (French)'), findsOneWidget);
    expect(find.text('German (German)'), findsOneWidget);
    expect(find.text('Spanish (Spanish)'), findsOneWidget);
    // Inactive language is filtered out.
    expect(find.text('Italian (Italian)'), findsNothing);
    // Language codes are upper-cased.
    expect(find.text(t.projects.addLanguage.languageCode(code: 'FR')),
        findsOneWidget);
  });

  testWidgets('hides languages already added to the project', (tester) async {
    await pumpDialog(tester, existing: ['lang-fr']);

    expect(find.text('French (French)'), findsNothing);
    expect(find.text('German (German)'), findsOneWidget);
  });

  testWidgets('shows the all-added empty state when nothing is selectable',
      (tester) async {
    await pumpDialog(
      tester,
      existing: ['lang-fr', 'lang-de', 'lang-es'],
    );

    expect(find.text(t.projects.addLanguage.allAdded), findsOneWidget);
  });

  testWidgets('shows a spinner while the language list loads', (tester) async {
    final completer = Completer<List<Language>>();
    await pumpDialog(
      tester,
      settle: false,
      languages: () => completer.future,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_languages);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders the load-error state when the provider throws',
      (tester) async {
    await pumpDialog(
      tester,
      languages: () async => throw Exception('list boom'),
    );

    expect(find.text(t.projects.addLanguage.loadError), findsOneWidget);
    expect(find.textContaining('list boom'), findsOneWidget);
  });

  testWidgets('Cancel pops the dialog without writing', (tester) async {
    await pumpDialog(tester);
    expect(find.text(t.projects.addLanguage.title), findsOneWidget);

    await tester.tap(find.text(t.common.actions.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.projects.addLanguage.title), findsNothing);
    verifyNever(() => projectLangRepo.insert(any()));
  });

  testWidgets('Add is disabled until a language is selected', (tester) async {
    await pumpDialog(tester);

    // Nothing selected → tapping Add does nothing (onTap is null).
    await tester.tap(find.text(t.projects.addLanguage.addButton));
    await tester.pump();
    verifyNever(() => projectLangRepo.insert(any()));

    // Select one language, then Add becomes actionable.
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();
  });

  testWidgets('toggling a language selects then deselects it', (tester) async {
    await pumpDialog(tester);

    // Select.
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();
    expect(
        find.byIcon(FluentIcons.checkbox_checked_24_filled), findsOneWidget);

    // Deselect (tap again).
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.checkbox_checked_24_filled), findsNothing);
  });

  testWidgets('confirm inserts a project_language + versions and pops the ids',
      (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('French (French)'));
    await tester.tap(find.text('German (German)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.projects.addLanguage.addButton));
    // Let the async _addLanguages flow complete (repo awaits + pop + toast).
    await tester.pump();
    await tester.pump();
    // Drain the success toast's 4s auto-dismiss timer + its exit animation.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Dialog popped.
    expect(find.text(t.projects.addLanguage.title), findsNothing);

    verify(() => unitRepo.getByProject(_projectId)).called(1);
    // One project_language insert per selected language.
    verify(() => projectLangRepo.insert(any())).called(2);
    // One version batch per selected language.
    verify(() => versionRepo.insertBatch(any())).called(2);
    verifyNever(() => projectLangRepo.delete(any()));
  });

  testWidgets('error loading units surfaces the inline error banner',
      (tester) async {
    when(() => unitRepo.getByProject(any())).thenAnswer(
      (_) async => Err(TWMTDatabaseException('units boom')),
    );

    await pumpDialog(tester);
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.projects.addLanguage.addButton));
    await tester.pumpAndSettle();

    // Inline error banner shows the addFailed message; dialog stays open.
    expect(find.text(t.projects.addLanguage.title), findsOneWidget);
    expect(find.textContaining('units boom'), findsOneWidget);
  });

  testWidgets('a version insert failure rolls back the created language',
      (tester) async {
    when(() => versionRepo.insertBatch(any())).thenAnswer(
      (_) async => Err(TWMTDatabaseException('versions boom')),
    );

    await pumpDialog(tester);
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.projects.addLanguage.addButton));
    await tester.pumpAndSettle();

    // The project_language was inserted, then rolled back via delete.
    verify(() => projectLangRepo.insert(any())).called(1);
    verify(() => projectLangRepo.delete(any())).called(1);
    // Error banner surfaced; dialog stays open.
    expect(find.text(t.projects.addLanguage.title), findsOneWidget);
    expect(find.textContaining('versions boom'), findsOneWidget);
  });

  testWidgets('a project_language insert failure surfaces the error banner',
      (tester) async {
    when(() => projectLangRepo.insert(any())).thenAnswer(
      (_) async => Err(TWMTDatabaseException('insert boom')),
    );

    await pumpDialog(tester);
    await tester.tap(find.text('French (French)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.projects.addLanguage.addButton));
    await tester.pumpAndSettle();

    verify(() => projectLangRepo.insert(any())).called(1);
    // Nothing was successfully created, so no rollback delete is issued.
    verifyNever(() => projectLangRepo.delete(any()));
    verifyNever(() => versionRepo.insertBatch(any()));
    expect(find.text(t.projects.addLanguage.title), findsOneWidget);
    expect(find.textContaining('insert boom'), findsOneWidget);
  });
}
