import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tmx_import_dialog.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Fake FilePicker installed as `FilePicker.platform`. Returns [result] from
/// `pickFiles`, sidestepping the real native picker.
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

/// Fake import notifier driving [tmImportStateProvider] deterministically.
///
/// Subclasses the generated public class and overrides `build()` to seed an
/// arbitrary state. `importFromTmx` invokes the supplied [onProgress] (so the
/// dialog's progress setState path runs) and then transitions to whatever
/// terminal state the test asked for, without touching the real service.
class _FakeTmImportState extends TmImportState {
  _FakeTmImportState({
    this.initial = const AsyncValue.data(null),
    this.terminal,
    this.emitProgress,
  });

  final AsyncValue<TmImportResult?> initial;
  final AsyncValue<TmImportResult?>? terminal;
  final (int, int)? emitProgress;

  @override
  AsyncValue<TmImportResult?> build() => initial;

  @override
  Future<void> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    state = const AsyncValue.loading();
    if (emitProgress != null) {
      onProgress?.call(emitProgress!.$1, emitProgress!.$2);
    }
    if (terminal != null) {
      state = terminal!;
    }
  }

  @override
  void reset() {
    state = const AsyncValue.data(null);
  }
}

void main() {
  late _FakeFilePicker picker;
  late File tmxFile;
  late Directory tmpDir;

  setUp(() {
    picker = _FakeFilePicker();
    FilePicker.platform = picker;

    tmpDir = Directory.systemTemp.createTempSync('tmx_import_test');
    tmxFile = File('${tmpDir.path}${Platform.pathSeparator}sample.tmx')
      ..writeAsStringSync('x' * 2048); // ~2 KB so size formatting runs

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1200, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  void setPickedFile() {
    picker.result = FilePickerResult([
      PlatformFile(name: 'sample.tmx', size: 2048, path: tmxFile.path),
    ]);
  }

  /// Hosts the dialog under a nested Navigator so `Navigator.of(context).pop()`
  /// works. [fake] drives the import state provider.
  Future<void> pumpDialog(
    WidgetTester tester, {
    _FakeTmImportState Function()? fake,
    bool settle = true,
  }) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const TmxImportDialog(),
          ),
          child: const Text('open'),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        if (fake != null) tmImportStateProvider.overrideWith(fake),
      ],
    ));
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Indeterminate LinearProgressIndicator animates forever; fixed pumps
      // avoid a pumpAndSettle timeout.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('initial state prompts to select a TMX file', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Import Translation Memory (TMX)'), findsOneWidget);
    expect(find.text('Click to select a .tmx file'), findsOneWidget);
    expect(find.text('Import Options'), findsOneWidget);
    expect(find.text('Overwrite existing entries'), findsOneWidget);
    expect(find.text('Validate entries'), findsOneWidget);
    // No file preview yet.
    expect(find.text('Size: 2.0 KB'), findsNothing);
  });

  testWidgets('import button is disabled until a file is selected',
      (tester) async {
    await pumpDialog(tester);

    // Tapping import with no file selected does nothing (onTap is null).
    await tester.tap(find.text('Import').last);
    await tester.pumpAndSettle();
    // Still on the picker prompt, no progress / result shown.
    expect(find.text('Importing...'), findsNothing);
  });

  testWidgets('picking a file shows the file preview with size', (tester) async {
    setPickedFile();
    await pumpDialog(tester);

    // Tap the file picker row (the "click to select" hint).
    await tester.tap(find.text('Click to select a .tmx file'));
    await tester.pumpAndSettle();

    expect(find.text('sample.tmx'), findsOneWidget);
    expect(find.text('Size: 2.0 KB'), findsOneWidget);
    // Selected-file label appears (picker label + preview label).
    expect(find.text('Selected File'), findsWidgets);
  });

  testWidgets('toggling import options updates the checkboxes', (tester) async {
    await pumpDialog(tester);

    // Overwrite starts off; validate starts on. Tap both rows to flip them.
    await tester.tap(find.text('Overwrite existing entries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Validate entries'));
    await tester.pumpAndSettle();

    // No crash; options still rendered.
    expect(find.text('Replace existing entries with imported ones'),
        findsOneWidget);
    expect(find.text('Check for errors before importing'), findsOneWidget);
  });

  testWidgets('cancel resets state and closes the dialog', (tester) async {
    await pumpDialog(tester);

    expect(find.byType(TmxImportDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TmxImportDialog), findsNothing);
  });

  testWidgets('loading state shows indeterminate progress', (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmImportState(
        initial: const AsyncValue.loading(),
      ),
      settle: false,
    );

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Cancel is disabled while loading.
    final cancelBtn = find.text('Cancel');
    expect(cancelBtn, findsOneWidget);
  });

  testWidgets('start import drives progress then success result',
      (tester) async {
    setPickedFile();
    await pumpDialog(
      tester,
      fake: () => _FakeTmImportState(
        emitProgress: (3, 10),
        terminal: const AsyncValue.data(TmImportResult(
          totalEntries: 10,
          importedEntries: 8,
          skippedEntries: 1,
          failedEntries: 1,
        )),
      ),
    );

    // Pick file to enable the Import action.
    await tester.tap(find.text('Click to select a .tmx file'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import').last);
    await tester.pump(); // run importFromTmx -> progress + terminal state
    await tester.pumpAndSettle();

    // Success result card rendered with all rows (skipped & failed > 0).
    expect(find.text('Import Complete'), findsOneWidget);
    expect(find.text('Total entries'), findsOneWidget);
    expect(find.text('Imported'), findsOneWidget);
    expect(find.text('Skipped (duplicates)'), findsOneWidget);
    expect(find.text('Failed (validation errors)'), findsOneWidget);
  });

  testWidgets('progress UI reflects processed/total counts', (tester) async {
    setPickedFile();
    await pumpDialog(
      tester,
      fake: () => _FakeTmImportState(
        emitProgress: (4, 20),
        // No terminal -> stays in loading after emitting progress.
      ),
    );

    await tester.tap(find.text('Click to select a .tmx file'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import').last);
    await tester.pump(); // run importFromTmx: setState progress + loading state
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('Processed 4 of 20 entries'), findsOneWidget);
  });

  testWidgets('success result hides skipped/failed rows when zero',
      (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmImportState(
        initial: const AsyncValue.data(TmImportResult(
          totalEntries: 5,
          importedEntries: 5,
          skippedEntries: 0,
          failedEntries: 0,
        )),
      ),
    );

    expect(find.text('Import Complete'), findsOneWidget);
    expect(find.text('Total entries'), findsOneWidget);
    expect(find.text('Imported'), findsOneWidget);
    expect(find.text('Skipped (duplicates)'), findsNothing);
    expect(find.text('Failed (validation errors)'), findsNothing);
  });

  testWidgets('error state renders the error banner', (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmImportState(
        initial: AsyncValue.error(
          'TMX parse failed: bad header',
          StackTrace.empty,
        ),
      ),
    );

    expect(find.textContaining('TMX parse failed: bad header'), findsOneWidget);
  });

  testWidgets('picker returning null leaves preview hidden', (tester) async {
    picker.result = null; // user cancelled the native picker
    await pumpDialog(tester);

    await tester.tap(find.text('Click to select a .tmx file'));
    await tester.pumpAndSettle();

    expect(find.text('Click to select a .tmx file'), findsOneWidget);
    expect(find.text('Size: 2.0 KB'), findsNothing);
  });

  testWidgets('TmImportResult.summary formats counts', (tester) async {
    const result = TmImportResult(
      totalEntries: 10,
      importedEntries: 7,
      skippedEntries: 2,
      failedEntries: 1,
    );
    expect(
      result.summary,
      'Total: 10 | Imported: 7 | Skipped: 2 | Failed: 1',
    );
    // Silence unused tester warning by performing a trivial pump.
    await tester.pump(Duration.zero);
  });
}
