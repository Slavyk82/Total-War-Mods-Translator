import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/provider_setup_dialog.dart';
import 'package:twmt/features/translation_editor/widgets/validation_edit_dialog.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const _issue = ValidationIssue(
  unitKey: 'greeting',
  unitId: 'unit-a',
  versionId: 'version-a',
  severity: ValidationSeverity.warning,
  issueType: 'markup',
  description: 'tag mismatch',
  sourceText: 'Hello world',
  translatedText: 'Bonjour',
);

void main() {
  // Both dialogs are wide (480/800px) with tall content; give the view room
  // so showDialog's overlay doesn't overflow the default 800x600 surface.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1400, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  /// Opens [dialog] from a host button. The returned list stays empty while
  /// the dialog is open and receives the pop value once it closes — interact,
  /// settle, then read `holder.single`.
  Future<List<T?>> openDialog<T>(WidgetTester tester, Widget dialog) async {
    final holder = <T?>[];
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              holder.add(await showDialog<T>(
                context: context,
                builder: (_) => dialog,
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return holder;
  }

  group('ProviderSetupDialog', () {
    testWidgets('lists the configurable providers', (tester) async {
      var wentToSettings = false;
      await openDialog<void>(
        tester,
        ProviderSetupDialog(onGoToSettings: () => wentToSettings = true),
      );

      expect(find.text('No Translation Provider Configured'), findsOneWidget);
      expect(find.text('Anthropic Claude'), findsOneWidget);
      expect(find.text('OpenAI GPT'), findsOneWidget);
      expect(find.text('DeepL'), findsOneWidget);
      expect(wentToSettings, isFalse);
    });

    testWidgets('Go to Settings pops and fires the callback', (tester) async {
      var wentToSettings = false;
      await openDialog<void>(
        tester,
        ProviderSetupDialog(onGoToSettings: () => wentToSettings = true),
      );

      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();

      expect(wentToSettings, isTrue);
      expect(find.text('No Translation Provider Configured'), findsNothing);
    });

    testWidgets('Cancel pops without firing the callback', (tester) async {
      var wentToSettings = false;
      await openDialog<void>(
        tester,
        ProviderSetupDialog(onGoToSettings: () => wentToSettings = true),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(wentToSettings, isFalse);
      expect(find.text('No Translation Provider Configured'), findsNothing);
    });
  });

  group('ValidationEditDialog', () {
    testWidgets('shows source text, the issue banner and prefilled translation',
        (tester) async {
      await openDialog<String>(
        tester,
        const ValidationEditDialog(issue: _issue),
      );

      expect(find.text('Edit Translation'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('markup: tag mismatch'), findsOneWidget);
      expect(find.text('Bonjour'), findsOneWidget); // prefilled controller
    });

    testWidgets('Save returns the trimmed edited text', (tester) async {
      final holder = await openDialog<String>(
        tester,
        const ValidationEditDialog(issue: _issue),
      );

      await tester.enterText(find.byType(TextField), '  Bonjour corrigé  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(holder.single, 'Bonjour corrigé');
      expect(find.text('Edit Translation'), findsNothing);
    });

    testWidgets('Save with empty text keeps the dialog open', (tester) async {
      final holder = await openDialog<String>(
        tester,
        const ValidationEditDialog(issue: _issue),
      );

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Translation'), findsOneWidget); // still open
      expect(holder, isEmpty); // never popped
    });

    testWidgets('Cancel closes the dialog returning null', (tester) async {
      final holder = await openDialog<String>(
        tester,
        const ValidationEditDialog(issue: _issue),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Translation'), findsNothing);
      expect(holder.single, isNull);
    });
  });
}
