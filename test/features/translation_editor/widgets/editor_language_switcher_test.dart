import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_language_switcher.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

ProjectLanguageDetails _pld(String id, String code, String name,
    {int translated = 0, int total = 0}) {
  return ProjectLanguageDetails(
    projectLanguage: ProjectLanguage(
      id: 'pl_$id',
      projectId: 'p',
      languageId: id,
      progressPercent: total == 0 ? 0 : translated / total * 100,
      createdAt: 1,
      updatedAt: 1,
    ),
    language: Language(id: id, code: code, name: name, nativeName: name),
    totalUnits: total,
    translatedUnits: translated,
  );
}

void main() {
  setUp(setupMockServices);
  tearDown(tearDownMockServices);

  Widget wrap(Widget child, List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('renders current language label', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith((ref) async => [
              _pld('fr-id', 'fr', 'French', translated: 40, total: 100),
              _pld('de-id', 'de', 'German', translated: 10, total: 100),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('French'), findsOneWidget);
  });

  testWidgets('opens menu listing project languages with progress',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith((ref) async => [
              _pld('fr-id', 'fr', 'French', translated: 40, total: 100),
              _pld('de-id', 'de', 'German', translated: 10, total: 100),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-language-switcher-chip')));
    await tester.pumpAndSettle();

    expect(find.text('German'), findsWidgets);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('+ Add language'), findsOneWidget);
  });

  testWidgets('delete icon disabled when project has a single language',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith(
            (ref) async => [_pld('fr-id', 'fr', 'French', total: 10)]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-language-switcher-chip')));
    await tester.pumpAndSettle();

    final trash = find.byKey(const Key('editor-language-delete-fr-id'));
    expect(trash, findsOneWidget);
    final button = tester.widget<IconButton>(trash);
    expect(button.onPressed, isNull);
  });
}
