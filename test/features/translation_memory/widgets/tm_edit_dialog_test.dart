import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tm_edit_dialog.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Fake update notifier driving [tmUpdateStateProvider] deterministically.
///
/// Subclasses the generated public class and overrides `build()` so the
/// provider resolves without GetIt/the real service. `updateTargetText`
/// records the arguments it was called with and returns the canned
/// [result], so the dialog's success / error branches can both be exercised.
class _FakeTmUpdateState extends TmUpdateState {
  _FakeTmUpdateState({this.result = true});

  final bool result;

  String? capturedEntryId;
  String? capturedTargetText;
  int callCount = 0;

  @override
  AsyncValue<bool?> build() => const AsyncValue.data(null);

  @override
  Future<bool> updateTargetText({
    required String entryId,
    required String newTargetText,
  }) async {
    callCount++;
    capturedEntryId = entryId;
    capturedTargetText = newTargetText;
    return result;
  }
}

void main() {
  late TranslationMemoryEntry entry;
  late _FakeTmUpdateState fakeUpdate;

  setUp(() {
    entry = const TranslationMemoryEntry(
      id: 'tm-1',
      sourceText: 'Hello world',
      sourceHash: 'hash-1',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: 'Bonjour le monde',
      usageCount: 7,
      createdAt: 1700000000,
      lastUsedAt: 1700100000,
      updatedAt: 1700100000,
    );
    fakeUpdate = _FakeTmUpdateState();

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1200, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  /// Hosts the dialog under a nested Navigator (`useRootNavigator: false`) so
  /// `Navigator.of(context).pop()` works and the success toast has an
  /// Overlay above it. [update] drives the update state provider.
  Future<void> pumpDialog(
    WidgetTester tester, {
    _FakeTmUpdateState? update,
    TranslationMemoryEntry? withEntry,
  }) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<String>(
            context: context,
            useRootNavigator: false,
            builder: (_) => TmEditDialog(entry: withEntry ?? entry),
          ),
          child: const Text('open'),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        tmUpdateStateProvider.overrideWith(() => update ?? fakeUpdate),
      ],
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders source, prefilled target and metadata', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Edit TM entry'), findsOneWidget);
    expect(find.text('Source Text'), findsOneWidget);
    expect(find.text('Target Text'), findsOneWidget);
    // Source text is read-only and rendered verbatim.
    expect(find.text('Hello world'), findsOneWidget);
    // Target field is prefilled from the entry's translation.
    expect(find.text('Bonjour le monde'), findsOneWidget);
    // Metadata row.
    expect(find.text('Usage Count'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Last Used'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
  });

  testWidgets('Save is disabled until target text changes', (tester) async {
    await pumpDialog(tester);

    // Unchanged text => canSave is false => tapping Save does nothing.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fakeUpdate.callCount, 0);
    // Dialog still open.
    expect(find.byType(TmEditDialog), findsOneWidget);
  });

  testWidgets('emptying the target field keeps Save disabled', (tester) async {
    await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fakeUpdate.callCount, 0);
    expect(find.byType(TmEditDialog), findsOneWidget);
  });

  testWidgets('editing text then saving calls the notifier and pops',
      (tester) async {
    await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), 'Salut le monde');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump(); // run _handleSave -> updateTargetText
    await tester.pumpAndSettle();

    expect(fakeUpdate.callCount, 1);
    expect(fakeUpdate.capturedEntryId, 'tm-1');
    expect(fakeUpdate.capturedTargetText, 'Salut le monde');
    // Dialog popped on success.
    expect(find.byType(TmEditDialog), findsNothing);
    // Success toast rendered.
    expect(find.text('TM entry updated successfully'), findsOneWidget);

    // Drain the toast auto-dismiss timer (4s) so no pending timers remain.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('save trims surrounding whitespace before calling notifier',
      (tester) async {
    await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), '  Coucou  ');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeUpdate.capturedTargetText, 'Coucou');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('save error keeps the dialog open and shows an error toast',
      (tester) async {
    final failing = _FakeTmUpdateState(result: false);
    await pumpDialog(tester, update: failing);

    await tester.enterText(find.byType(TextField), 'Mauvaise traduction');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(failing.callCount, 1);
    // Dialog stays open on failure.
    expect(find.byType(TmEditDialog), findsOneWidget);
    expect(find.text('Failed to update TM entry'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('cancel closes the dialog without calling the notifier',
      (tester) async {
    await pumpDialog(tester);

    expect(find.byType(TmEditDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TmEditDialog), findsNothing);
    expect(fakeUpdate.callCount, 0);
  });

  testWidgets('long source text scrolls inside the read-only box',
      (tester) async {
    final longEntry = entry.copyWith(
      sourceText: List.generate(40, (i) => 'Line $i of the source').join('\n'),
      usageCount: 0,
    );
    await pumpDialog(tester, withEntry: longEntry);

    // Renders without overflow; usage count of 0 shown.
    expect(find.text('0'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
