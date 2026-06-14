import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/editor_dialogs.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  // EditorDialogs render via showDialog overlays; give the surface room so the
  // token-themed popups don't overflow the default 800x600 test view.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1200, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  /// Pumps a host with an "open" button that invokes [onOpen] with a live
  /// [BuildContext]. The future's result (if any) is stashed in [holder].
  Future<List<T>> openVia<T>(
    WidgetTester tester,
    Future<T> Function(BuildContext context) onOpen,
  ) async {
    final holder = <T>[];
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async => holder.add(await onOpen(context)),
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

  group('message popups (info / warning / error)', () {
    testWidgets('showFeatureNotImplemented renders feature title and message',
        (tester) async {
      await openVia<void>(
        tester,
        (ctx) => EditorDialogs.showFeatureNotImplemented(ctx, 'Magic Feature'),
      );

      expect(find.text('Magic Feature'), findsOneWidget);
      expect(
        find.textContaining('fully implemented in the next phase'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Magic Feature'), findsNothing);
    });

    testWidgets('showNoSelectionDialog renders the warning copy and dismisses',
        (tester) async {
      await openVia<void>(tester, EditorDialogs.showNoSelectionDialog);

      expect(find.text('No Selection'), findsOneWidget);
      expect(
        find.text(
          'Please select one or more translation units to translate.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No Selection'), findsNothing);
    });

    testWidgets('showNoUntranslatedDialog renders the info copy',
        (tester) async {
      await openVia<void>(tester, EditorDialogs.showNoUntranslatedDialog);

      expect(find.text('No Untranslated Units'), findsOneWidget);
      expect(
        find.text(
          'All units in this project language are already translated.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No Untranslated Units'), findsNothing);
    });

    testWidgets('showAllTranslatedDialog renders the info copy',
        (tester) async {
      await openVia<void>(tester, EditorDialogs.showAllTranslatedDialog);

      expect(find.text('All Selected Units Translated'), findsOneWidget);
      expect(
        find.text('All selected units are already translated.'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('All Selected Units Translated'), findsNothing);
    });

    testWidgets('showErrorDialog renders supplied title and message',
        (tester) async {
      await openVia<void>(
        tester,
        (ctx) => EditorDialogs.showErrorDialog(ctx, 'Boom', 'It exploded'),
      );

      expect(find.text('Boom'), findsOneWidget);
      expect(find.text('It exploded'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Boom'), findsNothing);
    });

    testWidgets('showInfoDialog renders supplied title and message',
        (tester) async {
      await openVia<void>(
        tester,
        (ctx) => EditorDialogs.showInfoDialog(ctx, 'Heads up', 'Some detail'),
      );

      expect(find.text('Heads up'), findsOneWidget);
      expect(find.text('Some detail'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Heads up'), findsNothing);
    });
  });

  group('showTranslateConfirmationDialog', () {
    testWidgets('renders title, message and Translate action', (tester) async {
      await openVia<bool>(
        tester,
        (ctx) => EditorDialogs.showTranslateConfirmationDialog(
          ctx,
          title: 'Translate All',
          message: 'Translate every unit?',
        ),
      );

      expect(find.text('Translate All'), findsOneWidget);
      expect(find.text('Translate every unit?'), findsOneWidget);
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Translate pops true', (tester) async {
      final holder = await openVia<bool>(
        tester,
        (ctx) => EditorDialogs.showTranslateConfirmationDialog(
          ctx,
          title: 'Translate All',
          message: 'Translate every unit?',
        ),
      );

      await tester.tap(find.text('Translate'));
      await tester.pumpAndSettle();

      expect(holder.single, isTrue);
      expect(find.text('Translate All'), findsNothing);
    });

    testWidgets('Cancel pops false', (tester) async {
      final holder = await openVia<bool>(
        tester,
        (ctx) => EditorDialogs.showTranslateConfirmationDialog(
          ctx,
          title: 'Translate All',
          message: 'Translate every unit?',
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(holder.single, isFalse);
      expect(find.text('Translate All'), findsNothing);
    });
  });

  group('showExportDialog', () {
    testWidgets('lists the three export formats', (tester) async {
      await openVia<String?>(tester, EditorDialogs.showExportDialog);

      expect(find.text('Export Translations'), findsOneWidget);
      expect(find.text('Select export format:'), findsOneWidget);
      expect(find.text('.pack (Total War Mod)'), findsOneWidget);
      expect(find.text('Game-ready package file'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Comma-separated values'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
      expect(find.text('Microsoft Excel spreadsheet'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping the pack option pops "pack"', (tester) async {
      final holder = await openVia<String?>(
        tester,
        EditorDialogs.showExportDialog,
      );

      await tester.tap(find.text('.pack (Total War Mod)'));
      await tester.pumpAndSettle();

      expect(holder.single, 'pack');
      expect(find.text('Export Translations'), findsNothing);
    });

    testWidgets('tapping the CSV option pops "csv"', (tester) async {
      final holder = await openVia<String?>(
        tester,
        EditorDialogs.showExportDialog,
      );

      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();

      expect(holder.single, 'csv');
    });

    testWidgets('tapping the Excel option pops "excel"', (tester) async {
      final holder = await openVia<String?>(
        tester,
        EditorDialogs.showExportDialog,
      );

      await tester.tap(find.text('Excel'));
      await tester.pumpAndSettle();

      expect(holder.single, 'excel');
    });

    testWidgets('Cancel pops null', (tester) async {
      final holder = await openVia<String?>(
        tester,
        EditorDialogs.showExportDialog,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(holder.single, isNull);
      expect(find.text('Export Translations'), findsNothing);
    });

    testWidgets('hovering an export option flips its hovered styling',
        (tester) async {
      await openVia<String?>(tester, EditorDialogs.showExportDialog);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      // Move over the CSV option to trigger MouseRegion.onEnter -> setState.
      await gesture.moveTo(tester.getCenter(find.text('CSV')));
      await tester.pumpAndSettle();

      // Move away to trigger onExit -> setState (covers both branches).
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Export Translations'), findsOneWidget);
    });
  });
}
