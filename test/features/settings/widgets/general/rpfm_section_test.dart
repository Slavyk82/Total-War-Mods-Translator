// Widget coverage tests for
// lib/features/settings/widgets/general/rpfm_section.dart.
//
// The section renders two path fields (RPFM executable + schema folder), each
// with their own action buttons:
//   - Executable: Test (validate current path) + Browse (file picker) + field
//     whose onChanged immediately saves via updateRpfmPath.
//   - Schema:     Default (resolve %APPDATA% path) + Browse (directory picker)
//     + field whose onChanged immediately saves via updateRpfmSchemaPath.
//
// These tests render the section (configured + unconfigured), exercise the
// immediate save on typing, the file/directory pickers (faked
// FilePicker.platform), the Test action (empty path warning + invalid-path
// error), the Default schema button, and the save-error toast path.
//
// Note: RpfmCliManager.validateRpfmPath is a static method that shells out via
// Process.run, so its success (Ok) branch cannot be driven from a widget test
// without a real rpfm_cli.exe; we drive its deterministic failure branches
// (file-not-found / non-.exe) instead. See the "uncovered lines" report.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:twmt/features/settings/widgets/general/rpfm_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Records [updateRpfmPath] / [updateRpfmSchemaPath] calls instead of writing
/// to settings / DB.
class _FakeGeneralSettings extends GeneralSettings {
  final List<String> savedRpfm = [];
  final List<String> savedSchema = [];
  bool throwOnSaveRpfm = false;
  bool throwOnSaveSchema = false;

  @override
  Future<Map<String, String>> build() async => {};

  @override
  Future<void> updateRpfmPath(String path) async {
    if (throwOnSaveRpfm) {
      throw StateError('save failed');
    }
    savedRpfm.add(path);
  }

  @override
  Future<void> updateRpfmSchemaPath(String path) async {
    if (throwOnSaveSchema) {
      throw StateError('save failed');
    }
    savedSchema.add(path);
  }
}

/// Fake [FilePicker] installed as `FilePicker.platform`. Returns a single-file
/// [FilePickerResult] from `pickFiles` (the executable picker) and [dirPath]
/// from `getDirectoryPath` (the schema-folder picker), sidestepping the real
/// native dialogs.
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  String? filePath;
  String? dirPath;
  bool pickFilesCalled = false;
  bool getDirectoryCalled = false;

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
  }) async {
    pickFilesCalled = true;
    if (filePath == null) return null;
    return FilePickerResult([PlatformFile(name: 'rpfm_cli.exe', path: filePath, size: 0)]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    getDirectoryCalled = true;
    return dirPath;
  }
}

