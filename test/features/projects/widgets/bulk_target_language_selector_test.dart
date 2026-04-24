import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_target_language_selector.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/theme/app_theme.dart';

const _frLang = Language(
  id: '1',
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
);
const _deLang = Language(
  id: '2',
  code: 'de',
  name: 'German',
  nativeName: 'Deutsch',
);
const _fakeLanguages = [_frLang, _deLang];

ProjectLanguageWithInfo _plInfo(Language l) => ProjectLanguageWithInfo(
      projectLanguage: ProjectLanguage(
        id: 'pl-${l.code}',
        projectId: 'p1',
        languageId: l.id,
        createdAt: 0,
        updatedAt: 0,
      ),
      language: l,
      totalUnits: 10,
    );

ProjectWithDetails _projectWith(List<Language> languages) => ProjectWithDetails(
      project: const Project(
        id: 'p1',
        name: 'Project 1',
        gameInstallationId: 'g1',
        createdAt: 0,
        updatedAt: 0,
      ),
      languages: languages.map(_plInfo).toList(),
    );

/// Visible-scope override for the selector: `visible` drives the dropdown
/// filter, `matching` is not read by the selector.
// ignore: prefer_final_in_for_each
_scopeOverride(List<Language> visibleLanguages) {
  final visible = visibleLanguages.isEmpty
      ? <ProjectWithDetails>[]
      : [_projectWith(visibleLanguages)];
  return visibleProjectsForBulkProvider.overrideWith(
    (ref) => AsyncValue.data((visible: visible, matching: const [])),
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders a dropdown with language entries', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
        _scopeOverride(_fakeLanguages),
      ],
      child: _wrap(const BulkTargetLanguageSelector()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text('Target language'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows language display names in dropdown entries',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
        _scopeOverride(_fakeLanguages),
      ],
      child: _wrap(const BulkTargetLanguageSelector()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('French (Français)'), findsOneWidget);
    expect(find.text('German (Deutsch)'), findsOneWidget);
  });

  testWidgets('filters languages to those present in visible projects',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
        _scopeOverride(const [_frLang]),
      ],
      child: _wrap(const BulkTargetLanguageSelector()),
    ));
    await tester.pumpAndSettle();
    // With a single matching language the widget auto-selects it, so the
    // text can appear both in the field and in the entry list — assert at
    // least one match, and none for the filtered-out language.
    expect(find.text('French (Français)'), findsAtLeastNWidgets(1));
    expect(find.text('German (Deutsch)'), findsNothing);
  });

  testWidgets('shows empty-state message when no visible projects have languages',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
        _scopeOverride(const []),
      ],
      child: _wrap(const BulkTargetLanguageSelector()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownMenu<String>), findsNothing);
    expect(
      find.textContaining('No target language available'),
      findsOneWidget,
    );
  });

  testWidgets('selecting a language updates bulkTargetLanguageProvider',
      (tester) async {
    // Build container with overrides
    // Pump widget referencing container
    // Simulate selecting a specific language
    // Expect container.read(bulkTargetLanguageProvider).asData?.value == 'fr'
  }, skip: true);
}
