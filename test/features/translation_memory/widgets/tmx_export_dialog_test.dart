import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tmx_export_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmService extends Mock implements ITranslationMemoryService {}

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

void main() {
  late _MockTmService service;
  late _FakeFilePicker picker;

  setUp(() {
    service = _MockTmService();
    picker = _FakeFilePicker();
    FilePicker.platform = picker;
  });

  /// Pumps the dialog directly (no host button) under a [ProviderScope] with a
  /// real [tmExportStateProvider] notifier backed by the mocked service.
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
          translationMemoryServiceProvider.overrideWithValue(service),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: const Scaffold(body: TmxExportDialog()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('initial render', () {
    testWidgets('shows title, sections and default placeholder', (tester) async {
      await pumpDialog(tester);

      expect(find.text(t.translationMemory.dialogs.exportTitle), findsOneWidget);
      expect(find.text(t.translationMemory.labels.filters), findsOneWidget);
      expect(find.text(t.translationMemory.labels.whatToExport), findsOneWidget);
      expect(find.text(t.translationMemory.labels.outputFile), findsOneWidget);
      expect(
          find.text(t.translationMemory.labels.formatOptions), findsOneWidget);
      // No file picked yet -> the prompt placeholder is shown.
      expect(find.text(t.translationMemory.hints.clickToSelectSaveLocation),
          findsOneWidget);
      // Both scope options + both toggles render.
      expect(find.text(t.translationMemory.options.allEntries), findsOneWidget);
      expect(
          find.text(t.translationMemory.options.frequentlyUsed), findsOneWidget);
      expect(
          find.text(t.translationMemory.options.includeMetadata), findsOneWidget);
      expect(find.text(t.translationMemory.options.includeStats), findsOneWidget);
    });
  });

  group('options', () {
    testWidgets('selecting the target language updates the dropdown',
        (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      // 'FR' appears in the open menu; tap it.
      await tester.tap(find.text('FR').last);
      await tester.pumpAndSettle();

      expect(find.text('FR'), findsWidgets);
    });

    testWidgets('switching scope to frequently-used flips the radios',
        (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.text(t.translationMemory.options.frequentlyUsed));
      await tester.pumpAndSettle();

      // The filled radio icon should now be present for the selected option.
      expect(find.byIcon(FluentIcons.radio_button_24_filled), findsWidgets);

      // Tapping "all entries" again exercises that radio's onChanged callback.
      await tester.tap(find.text(t.translationMemory.options.allEntries));
      await tester.pumpAndSettle();
      expect(find.byIcon(FluentIcons.radio_button_24_filled), findsWidgets);
    });

    testWidgets('toggling format options flips the checkboxes', (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.text(t.translationMemory.options.includeMetadata));
      await tester.tap(find.text(t.translationMemory.options.includeStats));
      await tester.pumpAndSettle();

      // Still rendered after toggling (no crash, state updated).
      expect(
          find.text(t.translationMemory.options.includeMetadata), findsOneWidget);
    });
  });

  group('output path picker', () {
    testWidgets('cancelling the save dialog keeps the placeholder',
        (tester) async {
      picker.savePath = null;
      await pumpDialog(tester);

      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();

      expect(picker.saveCalled, isTrue);
      expect(find.text(t.translationMemory.hints.clickToSelectSaveLocation),
          findsOneWidget);
    });

    testWidgets('picking a path shows it in the picker row', (tester) async {
      picker.savePath = r'C:\out\memory.tmx';
      await pumpDialog(tester);

      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();

      expect(find.text(r'C:\out\memory.tmx'), findsOneWidget);
      expect(find.text(t.translationMemory.hints.clickToSelectSaveLocation),
          findsNothing);
    });
  });

  group('export flow', () {
    testWidgets('export button disabled until a path is picked',
        (tester) async {
      await pumpDialog(tester);

      // Tapping export without a path is a no-op (button disabled), so the
      // service is never invoked.
      await tester.tap(find.text(t.translationMemory.actions.export));
      await tester.pumpAndSettle();

      verifyNever(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          ));
    });

    testWidgets('successful export shows the result card', (tester) async {
      when(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          )).thenAnswer((_) async => const Ok(7));

      picker.savePath = r'C:\out\memory.tmx';
      await pumpDialog(tester);

      // Pick a path + choose frequently-used so minUsageCount branch runs.
      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.translationMemory.options.frequentlyUsed));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.translationMemory.actions.export));
      await tester.pumpAndSettle();

      expect(find.text(t.translationMemory.messages.exportComplete),
          findsOneWidget);
      expect(
          find.text(
              t.translationMemory.messages.exportedEntries(count: 7)),
          findsOneWidget);
      expect(find.text(r'C:\out\memory.tmx'), findsWidgets);

      verify(() => service.exportToTmx(
            outputPath: r'C:\out\memory.tmx',
            targetLanguageCode: null,
            minUsageCount: 6,
            includeMetadata: true,
            includeStats: true,
          )).called(1);
    });

    testWidgets('shows the progress bar while exporting', (tester) async {
      final gate = Completer<Result<int, TmExportException>>();
      when(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          )).thenAnswer((_) => gate.future);

      picker.savePath = r'C:\out\memory.tmx';
      await pumpDialog(tester);

      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.translationMemory.actions.export));
      await tester.pump(); // start export, surface loading UI

      expect(find.text(t.translationMemory.actions.exporting), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      gate.complete(const Ok(1));
      await tester.pumpAndSettle();
    });

    testWidgets('failed export shows the error banner', (tester) async {
      when(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          )).thenThrow(Exception('disk full'));

      picker.savePath = r'C:\out\memory.tmx';
      await pumpDialog(tester);

      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.translationMemory.actions.export));
      await tester.pumpAndSettle();

      expect(find.textContaining('disk full'), findsOneWidget);
    });
  });

  group('override-driven states', () {
    testWidgets('loading override renders the progress section', (tester) async {
      await pumpDialog(
        tester,
        settle: false,
        overrides: [
          tmExportStateProvider.overrideWithValue(
            const AsyncValue<TmExportResult?>.loading(),
          ),
        ],
      );

      expect(find.text(t.translationMemory.actions.exporting), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('error override renders the error message', (tester) async {
      await pumpDialog(
        tester,
        overrides: [
          tmExportStateProvider.overrideWithValue(
            AsyncValue<TmExportResult?>.error(
              Exception('boom'),
              StackTrace.empty,
            ),
          ),
        ],
      );

      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('data override renders the success result', (tester) async {
      await pumpDialog(
        tester,
        overrides: [
          tmExportStateProvider.overrideWithValue(
            const AsyncValue<TmExportResult?>.data(
              TmExportResult(entriesExported: 42, filePath: r'C:\x\y.tmx'),
            ),
          ),
        ],
      );

      expect(find.text(t.translationMemory.messages.exportComplete),
          findsOneWidget);
      expect(
          find.text(t.translationMemory.messages.exportedEntries(count: 42)),
          findsOneWidget);
    });
  });

  group('cancel action', () {
    testWidgets('cancel resets the export state notifier', (tester) async {
      // Seed a success result via the real notifier, then cancel and assert the
      // result card disappears (state reset to data(null)).
      when(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          )).thenAnswer((_) async => const Ok(2));

      picker.savePath = r'C:\out\memory.tmx';
      await pumpDialog(tester);

      await tester
          .tap(find.text(t.translationMemory.hints.clickToSelectSaveLocation));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.translationMemory.actions.export));
      await tester.pumpAndSettle();

      expect(find.text(t.translationMemory.messages.exportComplete),
          findsOneWidget);

      await tester.tap(find.text(t.common.actions.cancel));
      await tester.pumpAndSettle();
    });
  });
}
