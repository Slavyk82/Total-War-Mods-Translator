import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/features/translation_editor/widgets/grid_actions_handler.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../../../helpers/test_helpers.dart';
import '../../../helpers/test_bootstrap.dart';

TranslationRow _row(String id) => TranslationRow(
      unit: TranslationUnit(
        id: id,
        projectId: 'p1',
        key: 'k_$id',
        sourceText: 's_$id',
        createdAt: 0,
        updatedAt: 0,
      ),
      version: TranslationVersion(
        id: 'v_$id',
        unitId: id,
        projectLanguageId: 'pl1',
        createdAt: 0,
        updatedAt: 0,
      ),
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  // Mocks the system clipboard so handlePaste() reads deterministic TSV content.
  void mockClipboard(String text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': text};
      }
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'handlePaste shows the success toast only after all cell edits complete',
      (tester) async {
    // Two rows; paste references both keys.
    final dataSource = EditorDataSource(
      onCellEdit: (_, _) async {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
    dataSource.updateDataSource([_row('u1'), _row('u2')]);

    mockClipboard('k_u1\ts_u1\tT1\nk_u2\ts_u2\tT2');

    // Each edit is gated by a Completer so we can observe the in-flight window.
    final edited = <String>[];
    final gates = <Completer<void>>[];

    late BuildContext capturedContext;
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      createThemedTestableWidget(
        Consumer(
          builder: (context, ref, _) {
            capturedContext = context;
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
        theme: AppTheme.atelierDarkTheme,
      ),
    );

    final handler = GridActionsHandler(
      context: capturedContext,
      ref: capturedRef,
      dataSource: dataSource,
      selectedRowIds: const <String>{},
      projectId: 'p1',
      languageId: 'fr',
      onCellEdit: (unitId, newText) {
        edited.add(unitId);
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      },
    );

    // Fire the paste but do not await it yet.
    final pasteFuture = handler.handlePaste();

    // Let the clipboard read + first onCellEdit call run.
    await tester.pump();

    // First edit started, second has not (sequential awaiting), and crucially
    // the success toast must NOT be on screen while edits are still pending.
    expect(edited, ['u1']);
    expect(find.byType(FluentToastWidget), findsNothing,
        reason: 'toast must not appear before edits complete');

    // Complete the first edit; the loop should then start the second.
    gates[0].complete();
    await tester.pump();
    expect(edited, ['u1', 'u2']);
    expect(find.byType(FluentToastWidget), findsNothing,
        reason: 'toast must not appear while the second edit is in flight');

    // Complete the second edit; now the toast may show.
    gates[1].complete();
    await pasteFuture;
    await tester.pump();

    expect(find.byType(FluentToastWidget), findsOneWidget,
        reason: 'success toast shows after every edit has completed');

    // Let the toast's auto-dismiss timer/animation run so no timers leak past
    // teardown.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
