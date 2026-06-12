import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:twmt/features/translation_editor/services/pack_import_service.dart';
import 'package:twmt/features/translation_editor/widgets/pack_import_dialog.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

class _MockImportService extends Mock implements PackImportService {}

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

const _projectId = 'project-1';
const _languageId = 'language-fr';

PackImportEntry _entry(String key, String value, {required bool conflict}) =>
    PackImportEntry(
      unit: TranslationUnit(
        id: key,
        projectId: _projectId,
        key: key,
        sourceText: 'source of $key',
        createdAt: 0,
        updatedAt: 0,
      ),
      existingVersion: conflict
          ? TranslationVersion(
              id: 'v-$key',
              unitId: key,
              projectLanguageId: 'pl-1',
              translatedText: 'existing',
              status: TranslationVersionStatus.translated,
              createdAt: 0,
              updatedAt: 0,
            )
          : null,
      importedValue: value,
      key: key,
    );

PackImportPreview _preview(List<PackImportEntry> entries) => PackImportPreview(
      matchingEntries: entries,
      unmatchedEntries: const [],
      totalEntriesInPack: 5,
      packFilePath: r'C:\mods\x.pack',
    );

void main() {
  late _MockImportService service;
  late _FakeFilePicker picker;

  setUpAll(() {
    registerFallbackValue(<PackImportEntry>[]);
  });

  setUp(() {
    service = _MockImportService();
    picker = _FakeFilePicker();
    FilePicker.platform = picker;

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1600, 1400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  void stubPreview(Result<PackImportPreview, String> result) {
    when(() => service.previewImport(
          packFilePath: any(named: 'packFilePath'),
          projectId: any(named: 'projectId'),
          languageId: any(named: 'languageId'),
        )).thenAnswer((_) async => result);
  }

  void setPickedFile() {
    picker.result = FilePickerResult([
      PlatformFile(name: 'x.pack', size: 0, path: r'C:\mods\x.pack'),
    ]);
  }

  var importCompleteCalls = 0;

  Future<void> pumpDialog(WidgetTester tester) async {
    importCompleteCalls = 0;
    // Host the dialog inside a nested Navigator that sits under an Overlay, so
    // the result toast's `Overlay.of(Navigator.context)` resolves (the bare
    // MaterialApp root navigator has no Overlay ancestor; the real app shell
    // provides one). showDialog uses this nested navigator (useRootNavigator:
    // false) so the toast survives the dialog pop.
    await tester.pumpWidget(createThemedTestableWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (navContext) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: navContext,
                      useRootNavigator: false,
                      builder: (_) => PackImportDialog(
                        projectId: _projectId,
                        languageId: _languageId,
                        importService: service,
                        onImportComplete: () => importCompleteCalls++,
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
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Opens the dialog, picks a file and loads [entries] as the preview.
  Future<void> pumpWithPreview(
    WidgetTester tester,
    List<PackImportEntry> entries,
  ) async {
    stubPreview(Ok(_preview(entries)));
    setPickedFile();
    await pumpDialog(tester);
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
  }

  testWidgets('initial state prompts to select a pack file', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Import translations from a .pack file'), findsOneWidget);
    expect(find.text('No file selected'), findsOneWidget);
    expect(find.text('Select a .pack file containing translations'),
        findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('shows a spinner while analyzing the pack', (tester) async {
    when(() => service.previewImport(
          packFilePath: any(named: 'packFilePath'),
          projectId: any(named: 'projectId'),
          languageId: any(named: 'languageId'),
        )).thenAnswer(
      (_) => Completer<Result<PackImportPreview, String>>().future,
    );
    setPickedFile();
    await pumpDialog(tester);

    await tester.tap(find.text('Browse'));
    await tester.pump(); // run _selectFile / start _loadPreview
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Analyzing pack file...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error banner when the preview fails', (tester) async {
    stubPreview(const Err('corrupt pack header'));
    setPickedFile();
    await pumpDialog(tester);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    expect(find.text('corrupt pack header'), findsOneWidget);
  });

  testWidgets('renders the summary, grid and import count on a valid preview',
      (tester) async {
    await pumpWithPreview(tester, [
      _entry('key.a', 'Bonjour', conflict: false),
      _entry('key.b', 'Salut', conflict: true),
    ]);

    // Summary card values
    expect(find.text('Analysis Summary'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // total in pack

    // Grid content
    expect(find.text('key.a'), findsOneWidget);
    expect(find.text('key.b'), findsOneWidget);
    expect(find.text('New'), findsWidgets); // summary label + status chip
    expect(find.text('Conflict'), findsOneWidget);

    // Both entries selected by default -> Import (2)
    expect(find.text('Import (2)'), findsOneWidget);
    expect(find.text('Deselect all'), findsOneWidget);
  });

  testWidgets('shows the empty state when no entries match', (tester) async {
    await pumpWithPreview(tester, const []);

    expect(find.text('No matching translations found'), findsOneWidget);
    expect(find.text('Import (0)'), findsOneWidget);
  });

  testWidgets('toggling select-all clears the selection', (tester) async {
    await pumpWithPreview(tester, [
      _entry('key.a', 'Bonjour', conflict: false),
      _entry('key.b', 'Salut', conflict: true),
    ]);

    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();

    expect(find.text('Import (0)'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('shows progress while importing then closes and notifies',
      (tester) async {
    final gate = Completer<Result<PackImportResult, String>>();
    when(() => service.executeImport(
          entriesToImport: any(named: 'entriesToImport'),
          projectId: any(named: 'projectId'),
          languageId: any(named: 'languageId'),
          overwriteExisting: any(named: 'overwriteExisting'),
          onProgress: any(named: 'onProgress'),
          isCancelled: any(named: 'isCancelled'),
        )).thenAnswer((invocation) {
      final onProgress = invocation.namedArguments[#onProgress]
          as void Function(int, int, String)?;
      onProgress?.call(1, 2, 'Importing key.a');
      return gate.future;
    });

    await pumpWithPreview(tester, [
      _entry('key.a', 'Bonjour', conflict: false),
      _entry('key.b', 'Salut', conflict: true),
    ]);

    await tester.tap(find.text('Import (2)'));
    await tester.pump(); // start import, surface progress UI

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('1 / 2 entries processed'), findsOneWidget);

    // Finish the import.
    gate.complete(const Ok(PackImportResult(
      importedCount: 2,
      skippedCount: 0,
      errorCount: 0,
      errors: [],
    )));
    await tester.pumpAndSettle();

    // Dialog closed + parent notified.
    expect(find.text('Import translations from a .pack file'), findsNothing);
    expect(importCompleteCalls, 1);

    // Drain the result toast's 4s auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error banner when the import fails', (tester) async {
    when(() => service.executeImport(
          entriesToImport: any(named: 'entriesToImport'),
          projectId: any(named: 'projectId'),
          languageId: any(named: 'languageId'),
          overwriteExisting: any(named: 'overwriteExisting'),
          onProgress: any(named: 'onProgress'),
          isCancelled: any(named: 'isCancelled'),
        )).thenAnswer((_) async => const Err('disk full'));

    await pumpWithPreview(tester, [
      _entry('key.a', 'Bonjour', conflict: false),
    ]);

    await tester.tap(find.text('Import (1)'));
    await tester.pumpAndSettle();

    expect(find.text('disk full'), findsOneWidget);
    expect(importCompleteCalls, 0);
  });
}
