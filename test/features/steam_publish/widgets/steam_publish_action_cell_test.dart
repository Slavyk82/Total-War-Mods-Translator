// Widget tests for [SteamActionCell].
//
// The companion file `steam_publish_action_cell_state_test.dart` locks the
// four *rendering* modes (A0/A1/B/C). This file drives the cell's interactive
// effects — the parts that were previously uncovered:
//
//   * `_openWorkshop`  — Open-in-Steam button → url_launcher.
//   * `_openLauncher`  — game-launcher icon (state B) → selected-game resolve
//                        + url_launcher, plus the "Steam not found" warning.
//   * Update button (state C) → stages the item + navigates to the single
//     publish route.
//   * `_handleGeneratePack` — compilation → navigates to the pack route;
//     project with no languages → warning toast; single-language project →
//     drives `_generatePackForProject`; multi-language project → opens the
//     [PackLanguageDialog].
//   * `_generatePackForProject` — progress UI (`_buildGenerateProgress`),
//     `_humanizeStep`, success / failure / exception toast branches and the
//     `publishableItemsProvider` invalidation.
//
// Fixtures use real temp pack files because [ProjectPublishItem.hasPack] reads
// `File(outputPath).existsSync()` directly.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/pack_language_dialog.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_action_cell.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _MockOrchestrator extends Mock implements ExportOrchestratorService {}

/// Test double for [SelectedGame] returning a fixed value without settings.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _wh3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/games/wh3',
);

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Creates an empty pack file in a per-test temp directory so
/// [ProjectPublishItem.hasPack] / [CompilationPublishItem.hasPack] report true.
String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-action-cell-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}

ProjectPublishItem _project({
  String id = 'p1',
  String name = 'Sigmars Heirs',
  String? publishedSteamId,
  bool hasPack = false,
  List<String> languageCodes = const ['en'],
}) {
  final outputPath = hasPack ? _createTempPack(id) : '';
  return ProjectPublishItem(
    export: hasPack
        ? ExportHistory(
            id: 'e-$id',
            projectId: id,
            languages: '["en"]',
            format: ExportFormat.pack,
            validatedOnly: false,
            outputPath: outputPath,
            entryCount: 10,
            exportedAt: 1_700_000_000,
          )
        : null,
    project: Project(
      id: id,
      name: name,
      gameInstallationId: 'g1',
      createdAt: 0,
      updatedAt: 0,
    ),
    languageCodes: languageCodes,
    resolvedPublishedSteamId: publishedSteamId,
    resolvedPublishedAt: publishedSteamId != null ? 1_700_000_000 : null,
  );
}

CompilationPublishItem _compilation({
  String id = 'c1',
  String name = 'My Compilation',
  String? publishedSteamId,
}) {
  return CompilationPublishItem(
    compilation: Compilation(
      id: id,
      name: name,
      prefix: 'pre_',
      packName: 'pack',
      gameInstallationId: 'g1',
      languageId: null,
      lastOutputPath: null,
      lastGeneratedAt: null,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
      createdAt: 0,
      updatedAt: 0,
    ),
    projectCount: 2,
  );
}

// ---------------------------------------------------------------------------
// Test app harness
// ---------------------------------------------------------------------------

const _packRouteMarker = 'PACK-COMPILATION-LIST';
const _singlePublishMarker = 'SINGLE-PUBLISH-SCREEN';

