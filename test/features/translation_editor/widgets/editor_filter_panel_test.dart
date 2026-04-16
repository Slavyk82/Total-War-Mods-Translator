import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_filter_panel.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders both filter groups', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: EditorFilterPanel(projectId: 'p', languageId: 'fr'),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        editorStatsProvider('p', 'fr').overrideWith((_) async => const EditorStats(
              totalUnits: 100,
              pendingCount: 50,
              translatedCount: 40,
              needsReviewCount: 10,
              completionPercentage: 40.0,
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('État'), findsOneWidget);
    expect(find.text('Source mémoire'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.text('Exact match'), findsOneWidget);
    expect(find.text('Fuzzy match'), findsOneWidget);
    expect(find.text('LLM'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('does not render Statistics section', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: EditorFilterPanel(projectId: 'p', languageId: 'fr'),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        editorStatsProvider('p', 'fr').overrideWith((_) async => EditorStats.empty()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Statistics'), findsNothing);
    expect(find.text('Total'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('clear filters appears only when filters active', (tester) async {
    final container = ProviderContainer(overrides: [
      editorStatsProvider('p', 'fr').overrideWith((_) async => EditorStats.empty()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: EditorFilterPanel(projectId: 'p', languageId: 'fr'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Clear filters'), findsNothing);

    container.read(editorFilterProvider.notifier).setStatusFilters(
      {TranslationVersionStatus.translated},
    );
    await tester.pumpAndSettle();

    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('Clear filters'), findsNothing);
  });
}
