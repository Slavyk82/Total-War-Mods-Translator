// Widget coverage tests for
// lib/features/settings/widgets/general/game_installations_section.dart.
//
// The section lists every configured Total War game in a [FluentExpander] with
// a per-game path field plus Detect / Browse actions, and a top-level
// "Auto-Detect All Games" button. These tests render the section (configured +
// unconfigured games, detecting state), exercise the directory picker (faked
// FilePicker.platform), per-game detection (found / not-found / error), the
// detect-all flow (some found / none found / error), the debounced text-field
// save, and the immediate browse/detect save -> updateGamePath call.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:twmt/features/settings/models/game_display_info.dart';
import 'package:twmt/features/settings/widgets/general/game_installations_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/steam/steam_detection_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _MockSteamDetectionService extends Mock
    implements SteamDetectionService {}

/// Records [updateGamePath] calls instead of writing to settings / DB.
class _FakeGeneralSettings extends GeneralSettings {
  final List<({String code, String path})> saved = [];
  bool throwOnSave = false;

  @override
  Future<Map<String, String>> build() async => {};

  @override
  Future<void> updateGamePath(String gameCode, String path) async {
    if (throwOnSave) {
      throw StateError('save failed');
    }
    saved.add((code: gameCode, path: path));
  }
}

/// Fake [FilePicker] installed as `FilePicker.platform`. Returns [dirPath]
/// from `getDirectoryPath`, sidestepping the real native picker.
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  String? dirPath;
  bool getDirectoryCalled = false;

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
  setUpAll(() {
    registerFallbackValue('');
  });

  late _MockSteamDetectionService detection;
  late _FakeGeneralSettings settings;
  late Map<String, TextEditingController> controllers;

  // wh3 starts configured (non-empty path -> expander auto-expands), wh starts
  // unconfigured (empty path -> collapsed). The FluentExpander always builds
  // its child, so both path fields are present in the tree regardless.
  final games = const [
    GameDisplayInfo(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      settingsKey: 'game_path_wh3',
    ),
    GameDisplayInfo(
      code: 'wh',
      name: 'Total War: WARHAMMER',
      settingsKey: 'game_path_wh',
    ),
  ];

  setUp(() {
    detection = _MockSteamDetectionService();
    settings = _FakeGeneralSettings();
    controllers = {
      'wh3': TextEditingController(text: r'C:\Games\wh3'),
      'wh': TextEditingController(text: ''),
    };
  });

  tearDown(() {
    for (final c in controllers.values) {
      c.dispose();
    }
  });

  Widget host() {
    return ProviderScope(
      overrides: [
        steamDetectionServiceProvider.overrideWithValue(detection),
        generalSettingsProvider.overrideWith(() => settings),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 1100,
              child: GameInstallationsSection(
                gamePathControllers: controllers,
                games: games,
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

  testWidgets('renders header, detect-all button and a field per game',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    expect(
      find.text(t.settings.general.gameInstallations.sectionTitle),
      findsOneWidget,
    );
    expect(
      find.text(t.settings.general.gameInstallations.detectAllButton),
      findsOneWidget,
    );
    // Two game expanders -> two path fields + per-row detect/browse buttons.
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(
      find.text(t.settings.general.gameInstallations.detectButton),
      findsNWidgets(2),
    );
    expect(
      find.text(t.settings.general.gameInstallations.browseButton),
      findsNWidgets(2),
    );
    // Configured game's path is shown.
    expect(find.text(r'C:\Games\wh3'), findsOneWidget);
    // Game labels strip the "Total War: " prefix.
    expect(find.text('WARHAMMER III'), findsOneWidget);
  });

  testWidgets('typing in a path field debounce-saves via updateGamePath',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // wh field is the second one (empty).
    await tester.enterText(
      find.byType(TextFormField).last,
      r'D:\new\wh',
    );
    // Debounce is 600ms; advance past it.
    await tester.pump(const Duration(milliseconds: 700));

    expect(settings.saved, [(code: 'wh', path: r'D:\new\wh')]);
  });

  testWidgets('pending debounce timer is cancelled on dispose', (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Start a debounce timer (600ms) but do NOT let it fire.
    await tester.enterText(find.byType(TextFormField).last, r'X:\partial');
    await tester.pump(const Duration(milliseconds: 100));

    // Replace the widget tree so the section is disposed with a pending timer,
    // exercising the dispose() timer-cancel loop. (No save should happen.)
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(settings.saved, isEmpty);
  });

  testWidgets('browse picks a directory and immediately saves it',
      (tester) async {
    final picker = _FakeFilePicker()..dirPath = r'E:\steam\wh3';
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Tap the wh3 row's Browse button (first one; its expander is expanded
    // because wh3 starts configured, so the button is hit-testable).
    await tester.tap(
      find.text(t.settings.general.gameInstallations.browseButton).first,
    );
    await tester.pumpAndSettle();

    expect(picker.getDirectoryCalled, isTrue);
    expect(controllers['wh3']!.text, r'E:\steam\wh3');
    expect(settings.saved, [(code: 'wh3', path: r'E:\steam\wh3')]);
  });

  testWidgets('browse cancelled (null) does not save', (tester) async {
    final picker = _FakeFilePicker()..dirPath = null;
    FilePicker.platform = picker;

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.browseButton).first,
    );
    await tester.pumpAndSettle();

    expect(picker.getDirectoryCalled, isTrue);
    expect(settings.saved, isEmpty);
  });

  testWidgets('per-game detect: found path saves and shows success toast',
      (tester) async {
    when(() => detection.detectGame('wh3'))
        .thenAnswer((_) async => const Ok(r'F:\found\wh3'));

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectButton).first,
    );
    await tester.pump();
    await tester.pump();

    verify(() => detection.detectGame('wh3')).called(1);
    expect(controllers['wh3']!.text, r'F:\found\wh3');
    expect(settings.saved, [(code: 'wh3', path: r'F:\found\wh3')]);
    expect(
      find.text(t.settings.general.gameInstallations.toasts
          .gameFound(game: 'WARHAMMER III')),
      findsOneWidget,
    );
    // Drain the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('per-game detect: not found shows warning toast and no save',
      (tester) async {
    when(() => detection.detectGame('wh3'))
        .thenAnswer((_) async => const Ok(null));

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectButton).first,
    );
    await tester.pump();
    await tester.pump();

    expect(settings.saved, isEmpty);
    expect(
      find.text(t.settings.general.gameInstallations.toasts
          .gameNotFound(game: 'WARHAMMER III')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('per-game detect: error shows error toast', (tester) async {
    when(() => detection.detectGame('wh3')).thenAnswer(
      (_) async => const Err(
        SteamServiceException('boom', code: 'DETECTION_ERROR'),
      ),
    );

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectButton).first,
    );
    await tester.pump();
    await tester.pump();

    expect(settings.saved, isEmpty);
    expect(
      find.text(t.settings.general.gameInstallations.toasts
          .detectionFailed(error: 'boom')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('detect-all: found games save and show success toast',
      (tester) async {
    when(() => detection.detectAllGames()).thenAnswer(
      (_) async => const Ok({'wh3': r'A:\wh3', 'wh': r'B:\wh'}),
    );

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectAllButton),
    );
    await tester.pump();
    await tester.pump();

    verify(() => detection.detectAllGames()).called(1);
    expect(controllers['wh3']!.text, r'A:\wh3');
    expect(controllers['wh']!.text, r'B:\wh');
    expect(settings.saved.length, 2);
    expect(
      find.text(
        t.settings.general.gameInstallations.toasts.allFound(count: 2),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('detect-all: none found shows warning toast', (tester) async {
    when(() => detection.detectAllGames())
        .thenAnswer((_) async => const Ok({}));

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectAllButton),
    );
    await tester.pump();
    await tester.pump();

    expect(settings.saved, isEmpty);
    expect(
      find.text(t.settings.general.gameInstallations.toasts.noneFound),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('detect-all: error shows error toast', (tester) async {
    when(() => detection.detectAllGames()).thenAnswer(
      (_) async => const Err(
        SteamServiceException('kaboom', code: 'DETECTION_ERROR'),
      ),
    );

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectAllButton),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(t.settings.general.gameInstallations.toasts
          .detectionFailed(error: 'kaboom')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('save failure surfaces an error toast', (tester) async {
    settings.throwOnSave = true;
    when(() => detection.detectGame('wh3'))
        .thenAnswer((_) async => const Ok(r'F:\found\wh3'));

    await setSurface(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(
      find.text(t.settings.general.gameInstallations.detectButton).first,
    );
    await tester.pump();
    await tester.pump();

    // updateGamePath threw -> a save-error toast is shown.
    expect(
      find.textContaining('Error saving game path'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
