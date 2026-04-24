// Screen tests for the migrated Mods screen (Plan 5a · Task 3).
//
// The pre-existing tests that asserted a FluentScaffold root and the
// SfDataGrid-based list were replaced when the screen moved to the
// FilterToolbar + ListRow archetype. These tests exercise the new chrome,
// row archetype and filter-pill interactions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/screens/mods_screen.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

DetectedMod _mod(
  String id,
  String name, {
  int? timeUpdated,
  int? localFileLastModified,
  bool isAlreadyImported = false,
  bool isHidden = false,
  int subscribers = 0,
  ModUpdateAnalysis? analysis,
}) =>
    DetectedMod(
      workshopId: id,
      name: name,
      packFilePath: '/tmp/$id.pack',
      imageUrl: null,
      metadata: subscribers > 0
          ? ProjectMetadata(modSubscribers: subscribers)
          : null,
      isAlreadyImported: isAlreadyImported,
      isHidden: isHidden,
      timeUpdated: timeUpdated,
      localFileLastModified: localFileLastModified,
      updateAnalysis: analysis,
    );

const _baseEpoch = 1_700_000_000;

// Base overrides shared by every test. Populates all count providers and
// keeps the scan log stream empty so refresh/loading paths never block.
List<Override> _baseOverrides({
  List<DetectedMod> mods = const [],
  Object? error,
}) =>
    [
      scanLogStreamProvider.overrideWithValue(
        const Stream<ScanLogMessage>.empty(),
      ),
      filteredModsProvider.overrideWith((_) => mods),
      modsIsLoadingProvider.overrideWith((_) => false),
      modsErrorProvider.overrideWith((_) => error),
      totalModsCountProvider.overrideWith((_) async => mods.length),
      notImportedModsCountProvider.overrideWith(
        (_) async => mods.where((m) => !m.isAlreadyImported).length,
      ),
      needsUpdateModsCountProvider.overrideWith((_) async => 0),
      hiddenModsCountProvider.overrideWith((_) async => 0),
      projectsWithPendingChangesCountProvider.overrideWith((_) async => 0),
    ];

List<DetectedMod> _populatedMods() => [
      _mod(
        '1001',
        'Sigmars Heirs',
        timeUpdated: _baseEpoch,
        localFileLastModified: _baseEpoch - 3600,
        isAlreadyImported: false,
        subscribers: 12345,
      ),
      _mod(
        '1002',
        'Warhammer Chaos Dwarves',
        timeUpdated: _baseEpoch,
        localFileLastModified: _baseEpoch,
        isAlreadyImported: true,
        subscribers: 6789,
      ),
      // Outdated — localFileLastModified < timeUpdated triggers needsDownload.
      _mod(
        '1003',
        'Beastmen Overhaul',
        timeUpdated: _baseEpoch + 1000,
        localFileLastModified: _baseEpoch,
        isAlreadyImported: true,
      ),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('ModsScreen renders FilterToolbar + ModsList with rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ModsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _baseOverrides(mods: _populatedMods()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(ListRow), findsNWidgets(3));
    expect(find.text('Sigmars Heirs'), findsOneWidget);
    expect(find.text('Warhammer Chaos Dwarves'), findsOneWidget);
    expect(find.text('Beastmen Overhaul'), findsOneWidget);
  });

  testWidgets('ModsScreen surfaces STATE pill group', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ModsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _baseOverrides(mods: _populatedMods()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('STATE'), findsOneWidget);
    expect(find.byType(FilterPill), findsNWidgets(4));
    expect(find.widgetWithText(FilterPill, 'All'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Not imported'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Needs update'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Hidden'), findsOneWidget);
  });

  testWidgets('Tapping Not imported pill switches ModsFilter', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Capture filter changes via a dedicated notifier spy so we can assert the
    // pill tap routes through ModsFilterState.setFilter without relying on
    // downstream re-filter behaviour (the filteredMods override is static).
    final notifier = _SpyModsFilterState();
    await tester.pumpWidget(createThemedTestableWidget(
      const ModsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        ..._baseOverrides(mods: _populatedMods()),
        modsFilterStateProvider.overrideWith(() => notifier),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterPill, 'Not imported'));
    await tester.pumpAndSettle();

    expect(notifier.recorded, contains(ModsFilter.notImported));
  });

  testWidgets('ModsScreen empty state renders when no mods', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ModsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _baseOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNothing);
    expect(find.text('No mods found'), findsOneWidget);
  });

  testWidgets('ModsScreen error state renders retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ModsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _baseOverrides(error: 'boom'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load mods'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
      'Tapping pending-projects banner deep-links to Projects with needs-update filter',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Wire a minimal router that pairs the real Mods screen with a dummy
    // Projects screen so we can observe the URL the banner tap navigates to.
    // The dummy Projects route echoes the `filter` query parameter so the
    // assertion can verify both the path and the filter token in one marker.
    final router = GoRouter(
      initialLocation: AppRoutes.mods,
      routes: [
        GoRoute(
          path: AppRoutes.mods,
          builder: (_, _) => const ModsScreen(),
        ),
        GoRoute(
          path: AppRoutes.projects,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'projects:filter=${state.uri.queryParameters['filter']}',
              ),
            ),
          ),
        ),
      ],
    );

    final mods = _populatedMods();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        scanLogStreamProvider.overrideWithValue(
          const Stream<ScanLogMessage>.empty(),
        ),
        filteredModsProvider.overrideWith((_) => mods),
        modsIsLoadingProvider.overrideWith((_) => false),
        modsErrorProvider.overrideWith((_) => null),
        totalModsCountProvider.overrideWith((_) async => mods.length),
        notImportedModsCountProvider.overrideWith(
          (_) async => mods.where((m) => !m.isAlreadyImported).length,
        ),
        needsUpdateModsCountProvider.overrideWith((_) async => 0),
        hiddenModsCountProvider.overrideWith((_) async => 0),
        // Force the banner to render by advertising a pending count.
        projectsWithPendingChangesCountProvider.overrideWith((_) async => 1),
      ],
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // Banner is present (count == 1 → label has no plural "s"). Several other
    // StatusPills render per mod row, so match on the banner's unique label.
    final banner = find.widgetWithText(StatusPill, '1 project pending');
    expect(banner, findsOneWidget);

    await tester.tap(banner);
    await tester.pumpAndSettle();

    // Dummy Projects screen now shown, echoing the filter token from the URL.
    expect(find.text('projects:filter=needs-update'), findsOneWidget);
  });
}

/// Notifier spy that records every filter set via [setFilter]. Lets tests
/// assert a pill tap triggers the correct [ModsFilter] without relying on
/// downstream re-compute of [filteredModsProvider].
class _SpyModsFilterState extends ModsFilterState {
  final List<ModsFilter> recorded = [];

  @override
  ModsFilter build() => ModsFilter.all;

  @override
  void setFilter(ModsFilter filter) {
    recorded.add(filter);
    state = filter;
  }
}
