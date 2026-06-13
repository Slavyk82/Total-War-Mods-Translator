import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/add_language_wizard_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  // Wrapper holding the captured result so tests can assert it after the
  // dialog pops (the `_openDialog` helper returns the value *before* the
  // dialog is dismissed, so we use a mutable holder instead).
  late AddLanguageWizardResult? result;

  Future<void> pumpAndOpen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    result = null;

    await tester.pumpWidget(
      createThemedTestableWidget(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                result = await showDialog<AddLanguageWizardResult>(
                  context: context,
                  useRootNavigator: false,
                  builder: (_) => const AddLanguageWizardDialog(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Finder addButton() => find.widgetWithText(
        SmallTextButton,
        t.gameTranslation.addLanguageDialog.actions.add,
      );

  Finder cancelButton() => find.widgetWithText(
        SmallTextButton,
        t.gameTranslation.wizard.actions.cancel,
      );

  testWidgets('renders the dialog with title, fields, helpers and actions',
      (tester) async {
    await pumpAndOpen(tester);

    expect(find.byType(AddLanguageWizardDialog), findsOneWidget);
    expect(find.text(t.gameTranslation.addLanguageDialog.title), findsOneWidget);
    expect(
      find.text(t.gameTranslation.addLanguageDialog.description),
      findsOneWidget,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.codeLabel),
      findsOneWidget,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.codeHelper),
      findsOneWidget,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.nameLabel),
      findsOneWidget,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.nameHelper),
      findsOneWidget,
    );
    // Default-language option + info section
    expect(
      find.text(t.gameTranslation.addLanguageDialog.defaultLanguage.label),
      findsOneWidget,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.info),
      findsOneWidget,
    );
    // Actions
    expect(addButton(), findsOneWidget);
    expect(cancelButton(), findsOneWidget);
    // Checkbox starts unchecked.
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
  });

  testWidgets('cancel closes the dialog and returns null', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(cancelButton());
    await tester.pumpAndSettle();

    expect(find.byType(AddLanguageWizardDialog), findsNothing);
    expect(result, isNull);
  });

  testWidgets('shows required errors when saving with empty fields',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(addButton());
    await tester.pumpAndSettle();

    // Dialog stays open; both required errors shown.
    expect(find.byType(AddLanguageWizardDialog), findsOneWidget);
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.codeErrors.required,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.nameErrors.required,
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows tooShort error for a 1-char code', (tester) async {
    await pumpAndOpen(tester);

    final codeField = find.byType(TextField).first;
    await tester.enterText(codeField, 'p');
    // Provide a valid name so only the code error surfaces.
    await tester.enterText(find.byType(TextField).last, 'Polish');
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.codeErrors.tooShort,
      ),
      findsOneWidget,
    );
    expect(find.byType(AddLanguageWizardDialog), findsOneWidget);
  });

  testWidgets('shows lettersOnly error for a non-alpha code', (tester) async {
    await pumpAndOpen(tester);

    await tester.enterText(find.byType(TextField).first, 'p1');
    await tester.enterText(find.byType(TextField).last, 'Polish');
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.codeErrors.lettersOnly,
      ),
      findsOneWidget,
    );
  });

  testWidgets('clears code error when typing again after a failed save',
      (tester) async {
    await pumpAndOpen(tester);

    // Trigger errors first.
    await tester.tap(addButton());
    await tester.pumpAndSettle();
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.codeErrors.required,
      ),
      findsOneWidget,
    );

    // Typing into the code field clears its error (helper text reappears).
    await tester.enterText(find.byType(TextField).first, 'pl');
    await tester.pumpAndSettle();
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.codeErrors.required,
      ),
      findsNothing,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.codeHelper),
      findsOneWidget,
    );
  });

  testWidgets('clears name error when typing again after a failed save',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(addButton());
    await tester.pumpAndSettle();
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.nameErrors.required,
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'Polish');
    await tester.pumpAndSettle();
    expect(
      find.text(
        t.gameTranslation.addLanguageDialog.fields.nameErrors.required,
      ),
      findsNothing,
    );
    expect(
      find.text(t.gameTranslation.addLanguageDialog.fields.nameHelper),
      findsOneWidget,
    );
  });

  testWidgets('toggling the default-language checkbox updates its value',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);
  });

  testWidgets('valid save pops a result with trimmed code/name (not default)',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.enterText(find.byType(TextField).first, '  pl  ');
    await tester.enterText(find.byType(TextField).last, '  Polish  ');
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    // Dialog closed and result captured.
    expect(find.byType(AddLanguageWizardDialog), findsNothing);
    expect(result, isNotNull);
    expect(result!.code, 'pl');
    expect(result!.name, 'Polish');
    expect(result!.setAsDefault, isFalse);
  });

  testWidgets('valid save with default checkbox set returns setAsDefault=true',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.enterText(find.byType(TextField).first, 'ko');
    await tester.enterText(find.byType(TextField).last, 'Korean');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.code, 'ko');
    expect(result!.name, 'Korean');
    expect(result!.setAsDefault, isTrue);
  });
}
