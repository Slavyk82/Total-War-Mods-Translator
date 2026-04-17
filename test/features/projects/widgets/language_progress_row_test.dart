import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/widgets/language_progress_row.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

void main() {
  const fr = Language(id: 'l-fr', code: 'fr', name: 'French', nativeName: 'Français');

  ProjectLanguageDetails details({
    int total = 100,
    int translated = 60,
  }) => ProjectLanguageDetails(
        projectLanguage: const ProjectLanguage(
          id: 'pl-1',
          projectId: 'p-1',
          languageId: 'l-fr',
          createdAt: 0,
          updatedAt: 0,
        ),
        language: fr,
        totalUnits: total,
        translatedUnits: translated,
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(width: 800, child: child),
        ),
      );

  testWidgets('renders language name, percent, units and status pill',
      (t) async {
    await t.pumpWidget(wrap(LanguageProgressRow(
      langDetails: details(total: 100, translated: 60),
      onOpenEditor: () {},
    )));
    expect(find.text('French'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('60 / 100'), findsOneWidget);
    expect(find.byType(StatusPill), findsOneWidget);
  });

  testWidgets('onOpenEditor tap fires', (t) async {
    var opened = false;
    await t.pumpWidget(wrap(LanguageProgressRow(
      langDetails: details(),
      onOpenEditor: () => opened = true,
    )));
    await t.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  testWidgets('onDelete fires when delete icon tapped', (t) async {
    var deleted = false;
    await t.pumpWidget(wrap(LanguageProgressRow(
      langDetails: details(),
      onOpenEditor: () {},
      onDelete: () => deleted = true,
    )));
    await t.tap(find.byTooltip('Delete language'));
    expect(deleted, isTrue);
  });

  testWidgets('zero-unit language shows 0% and pending pill', (t) async {
    await t.pumpWidget(wrap(LanguageProgressRow(
      langDetails: details(total: 0, translated: 0),
      onOpenEditor: () {},
    )));
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('PENDING'), findsOneWidget);
  });

  testWidgets('100% language shows completed pill', (t) async {
    await t.pumpWidget(wrap(LanguageProgressRow(
      langDetails: details(total: 50, translated: 50),
      onOpenEditor: () {},
    )));
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('COMPLETED'), findsOneWidget);
  });
}