/// Wraps [child] in a `MaterialApp.router` whose routes mirror the two
/// destinations the cell navigates to, so `context.goPackCompilation()` and
/// `context.goWorkshopPublishSingle()` resolve and we can assert by marker.
Widget _routedApp(
  Widget child, {
  required List<Override> overrides,
}) {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) =>
            Scaffold(body: SizedBox(width: 1200, height: 400, child: child)),
      ),
      GoRoute(
        path: '/publishing/pack',
        builder: (_, _) => const Scaffold(body: Text(_packRouteMarker)),
      ),
      GoRoute(
        path: '/publishing/steam/single',
        builder: (_, _) => const Scaffold(body: Text(_singlePublishMarker)),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final urlCalls = <MethodCall>[];
  late bool canLaunchResult;

  setUpAll(() {
    registerFallbackValue(<String>['en']);
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    urlCalls.clear();
    canLaunchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
      urlCalls.add(call);
      if (call.method == 'canLaunch') return canLaunchResult;
      if (call.method == 'launch') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, null);
  });

  // -------------------------------------------------------------------------
  group('Open in Steam Workshop', () {
    testWidgets('A1: tapping Open in Steam launches the workshop URL',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project(publishedSteamId: '123456')),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
      ));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SmallTextButton, 'Open in Steam Workshop'),
      );
      await tester.pump();

      final launch = urlCalls.firstWhere((c) => c.method == 'launch');
      final url = (launch.arguments as Map)['url'] as String;
      expect(
        url,
        'https://steamcommunity.com/sharedfiles/filedetails/?id=123456',
      );
    });

    testWidgets('C: pack + id renders Update and Open-in-Steam, launches URL',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(
          item: _project(hasPack: true, publishedSteamId: '987654'),
        ),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open in Steam Workshop'));
      await tester.pump();

      final launch = urlCalls.firstWhere((c) => c.method == 'launch');
      final url = (launch.arguments as Map)['url'] as String;
      expect(url, contains('id=987654'));
    });
  });

  // -------------------------------------------------------------------------
  group('Open game launcher (state B)', () {
    testWidgets('resolves selected game and launches steam://run URI',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          selectedGameProvider.overrideWith(() => _FakeSelectedGame(_wh3)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open the in-game launcher'));
      await tester.pumpAndSettle();

      // wh3 steam app id is 1142710.
      final launch = urlCalls.firstWhere((c) => c.method == 'launch');
      final url = (launch.arguments as Map)['url'] as String;
      expect(url, 'steam://run/1142710');
    });

    testWidgets('no selected game shows "Steam not found" warning toast',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open the in-game launcher'));
      await tester.pump(); // resolve future + show toast

      expect(
        find.text('Could not open the Steam client. Is Steam installed?'),
        findsOneWidget,
      );
      // No URL launch attempted when the app id could not be resolved.
      expect(urlCalls.where((c) => c.method == 'launch'), isEmpty);

      // Drain the toast's 4s auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('launcher unavailable (canLaunch=false) warns', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      canLaunchResult = false;

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          selectedGameProvider.overrideWith(() => _FakeSelectedGame(_wh3)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open the in-game launcher'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Could not open the Steam client. Is Steam installed?'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  // -------------------------------------------------------------------------
  group('Update button (state C) navigation', () {
    testWidgets('stages the item and navigates to the single publish route',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final item = _project(hasPack: true, publishedSteamId: '555');
      final container = ProviderContainer(overrides: const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _routedApp(
            SteamActionCell(item: item),
            overrides: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(singlePublishStagingProvider), isNull);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      // Staged + navigated.
      expect(container.read(singlePublishStagingProvider), same(item));
      expect(find.text(_singlePublishMarker), findsOneWidget);
    });

    testWidgets('disabled Update (state B) does not navigate', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_routedApp(
        SteamActionCell(item: _project(hasPack: true)),
        overrides: [
          selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      // Still on the host page — disabled tap is a no-op.
      expect(find.text(_singlePublishMarker), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('Generate pack — routing & guards', () {
    testWidgets('compilation navigates to the pack compilation route',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_routedApp(
        SteamActionCell(item: _compilation()),
        overrides: const [],
      ));
      await tester.pumpAndSettle();

      // Compilation renders "Open compilation" rather than "Generate pack".
      expect(find.text('Open compilation'), findsOneWidget);

      await tester.tap(find.text('Open compilation'));
      await tester.pumpAndSettle();

      expect(find.text(_packRouteMarker), findsOneWidget);
    });

    testWidgets('project with no languages shows a warning toast',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: SteamActionCell(
            item: _project(languageCodes: const []),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pump();

      expect(
        find.text('No languages configured for this project.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'multi-language project opens the PackLanguageDialog; cancel aborts',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orchestrator = _MockOrchestrator();

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: SteamActionCell(
            item: _project(languageCodes: const ['en', 'fr']),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          exportOrchestratorServiceProvider.overrideWithValue(orchestrator),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pumpAndSettle();

      expect(find.byType(PackLanguageDialog), findsOneWidget);

      // Cancel — generation must not be triggered.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(PackLanguageDialog), findsNothing);
      verifyNever(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            onProgress: any(named: 'onProgress'),
          ));
    });
  });

  // -------------------------------------------------------------------------
  group('Generate pack — orchestration', () {
    testWidgets('single language drives export and shows success toast',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orchestrator = _MockOrchestrator();
      final gate = Completer<void>();
      when(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((invocation) async {
        // Exercise the progress callback so `_buildGenerateProgress` and
        // `_humanizeStep` run for several known + unknown steps.
        final onProgress = invocation.namedArguments[#onProgress]
            as ExportProgressCallback?;
        onProgress?.call('preparingData', 0.1);
        onProgress?.call('generatingLocFiles', 0.3, currentLanguage: 'en');
        onProgress?.call('creatingPack', 0.5, currentLanguage: 'en');
        onProgress?.call('generatingImage', 0.7);
        onProgress?.call('finalizing', 0.85);
        onProgress?.call('completed', 0.95);
        onProgress?.call('unknownStep', 0.99);
        // Block until the test releases the gate so the progress UI is
        // observable mid-flight.
        await gate.future;
        return const Ok<ExportResult, FileServiceException>(
          ExportResult(
            outputPath: 'out.pack',
            entryCount: 42,
            fileSize: 1234,
            languageCodes: ['en'],
          ),
        );
      });

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          exportOrchestratorServiceProvider.overrideWithValue(orchestrator),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pump(); // setState -> progress UI

      // Progress UI is shown while generating (export still gated).
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Release the export and let it complete.
      gate.complete();
      await tester.pumpAndSettle();

      // Success toast surfaced with the entry count.
      expect(find.text('Pack generated: 42 entries'), findsOneWidget);
      verify(() => orchestrator.exportToPack(
            projectId: 'p1',
            languageCodes: ['en'],
            outputPath: '',
            validatedOnly: false,
            onProgress: any(named: 'onProgress'),
          )).called(1);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('export failure shows error toast', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orchestrator = _MockOrchestrator();
      when(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Err<ExportResult, FileServiceException>(
          FileServiceException('disk full'),
        ),
      );

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          exportOrchestratorServiceProvider.overrideWithValue(orchestrator),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failed to generate pack:'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('export throwing shows error toast and resets state',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orchestrator = _MockOrchestrator();
      when(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            onProgress: any(named: 'onProgress'),
          )).thenThrow(StateError('boom'));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          exportOrchestratorServiceProvider.overrideWithValue(orchestrator),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error generating pack:'), findsOneWidget);
      // After the failure the cell returns to the Generate state.
      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('multi-language dialog confirm drives export', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orchestrator = _MockOrchestrator();
      when(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Ok<ExportResult, FileServiceException>(
          ExportResult(
            outputPath: 'out.pack',
            entryCount: 3,
            fileSize: 10,
            languageCodes: ['en', 'fr'],
          ),
        ),
      );

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: SteamActionCell(
            item: _project(languageCodes: const ['en', 'fr']),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
        overrides: [
          exportOrchestratorServiceProvider.overrideWithValue(orchestrator),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate pack'));
      await tester.pumpAndSettle();
      expect(find.byType(PackLanguageDialog), findsOneWidget);

      // Confirm with both languages preselected.
      await tester.tap(find.widgetWithText(SmallTextButton, 'Generate'));
      await tester.pumpAndSettle();

      expect(find.text('Pack generated: 3 entries'), findsOneWidget);
      verify(() => orchestrator.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: ['en', 'fr'],
            outputPath: '',
            validatedOnly: false,
            onProgress: any(named: 'onProgress'),
          )).called(1);

      await tester.pump(const Duration(seconds: 5));
    });
  });

  // -------------------------------------------------------------------------
  group('rendering signatures', () {
    testWidgets('A0: Generate pack only when never published', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project()),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Generate pack'), findsOneWidget);
      expect(
        find.widgetWithText(SmallTextButton, 'Open in Steam Workshop'),
        findsNothing,
      );
    });

    testWidgets('compilation generate button uses the open icon',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _compilation()),
        theme: AppTheme.atelierDarkTheme,
        screenSize: const Size(1200, 1600),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Open compilation'), findsOneWidget);
      expect(find.byIcon(FluentIcons.open_24_regular), findsWidgets);
    });
  });
}
