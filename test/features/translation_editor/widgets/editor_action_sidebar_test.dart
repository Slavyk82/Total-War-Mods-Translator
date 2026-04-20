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
              totalUnits: (pendingCount ?? 0),
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

  testWidgets('renders the 4 intent-based section headers', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // AI Context (model + prompt config), Translate, Review, Pack.
    expect(find.text('AI Context'), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Pack'), findsOneWidget);
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
    // routes to onTranslateAll. The Ctrl+T hint is displayed inline.
    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('Ctrl+T'), findsOneWidget);
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

    // Label flips to the selection form; the Ctrl+T hint stays put because
    // the screen-scope shortcut is itself selection-aware.
    expect(find.text('Translate all'), findsNothing);
    expect(find.text('Translate selection'), findsOneWidget);
    expect(find.text('Ctrl+T'), findsOneWidget);
    // The now-removed dedicated "Selection" secondary button must not return.
    expect(find.text('Selection'), findsNothing);

    // Tapping routes to onTranslateSelected, not onTranslateAll.
    await tester.tap(find.text('Translate selection'));
    await tester.pumpAndSettle();
    expect(selectedTapped, isTrue);
    expect(allTapped, isFalse);
  });

  testWidgets('tapping Validate invokes onValidate', (tester) async {
    // The §Review section now exposes a single unified button: Validate
    // rescans everything and then filters the grid to `needsReview`. The
    // former secondary "Rescan all" button was folded into this handler,
    // so it must no longer render.
    var tapped = false;
    await tester.pumpWidget(build(onValidate: () => tapped = true));
    await tester.pumpAndSettle();

    expect(find.text('Rescan all'), findsNothing);
    expect(find.text('Validate selected'), findsNothing);

    await tester.tap(find.text('Validate'));
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

    await tester.tap(find.text('Import pack'));
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

}
