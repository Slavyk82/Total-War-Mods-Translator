// Widget coverage tests for
// lib/features/glossary/widgets/glossary_import_dialog.dart.
//
// The dialog resolves the glossary's target-language code (via
// IGlossaryService.getGlossaryById + LanguageRepository.getById) and drives the
// GlossaryImportState notifier to run a CSV import. These tests render every UI
// state (initial, language-resolved, language-error, importing, success,
// error), exercise the file picker, and trigger the import action.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_import_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryService extends Mock implements IGlossaryService {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

/// Fake FilePicker installed as `FilePicker.platform`; returns [result] from
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

/// Drives [GlossaryImportState] to a fixed [AsyncValue] so the dialog renders
/// the loading / success / error branches deterministically.
class _FakeImportState extends GlossaryImportState {
  _FakeImportState(this._value);

  final AsyncValue<ImportResult?> _value;

  @override
  AsyncValue<ImportResult?> build() => _value;
}

const _glossaryId = 'glossary-1';
const _err = GlossaryDatabaseException('boom');

Glossary _glossary() => Glossary(
      id: _glossaryId,
      name: 'Test',
      gameCode: 'wh3',
      targetLanguageId: 'lang-fr',
      createdAt: 1700000000,
      updatedAt: 1700000000,
    );

Language _lang() =>
    const Language(id: 'lang-fr', code: 'fr', name: 'French', nativeName: 'Français');

void main() {
  late _MockGlossaryService service;
  late _MockLanguageRepository langRepo;
  late _FakeFilePicker picker;

  setUp(() {
    service = _MockGlossaryService();
    langRepo = _MockLanguageRepository();
    picker = _FakeFilePicker();
    FilePicker.platform = picker;

    // Default: resolve the glossary language successfully.
    when(() => service.getGlossaryById(any()))
        .thenAnswer((_) async => Ok(_glossary()));
    when(() => langRepo.getById(any())).thenAnswer((_) async => Ok(_lang()));
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
          languageRepositoryProvider.overrideWithValue(langRepo),
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
                            builder: (_) => const GlossaryImportDialog(
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
      // The dialog's open animation + the async language resolution; pump a few
      // frames without settling (a continuously-animating progress bar would
      // make pumpAndSettle time out).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('renders the initial state with the file prompt and language',
      (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.glossary.dialogs.importTitle), findsOneWidget);
    expect(find.text(t.glossary.hints.clickToSelectFile), findsOneWidget);
    expect(find.text(t.glossary.hints.skipDuplicates), findsOneWidget);
    // Resolved language code is shown upper-cased.
    expect(find.text('FR'), findsOneWidget);

    verify(() => service.getGlossaryById(_glossaryId)).called(1);
    verify(() => langRepo.getById('lang-fr')).called(1);
  });

  testWidgets('toggling skip-duplicates flips the checkbox', (tester) async {
    await pumpDialog(tester);

    // Tapping the option toggle rebuilds; just ensure no exception and the
    // toggle row remains rendered.
    await tester.tap(find.text(t.glossary.hints.skipDuplicates));
    await tester.pumpAndSettle();

    expect(find.text(t.glossary.hints.skipDuplicatesHint), findsOneWidget);
  });

  testWidgets('shows "-" when language resolution fails', (tester) async {
    when(() => service.getGlossaryById(any()))
        .thenAnswer((_) async => const Err(_err));

    await pumpDialog(tester);

    expect(find.text('-'), findsOneWidget);
    expect(find.text('FR'), findsNothing);
  });

  testWidgets('language repo error also surfaces the "-" placeholder',
      (tester) async {
    when(() => langRepo.getById(any()))
        .thenAnswer((_) async => Err(TWMTDatabaseException('lang boom')));

    await pumpDialog(tester);

    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('picking a CSV file shows the selected path', (tester) async {
    picker.result = FilePickerResult([
      PlatformFile(name: 'g.csv', size: 0, path: r'C:\g.csv'),
    ]);

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectFile));
    await tester.pumpAndSettle();

    expect(find.text(r'C:\g.csv'), findsOneWidget);
    expect(find.text(t.glossary.hints.clickToSelectFile), findsNothing);
  });

  testWidgets('picking nothing keeps the placeholder', (tester) async {
    picker.result = null; // user cancelled

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectFile));
    await tester.pumpAndSettle();

    expect(find.text(t.glossary.hints.clickToSelectFile), findsOneWidget);
  });

  testWidgets('tapping Import with no file shows a "select file" toast',
      (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text(t.glossary.actions.import));
    await tester.pump();

    expect(find.text(t.glossary.messages.pleaseSelectFile), findsOneWidget);
    verifyNever(() => service.importFromCsv(
          glossaryId: any(named: 'glossaryId'),
          filePath: any(named: 'filePath'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          skipDuplicates: any(named: 'skipDuplicates'),
        ));

    // Drain the toast's auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('selecting a file then Import calls importFromCsv', (tester) async {
    when(() => service.importFromCsv(
          glossaryId: any(named: 'glossaryId'),
          filePath: any(named: 'filePath'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          skipDuplicates: any(named: 'skipDuplicates'),
        )).thenAnswer((_) async => const Ok(4));

    picker.result = FilePickerResult([
      PlatformFile(name: 'g.csv', size: 0, path: r'C:\g.csv'),
    ]);

    await pumpDialog(tester);
    await tester.tap(find.text(t.glossary.hints.clickToSelectFile));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.glossary.actions.import));
    await tester.pumpAndSettle();

    verify(() => service.importFromCsv(
          glossaryId: _glossaryId,
          filePath: r'C:\g.csv',
          targetLanguageCode: 'fr',
          skipDuplicates: true,
        )).called(1);
  });

  testWidgets('loading state shows the importing progress indicator',
      (tester) async {
    await pumpDialog(tester, settle: false, overrides: [
      glossaryImportStateProvider.overrideWith(
        () => _FakeImportState(const AsyncValue.loading()),
      ),
    ]);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // The importing label appears in the body and on the disabled action button.
    expect(find.text(t.glossary.actions.importing), findsWidgets);
  });

  testWidgets('success state renders the ImportResult summary banner',
      (tester) async {
    const result = ImportResult(total: 9, imported: 7, skipped: 2, failed: 0);
    await pumpDialog(tester, overrides: [
      glossaryImportStateProvider.overrideWith(
        () => _FakeImportState(const AsyncValue.data(result)),
      ),
    ]);

    expect(find.text(t.glossary.labels.importSummary), findsOneWidget);
    expect(find.text(result.summary), findsOneWidget);
  });

  testWidgets('error state renders the error banner', (tester) async {
    await pumpDialog(tester, overrides: [
      glossaryImportStateProvider.overrideWith(
        () => _FakeImportState(
          AsyncValue.error('kaboom', StackTrace.empty),
        ),
      ),
    ]);

    expect(find.textContaining('kaboom'), findsOneWidget);
  });

  testWidgets('Close button pops the dialog', (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.glossary.dialogs.importTitle), findsOneWidget);

    await tester.tap(find.text(t.common.actions.close));
    await tester.pumpAndSettle();

    expect(find.text(t.glossary.dialogs.importTitle), findsNothing);
  });
}
