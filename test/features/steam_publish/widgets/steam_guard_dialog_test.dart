// Widget coverage tests for
// lib/features/steam_publish/widgets/steam_guard_dialog.dart.
//
// The dialog is a small token-themed popup prompting for a 5-character Steam
// Guard code. It renders a description, a note, and a single text field with
// input formatters (alphanumeric only, capped at 5 chars, upper-cased on
// submit) plus a Form validator (required / min length 5). Verify pops the
// trimmed, upper-cased code; Cancel pops null; onFieldSubmitted submits too.
//
// These tests open the dialog via its static `show(context)` from a button so
// the popped result is captured, then drive the field and the Verify / Cancel
// actions to exercise render, valid submit, validation (empty / too-short),
// the onFieldSubmitted path, and cancel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/steam_publish/widgets/steam_guard_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(
    WidgetTester tester,
    List<Object?> resultHolder,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      createThemedTestableWidget(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await SteamGuardDialog.show(context);
                  resultHolder.add(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
      ),
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<Object?> resultHolder,
  }) async {
    await pumpHost(tester, resultHolder);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder codeField() => find.byType(TextFormField);

  testWidgets('renders the dialog chrome and the code field', (tester) async {
    await pumpDialog(tester, resultHolder: <Object?>[]);

    expect(find.text(t.steamPublish.steamGuardDialog.title), findsOneWidget);
    expect(
      find.text(t.steamPublish.steamGuardDialog.description),
      findsOneWidget,
    );
    expect(find.text(t.steamPublish.steamGuardDialog.note), findsOneWidget);
    expect(find.text(t.steamPublish.steamGuardDialog.codeLabel), findsOneWidget);
    expect(find.text(t.steamPublish.steamGuardDialog.cancel), findsOneWidget);
    expect(find.text(t.steamPublish.steamGuardDialog.verify), findsOneWidget);
    expect(codeField(), findsOneWidget);
  });

  testWidgets('valid code submitted via Verify pops it trimmed + upper-cased',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(codeField(), 'abcde');
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.steamGuardDialog.verify));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamGuardDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, 'ABCDE');
  });

  testWidgets('empty submit surfaces the required error and stays open',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.tap(find.text(t.steamPublish.steamGuardDialog.verify));
    await tester.pumpAndSettle();

    expect(
      find.text(t.steamPublish.steamGuardDialog.errors.codeRequired),
      findsOneWidget,
    );
    // Validation failed -> dialog stays open, nothing popped.
    expect(find.text(t.steamPublish.steamGuardDialog.title), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('too-short code surfaces the min-length error and blocks submit',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(codeField(), 'ab');
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.steamGuardDialog.verify));
    await tester.pumpAndSettle();

    expect(
      find.text(t.steamPublish.steamGuardDialog.errors.codeTooShort),
      findsOneWidget,
    );
    expect(find.text(t.steamPublish.steamGuardDialog.title), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('onFieldSubmitted (keyboard done) submits a valid code',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(codeField(), 'zzzzz');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single, 'ZZZZZ');
  });

  testWidgets('input formatter strips non-alphanumerics and caps at 5 chars',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    // Spaces / dashes filtered out; only the first 5 alphanumerics kept.
    await tester.enterText(codeField(), 'a-b c1234567');
    await tester.pump();

    expect(
      tester.widget<TextFormField>(codeField()).controller?.text,
      'abc12',
    );

    await tester.tap(find.text(t.steamPublish.steamGuardDialog.verify));
    await tester.pumpAndSettle();

    expect(results.single, 'ABC12');
  });

  testWidgets('cancel pops null', (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.tap(find.text(t.steamPublish.steamGuardDialog.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamGuardDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isNull);
  });
}
