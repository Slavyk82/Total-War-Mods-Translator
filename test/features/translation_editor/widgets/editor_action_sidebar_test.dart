import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_action_sidebar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Widget build({
    VoidCallback? onTranslateAll,
    VoidCallback? onTranslateSelected,
    VoidCallback? onValidate,
    VoidCallback? onExport,
    VoidCallback? onImportPack,
    int? pendingCount,
    bool statsLoading = false,
  }) {
    final statsOverride = statsLoading
        ? editorStatsProvider('p', 'fr')
            .overrideWith((_) => Completer<EditorStats>().future)
        : editorStatsProvider('p', 'fr').overrideWith(
            (_) async => EditorStats(
              totalUnits: pendingCount ?? 0,
              pendingCount: pendingCount ?? 0,
              translatedCount: 0,
              needsReviewCount: 0,
              completionPercentage: 0.0,
            ),
          );
    return createThemedTestableWidget(
      Scaffold(
        body: EditorActionSidebar(
          projectId: 'p',
          languageId: 'fr',
          onTranslateAll: onTranslateAll ?? () {},
          onTranslateSelected: onTranslateSelected ?? () {},
          onValidate: onValidate ?? () {},
          onExport: onExport ?? () {},
          onImportPack: onImportPack ?? () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [statsOverride],
    );
  }

  testWidgets('does not render a search field in the header row',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // The §SEARCH section was removed; search lives in the top FilterToolbar.
    // The sidebar now hosts number fields for batch settings — we assert the
    // search label is absent rather than blanket-matching `TextField`.
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('renders §AI CONTEXT header with model · skip-tm · rules',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('AI Context'), findsOneWidget);
    // Three context widgets present (model selector may render empty if no
    // models are available in test fakes, so we assert by widget type).
    expect(
      find.byWidgetPredicate((w) =>
          w.runtimeType.toString() == 'EditorToolbarSkipTm'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) =>
          w.runtimeType.toString() == 'EditorToolbarModRule'),
      findsOneWidget,
    );
  });

  testWidgets('renders the 3 intent-based section headers', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // AI Context (model + prompt config) + Other (Import pack) + Workflow
    // (Translate · Review · Generate pack as a single numbered pipeline,
    // mirroring the main navigation sidebar's Workflow group).
    expect(find.text('AI Context'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Workflow'), findsOneWidget);
    // The former per-step headers (Translate / Review / Pack) have been
    // folded into the single Workflow group. 'Review' now appears as the
    // step-2 button label, so it is expected to be present once; the former
    // 'Pack' header is gone entirely.
    expect(find.text('Pack'), findsNothing);
    // The old generic 'Actions' header and 'Settings' footer section were
    // replaced by intent-scoped groups; Translation settings now lives in
    // §AI Context alongside the other translation configuration controls.
    expect(find.text('Actions'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    // Older bare 'Context' label must not leak through either.
    expect(find.text('Context'), findsNothing);
  });

  testWidgets(
      'tapping the Translate button invokes onTranslateAll when no selection',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslateAll: () => tapped = true));
    await tester.pumpAndSettle();

    // With no selection, the unified button reads "Translate all" and
    // routes to onTranslateAll.
    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('Ctrl+T'), findsNothing);
    await tester.tap(find.text('Translate all'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets(
      'Translate button label, hint and handler reflect the grid selection',
      (tester) async {
    var allTapped = false;
    var selectedTapped = false;
    await tester.pumpWidget(build(
      onTranslateAll: () => allTapped = true,
      onTranslateSelected: () => selectedTapped = true,
    ));
    await tester.pumpAndSettle();

    // Seed a 3-row selection through the real provider.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorActionSidebar)),
      listen: false,
    );
    container
        .read(editorSelectionProvider.notifier)
        .selectAll(['a', 'b', 'c']);
    await tester.pumpAndSettle();

    // Label flips to the selection form.
    expect(find.text('Translate all'), findsNothing);
    expect(find.text('Translate selection'), findsOneWidget);
    expect(find.text('Ctrl+T'), findsNothing);
    // The now-removed dedicated "Selection" secondary button must not return.
    expect(find.text('Selection'), findsNothing);

    // Tapping routes to onTranslateSelected, not onTranslateAll.
    await tester.tap(find.text('Translate selection'));
    await tester.pumpAndSettle();
    expect(selectedTapped, isTrue);
    expect(allTapped, isFalse);
  });

  testWidgets('tapping Review invokes onValidate', (tester) async {
    // The Workflow step 2 exposes a single unified Review button: it
    // rescans everything and then filters the grid to `needsReview`. The
    // former secondary "Rescan all" button was folded into this handler,
    // so it must no longer render.
    var tapped = false;
    await tester.pumpWidget(build(onValidate: () => tapped = true));
    await tester.pumpAndSettle();

    expect(find.text('Rescan all'), findsNothing);
    expect(find.text('Validate selected'), findsNothing);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Generate pack invokes onExport', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onExport: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate pack'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Import pack invokes onImportPack', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onImportPack: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import external pack'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('renders the inline batch settings panel in §Context',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // The Translation Settings popup was removed; all 3 batch controls
    // (Auto toggle + Units / batch + Parallel batches) now live inline in
    // §Context.
    expect(
      find.byWidgetPredicate((w) =>
          w.runtimeType.toString() == 'EditorToolbarBatchSettings'),
      findsOneWidget,
    );
    expect(find.text('Auto batch size'), findsOneWidget);
    expect(find.text('Units / batch'), findsOneWidget);
    expect(find.text('Parallel batches'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    // The old action button that opened the popup must be gone.
    expect(find.text('Translation settings'), findsNothing);
  });

  testWidgets('shows "<n> units" subtitle under Translate all when count > 1',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 42));
    await tester.pumpAndSettle();

    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('42 units'), findsOneWidget);
  });

  testWidgets('subtitle uses singular form when exactly 1 unit is pending',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 1));
    await tester.pumpAndSettle();

    expect(find.text('1 unit'), findsOneWidget);
    expect(find.text('1 units'), findsNothing);
  });

  testWidgets('no subtitle is rendered when pendingCount is 0',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 0));
    await tester.pumpAndSettle();

    // Button still there, but no count hint under it. Asserting exact
    // strings avoids false positives from unrelated sidebar copy that
    // happens to include the substring "unit" (e.g. the batch settings
    // label "Units / batch").
    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('0 units'), findsNothing);
    expect(find.text('0 unit'), findsNothing);
  });

  testWidgets('subtitle shows the selection count when rows are selected',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 42));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorActionSidebar)),
      listen: false,
    );
    container
        .read(editorSelectionProvider.notifier)
        .selectAll(['a', 'b', 'c']);
    await tester.pumpAndSettle();

    // Label flips to "Translate selection" and the count hint switches from
    // pending-total to the selection size — 3 selected, not 42 pending.
    expect(find.text('Translate selection'), findsOneWidget);
    expect(find.text('3 units'), findsOneWidget);
    expect(find.text('42 units'), findsNothing);
  });

  testWidgets('selection-count subtitle uses singular form for exactly 1 row',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 42));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorActionSidebar)),
      listen: false,
    );
    container.read(editorSelectionProvider.notifier).selectAll(['a']);
    await tester.pumpAndSettle();

    expect(find.text('Translate selection'), findsOneWidget);
    expect(find.text('1 unit'), findsOneWidget);
    expect(find.text('1 units'), findsNothing);
  });

  testWidgets('no subtitle is rendered while editorStats is loading',
      (tester) async {
    await tester.pumpWidget(build(statsLoading: true));
    await tester.pump(); // 1 frame: provider still pending, no settle.

    expect(find.text('Translate all'), findsOneWidget);
    // We don't flash a placeholder while stats resolve. With the default
    // (pendingCount: 0) a leaked subtitle would read "0 unit(s)".
    expect(find.text('0 units'), findsNothing);
    expect(find.text('0 unit'), findsNothing);
  });
}