void main() {
  late _FakeGeneralSettings settings;
  late TextEditingController rpfmController;
  late TextEditingController schemaController;

  setUp(() {
    settings = _FakeGeneralSettings();
    rpfmController = TextEditingController();
    schemaController = TextEditingController();
  });

  tearDown(() {
    rpfmController.dispose();
    schemaController.dispose();
  });

  Widget host() {
    return ProviderScope(
      overrides: [
        generalSettingsProvider.overrideWith(() => settings),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 1100,
              child: RpfmSection(
                rpfmPathController: rpfmController,
                rpfmSchemaPathController: schemaController,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Drains the 4s toast auto-dismiss timer + its dismiss animation so the
  /// test does not finish with pending timers.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('renders header, both fields and their action buttons',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text(t.settings.general.rpfm.sectionTitle), findsOneWidget);
    expect(find.text(t.settings.general.rpfm.sectionSubtitle), findsOneWidget);
    expect(
      find.text(t.settings.general.rpfm.executableSubtitle),
      findsOneWidget,
    );
    expect(find.text(t.settings.general.rpfm.schemaSubtitle), findsOneWidget);
    expect(
      find.text(t.settings.general.rpfm.schemaDescription),
      findsOneWidget,
    );

    // Two path fields (executable + schema).
    expect(find.byType(TextFormField), findsNWidgets(2));
    // Action buttons: Test, Default and two Browse buttons.
    expect(find.text(t.settings.general.rpfm.testButton), findsOneWidget);
    expect(find.text(t.settings.general.rpfm.defaultButton), findsOneWidget);
    expect(find.text(t.settings.general.rpfm.browseButton), findsNWidgets(2));
  });

  testWidgets('renders configured paths from the controllers', (tester) async {
    rpfmController.text = r'C:\tools\rpfm_cli.exe';
    schemaController.text = r'C:\schemas';

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text(r'C:\tools\rpfm_cli.exe'), findsOneWidget);
    expect(find.text(r'C:\schemas'), findsOneWidget);
  });

  testWidgets('typing in the executable field saves via updateRpfmPath',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // The executable field is the first TextFormField.
    await tester.enterText(
      find.byType(TextFormField).first,
      r'D:\rpfm\rpfm_cli.exe',
    );
    await tester.pump();

    expect(settings.savedRpfm, [r'D:\rpfm\rpfm_cli.exe']);
  });

  testWidgets('typing in the schema field saves via updateRpfmSchemaPath',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // The schema field is the second TextFormField.
    await tester.enterText(
      find.byType(TextFormField).last,
      r'D:\schemas\wh3',
    );
    await tester.pump();

    expect(settings.savedSchema, [r'D:\schemas\wh3']);
  });

  testWidgets('save error on the executable field surfaces an error toast',
      (tester) async {
    settings.throwOnSaveRpfm = true;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, r'X:\bad.exe');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Error saving RPFM path'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('save error on the schema field surfaces an error toast',
      (tester) async {
    settings.throwOnSaveSchema = true;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).last, r'X:\bad');
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Error saving RPFM schema path'),
      findsOneWidget,
    );
    await drainToast(tester);
  });

  testWidgets('Test with empty path shows the "enter path first" warning',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text(t.settings.general.rpfm.testButton));
    await tester.pump();

    expect(
      find.text(t.settings.general.rpfm.toasts.enterPathFirst),
      findsOneWidget,
    );
    await drainToast(tester);
  });

  testWidgets(
      'Test with a non-existent path shows testing then a test-failed toast',
      (tester) async {
    rpfmController.text = r'Z:\definitely\missing\rpfm_cli.exe';

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text(t.settings.general.rpfm.testButton));
    await tester.pump();

    // The "Testing..." info toast is shown synchronously before validation.
    expect(
      find.text(t.settings.general.rpfm.toasts.testing),
      findsOneWidget,
    );

    // validateRpfmPath performs real filesystem I/O (File.exists), which only
    // resolves under runAsync; the missing file -> Err -> testFailed toast.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('RPFM test failed'), findsWidgets);
    await drainToast(tester);
  });

  testWidgets(
      'Browse executable: picking a (non-existent) file validates and shows '
      'an invalid-exe error toast', (tester) async {
    final picker = _FakeFilePicker()
      ..filePath = r'Z:\missing\rpfm_cli.exe';
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // First Browse button belongs to the executable row.
    await tester.tap(find.text(t.settings.general.rpfm.browseButton).first);
    await tester.pump();

    expect(picker.pickFilesCalled, isTrue);
    // The "Validating..." info toast appears before validation completes.
    expect(
      find.text(t.settings.general.rpfm.toasts.validating),
      findsOneWidget,
    );

    // validateRpfmPath does real filesystem I/O (File.exists), which only
    // resolves under runAsync; the missing file -> Err -> invalid-exe toast.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('Invalid RPFM executable'), findsWidgets);
    expect(settings.savedRpfm, isEmpty);
    await drainToast(tester);
  });

  testWidgets('Browse executable cancelled (null) does nothing', (tester) async {
    final picker = _FakeFilePicker()..filePath = null;
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text(t.settings.general.rpfm.browseButton).first);
    await tester.pumpAndSettle();

    expect(picker.pickFilesCalled, isTrue);
    expect(settings.savedRpfm, isEmpty);
  });

  testWidgets('Browse schema folder picks a directory and saves it',
      (tester) async {
    final picker = _FakeFilePicker()..dirPath = r'E:\schemas\picked';
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Second Browse button belongs to the schema row.
    await tester.tap(find.text(t.settings.general.rpfm.browseButton).last);
    await tester.pumpAndSettle();

    expect(picker.getDirectoryCalled, isTrue);
    expect(schemaController.text, r'E:\schemas\picked');
    expect(settings.savedSchema, [r'E:\schemas\picked']);
  });

  testWidgets('Browse schema folder cancelled (null) does not save',
      (tester) async {
    final picker = _FakeFilePicker()..dirPath = null;
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text(t.settings.general.rpfm.browseButton).last);
    await tester.pumpAndSettle();

    expect(picker.getDirectoryCalled, isTrue);
    expect(settings.savedSchema, isEmpty);
  });

  testWidgets('Default schema button resolves the %APPDATA% path and saves it',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text(t.settings.general.rpfm.defaultButton));
    await tester.pump();
    await tester.pumpAndSettle();

    // On the test host APPDATA/USERPROFILE is set, so a default path is
    // resolved, written to the field, saved, and an info toast is shown.
    final expectedSuffix = r'\FrodoWazEre\rpfm\config\schemas';
    expect(schemaController.text, endsWith(expectedSuffix));
    expect(settings.savedSchema.single, endsWith(expectedSuffix));
    expect(
      find.text(t.settings.general.rpfm.toasts.defaultPathSet),
      findsOneWidget,
    );
    await drainToast(tester);
  });
}
