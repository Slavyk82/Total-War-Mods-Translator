import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/widgets/cell_renderers/context_menu_builder.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const _row = TranslationRow(
  unit: TranslationUnit(
    id: 'u-1',
    projectId: 'p-1',
    key: 'greeting',
    sourceText: 'Hello',
    createdAt: 0,
    updatedAt: 0,
  ),
  version: TranslationVersion(
    id: 'v-1',
    unitId: 'u-1',
    projectLanguageId: 'pl-1',
    status: TranslationVersionStatus.translated,
    createdAt: 0,
    updatedAt: 0,
  ),
);

void main() {
  /// Opens the menu from a host button and returns a map recording which
  /// callbacks fired. Tap a menu item, settle, then read the map.
  Future<Map<String, bool>> pumpMenu(
    WidgetTester tester, {
    int selectionCount = 1,
    bool withForceRetranslate = false,
    bool withViewPrompt = false,
    bool withMarkAsTranslated = false,
  }) async {
    final fired = <String, bool>{};
    await tester.pumpWidget(createThemedTestableWidget(
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => ContextMenuBuilder.showContextMenu(
                context: context,
                ref: ref,
                position: const Offset(100, 100),
                row: _row,
                selectionCount: selectionCount,
                onSelectAll: () => fired['selectAll'] = true,
                onClear: () async => fired['clear'] = true,
                onViewHistory: () async => fired['history'] = true,
                onDelete: () async => fired['delete'] = true,
                onForceRetranslate: withForceRetranslate
                    ? () async => fired['forceRetranslate'] = true
                    : null,
                onViewPrompt:
                    withViewPrompt ? () async => fired['viewPrompt'] = true : null,
                onMarkAsTranslated: withMarkAsTranslated
                    ? () async => fired['markAsTranslated'] = true
                    : null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return fired;
  }

  testWidgets('renders the single-selection core items', (tester) async {
    await pumpMenu(tester);

    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Clear Translation'), findsOneWidget);
    expect(find.text('View History'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Select All invokes its callback and dismisses the menu',
      (tester) async {
    final fired = await pumpMenu(tester);

    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();

    expect(fired['selectAll'], isTrue);
    expect(find.text('Select All'), findsNothing);
  });

  testWidgets('Clear Translation invokes onClear', (tester) async {
    final fired = await pumpMenu(tester);

    await tester.tap(find.text('Clear Translation'));
    await tester.pumpAndSettle();

    expect(fired['clear'], isTrue);
  });

  testWidgets('View History invokes onViewHistory', (tester) async {
    final fired = await pumpMenu(tester);

    await tester.tap(find.text('View History'));
    await tester.pumpAndSettle();

    expect(fired['history'], isTrue);
  });

  testWidgets('Delete invokes onDelete', (tester) async {
    final fired = await pumpMenu(tester);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(fired['delete'], isTrue);
  });

  testWidgets('dismissing without a choice fires no callback', (tester) async {
    final fired = await pumpMenu(tester);

    // Tap the barrier (top-left corner, away from the menu) to dismiss.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(fired, isEmpty);
  });

  testWidgets('multi-selection uses pluralised labels and invokes onClear',
      (tester) async {
    final fired = await pumpMenu(tester, selectionCount: 3);

    expect(find.text('Clear Translation (3)'), findsOneWidget);
    expect(find.text('Delete (3)'), findsOneWidget);

    await tester.tap(find.text('Clear Translation (3)'));
    await tester.pumpAndSettle();
    expect(fired['clear'], isTrue);
  });

  testWidgets('multi-selection hides single-selection-only items',
      (tester) async {
    await pumpMenu(tester, selectionCount: 3, withViewPrompt: true);

    expect(find.text('View History'), findsNothing);
    expect(find.text('View Prompt'), findsNothing);
  });

  testWidgets('optional callbacks add their items and dispatch', (tester) async {
    final fired = await pumpMenu(
      tester,
      withForceRetranslate: true,
      withViewPrompt: true,
      withMarkAsTranslated: true,
    );

    expect(find.text('Force Retranslate'), findsOneWidget);
    expect(find.text('Mark as Translated'), findsOneWidget);
    expect(find.text('View Prompt'), findsOneWidget);

    await tester.tap(find.text('View Prompt'));
    await tester.pumpAndSettle();
    expect(fired['viewPrompt'], isTrue);
  });

  testWidgets('Force Retranslate uses a pluralised label and dispatches',
      (tester) async {
    final fired = await pumpMenu(
      tester,
      selectionCount: 4,
      withForceRetranslate: true,
    );

    expect(find.text('Force Retranslate (4)'), findsOneWidget);

    await tester.tap(find.text('Force Retranslate (4)'));
    await tester.pumpAndSettle();
    expect(fired['forceRetranslate'], isTrue);
  });

  testWidgets('Mark as Translated dispatches its callback', (tester) async {
    final fired = await pumpMenu(tester, withMarkAsTranslated: true);

    await tester.tap(find.text('Mark as Translated'));
    await tester.pumpAndSettle();
    expect(fired['markAsTranslated'], isTrue);
  });
}
