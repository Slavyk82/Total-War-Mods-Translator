import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/widgets/editor_action_sidebar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Widget build({
    FocusNode? focusNode,
    VoidCallback? onTranslationSettings,
    VoidCallback? onTranslateAll,
    VoidCallback? onTranslateSelected,
    VoidCallback? onValidate,
    VoidCallback? onRescanValidation,
    VoidCallback? onExport,
    VoidCallback? onImportPack,
  }) {
    return createThemedTestableWidget(
      Scaffold(
        body: EditorActionSidebar(
          projectId: 'p',
          languageId: 'fr',
          searchFocusNode: focusNode ?? FocusNode(),
          onTranslationSettings: onTranslationSettings ?? () {},
          onTranslateAll: onTranslateAll ?? () {},
          onTranslateSelected: onTranslateSelected ?? () {},
          onValidate: onValidate ?? () {},
          onRescanValidation: onRescanValidation ?? () {},
          onExport: onExport ?? () {},
          onImportPack: onImportPack ?? () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    );
  }

  testWidgets('renders §SEARCH header and search field', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing in search field debounces to editorFilterProvider',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Hold a live subscription: `editorFilterProvider` is auto-dispose,
    // so without it each `container.read` rebuilds fresh initial state
    // and forgets the widget's mutation.
    final sub = container.listen(editorFilterProvider, (_, _) {});
    addTearDown(sub.close);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: EditorActionSidebar(
            projectId: 'p',
            languageId: 'fr',
            searchFocusNode: FocusNode(),
            onTranslationSettings: () {},
            onTranslateAll: () {},
            onTranslateSelected: () {},
            onValidate: () {},
            onRescanValidation: () {},
            onExport: () {},
            onImportPack: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    // Wait past the 200ms debounce, then let the async body complete.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(
      container.read(editorFilterProvider).searchQuery,
      equals('hello'),
    );
  });

  testWidgets('renders §CONTEXT header with model · skip-tm · rules', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Context'), findsOneWidget);
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

  testWidgets('tapping Translate all invokes onTranslateAll', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslateAll: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Translate all'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Selection is a no-op when no selection', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslateSelected: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();

    // With no selection, the Selection button's onTap is null, so tapping
    // it must not invoke the callback.
    expect(tapped, isFalse);
  });

  testWidgets('tapping Validate selected invokes onValidate', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onValidate: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Validate selected'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Rescan all invokes onRescanValidation', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onRescanValidation: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rescan all'));
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

  testWidgets('tapping Translation settings invokes onTranslationSettings',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslationSettings: () => tapped = true));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('Translation settings'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
