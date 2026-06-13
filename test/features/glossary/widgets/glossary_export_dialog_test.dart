// Widget coverage tests for
// lib/features/glossary/widgets/glossary_export_dialog.dart.
//
// The dialog drives the GlossaryExportState notifier to export a glossary to a
// CSV file. It uses a SAVE file picker to choose the output path, then calls
// exportCsv. These tests render every UI state (initial, exporting/loading,
// success with ExportResult summary, error), exercise the save picker (pick a
// path / cancel), and trigger the export action.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_export_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryService extends Mock implements IGlossaryService {}

/// Fake [FilePicker] installed as `FilePicker.platform`. Returns [savePath]
/// from `saveFile`, sidestepping the real native picker.
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  String? savePath;
  bool saveCalled = false;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveCalled = true;
    return savePath;
  }
}

/// Drives [GlossaryExportState] to a fixed [AsyncValue] so the dialog renders
/// the loading / success / error branches deterministically.
class _FakeExportState extends GlossaryExportState {
  _FakeExportState(this._value);

  final AsyncValue<ExportResult?> _value;

  @override
  AsyncValue<ExportResult?> build() => _value;
}

const _glossaryId = 'glossary-1';

void main() {
  late _MockGlossaryService service;
  late _FakeFilePicker picker;

  setUp(() {
    service = _MockGlossaryService();
    picker = _FakeFilePicker();
    FilePicker.platform = picker;
  });

  /// Pump the dialog inside a nested Navigator under an Overlay, so the
  /// FluentToast's `Overlay.of(...)` resolves. The dialog body lives on a tall
  /// surface to avoid Column overflow.
  Future<void> pumpDialog(
    WidgetTester tester, {
    List<Override> overrides = const [],
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          glossaryServiceProvider.overrideWithValue(service),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (navContext) => Center(
                        child: ElevatedButton(
                          onPressed: () => showDialog<void>(
                            context: navContext,
                            useRootNavigator: false,
                            builder: (_) => const GlossaryExportDialog(
                              glossaryId: _glossaryId,
                            ),
                          ),
                          child: const Text('open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A continuously-animating progress bar would make pumpAndSettle time
      // out; pump a few frames without settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('renders the initial state with the output-file prompt',
      (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.glossary.dialogs.exportTitle), findsOneWidget);
    expect(find.text(t.glossary.labels.outputFile), findsOneWidget);
    expect(
        find.text(t.glossary.hints.clickToSelectOutputFile), findsOneWidget);
    // No banner / progress yet.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('picking a save path shows the selected path', (tester) async {
    picker.savePath = r'C:\out\glossary.csv';

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectOutputFile));
    await tester.pumpAndSettle();

    expect(picker.saveCalled, isTrue);
    expect(find.text(r'C:\out\glossary.csv'), findsOneWidget);
    expect(find.text(t.glossary.hints.clickToSelectOutputFile), findsNothing);
  });

  testWidgets('cancelling the save picker keeps the placeholder',
      (tester) async {
    picker.savePath = null; // user cancelled

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectOutputFile));
    await tester.pumpAndSettle();

    expect(picker.saveCalled, isTrue);
    expect(
        find.text(t.glossary.hints.clickToSelectOutputFile), findsOneWidget);
  });

  testWidgets('tapping Export with no path shows a "select file" toast',
      (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text(t.glossary.actions.export));
    await tester.pump();

    expect(find.text(t.glossary.messages.pleaseSelectOutputFile),
        findsOneWidget);
    verifyNever(() => service.exportToCsv(
          glossaryId: any(named: 'glossaryId'),
          filePath: any(named: 'filePath'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        ));

    // Drain the toast's auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('selecting a path then Export calls exportToCsv', (tester) async {
    when(() => service.exportToCsv(
          glossaryId: any(named: 'glossaryId'),
          filePath: any(named: 'filePath'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => const Ok(5));

    picker.savePath = r'C:\out\glossary.csv';

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectOutputFile));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.glossary.actions.export));
    await tester.pumpAndSettle();

    verify(() => service.exportToCsv(
          glossaryId: _glossaryId,
          filePath: r'C:\out\glossary.csv',
        )).called(1);
  });

  testWidgets('export error surfaces through the error banner', (tester) async {
    when(() => service.exportToCsv(
          glossaryId: any(named: 'glossaryId'),
          filePath: any(named: 'filePath'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer(
        (_) async => const Err(GlossaryDatabaseException('disk full')));

    picker.savePath = r'C:\out\glossary.csv';

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectOutputFile));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.glossary.actions.export));
    await tester.pumpAndSettle();

    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('loading state shows the exporting progress indicator',
      (tester) async {
    await pumpDialog(tester, settle: false, overrides: [
      glossaryExportStateProvider.overrideWith(
        () => _FakeExportState(const AsyncValue.loading()),
      ),
    ]);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // The exporting label appears in the body and on the disabled action button.
    expect(find.text(t.glossary.actions.exporting), findsWidgets);
  });

  testWidgets('success state renders the ExportResult summary banner',
      (tester) async {
    const result =
        ExportResult(entriesExported: 12, filePath: r'C:\out\glossary.csv');
    await pumpDialog(tester, overrides: [
      glossaryExportStateProvider.overrideWith(
        () => _FakeExportState(const AsyncValue.data(result)),
      ),
    ]);

    expect(find.text(t.glossary.labels.exportSummary), findsOneWidget);
    expect(find.text(result.summary), findsOneWidget);
  });

  testWidgets('error state renders the error banner', (tester) async {
    await pumpDialog(tester, overrides: [
      glossaryExportStateProvider.overrideWith(
        () => _FakeExportState(
          AsyncValue.error('kaboom', StackTrace.empty),
        ),
      ),
    ]);

    expect(find.textContaining('kaboom'), findsOneWidget);
  });

  testWidgets('Close button pops the dialog', (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.glossary.dialogs.exportTitle), findsOneWidget);

    await tester.tap(find.text(t.common.actions.close));
    await tester.pumpAndSettle();

    expect(find.text(t.glossary.dialogs.exportTitle), findsNothing);
  });
}
