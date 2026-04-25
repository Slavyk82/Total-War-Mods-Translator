// Screen tests for the migrated Steam Publish screen (Plan 5a · Task 4).
//
// These tests exercise the new FilterToolbar + ListRow chrome and the
// Riverpod-backed selection provider introduced in Task 4. The legacy
// FluentScaffold-based tests were dropped when the card list was replaced.
//
// `hasPack` on real [ProjectPublishItem] / [CompilationPublishItem] reads
// `File(...).existsSync()` on the output path, so populated fixtures create
// real temp pack files and clean them up with `addTearDown`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/screens/steam_publish_screen.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_list.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

/// Creates a touched-but-empty pack file in a per-test temp directory so
/// [ProjectPublishItem.hasPack] reports true. The temp directory is removed
/// via [addTearDown].
String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-steam-publish-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup; tests shouldn't fail on a stale temp dir.
    }
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}

ProjectPublishItem _project({
  required String id,
  required String name,
  String? publishedSteamId,
  int? publishedAt,
  int exportedAt = 0,
  bool hasPack = false,
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
            exportedAt: exportedAt,
          )
        : null,
    project: Project(
      id: id,
      name: name,
      gameInstallationId: 'g1',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedAt,
    ),
    languageCodes: const ['en'],
  );
}

List<PublishableItem> _populatedItems() => [
      // Published and up to date.
      _project(
        id: 'p1',
        name: 'Sigmars Heirs',
        publishedSteamId: '111111',
        publishedAt: _baseEpoch,
        exportedAt: _baseEpoch,
        hasPack: true,
      ),
      // Published but outdated (pack newer than publish).
      _project(
        id: 'p2',
        name: 'Warhammer Chaos Dwarves',
        publishedSteamId: '222222',
        publishedAt: _baseEpoch,
        exportedAt: _baseEpoch + 3600,
        hasPack: true,
      ),
      // Pack ready, never published.
      _project(
        id: 'p3',
        name: 'Beastmen Overhaul',
        exportedAt: _baseEpoch - 7200,
        hasPack: true,
      ),
      // No pack yet, never published.
      _project(
        id: 'p4',
        name: 'Norsca Reborn',
      ),
    ];

List<Override> _populatedOverrides({
  List<PublishableItem>? items,
}) {
  final data = items ?? _populatedItems();
  final outdated = data
      .where((e) => e.publishedAt != null && e.exportedAt > e.publishedAt!)
      .length;
  final noPack = data.where((e) => !e.hasPack).length;
  return [
    clockProvider.overrideWithValue(
      () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
          .add(const Duration(days: 30)),
    ),
    publishableItemsProvider.overrideWith((_) async => data),
    filteredPublishableItemsProvider.overrideWithValue(data),
    outdatedPublishableItemsCountProvider.overrideWithValue(outdated),
    noPackPublishableItemsCountProvider.overrideWithValue(noPack),
  ];
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'SteamPublishScreen renders FilterToolbar + SteamPublishList with rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(SteamPublishList), findsOneWidget);
    expect(find.byType(ListRow), findsNWidgets(4));
    expect(find.text('Sigmars Heirs'), findsOneWidget);
    expect(find.text('Warhammer Chaos Dwarves'), findsOneWidget);
    expect(find.text('Beastmen Overhaul'), findsOneWidget);
    expect(find.text('Norsca Reborn'), findsOneWidget);
  });

  testWidgets('SteamPublishScreen surfaces STATE pill group', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('STATE'), findsOneWidget);
    expect(find.byType(FilterPill), findsNWidgets(4));
    expect(find.widgetWithText(FilterPill, 'All'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Outdated'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'No pack'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Compilations'), findsOneWidget);
  });

  testWidgets('SteamPublishScreen Select all populates selection provider',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = _populatedItems();
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(items: items),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SmallTextButton, 'Select all'));
    await tester.pumpAndSettle();

    final selectedRows = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .where((r) => r.selected);
    expect(selectedRows.length, greaterThan(0));
    expect(selectedRows.length, items.length);
  });

  testWidgets('Tapping a ListRow toggles selection on that row only',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sigmars Heirs'));
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .where((r) => r.selected)
        .length;
    expect(selected, 1);

    await tester.tap(find.text('Sigmars Heirs'));
    await tester.pumpAndSettle();

    final afterToggle = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .where((r) => r.selected)
        .length;
    expect(afterToggle, 0);
  });

  testWidgets('Empty state shows when no publishable items exist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(items: const []),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNothing);
    expect(find.text('No projects or compilations yet'), findsOneWidget);
  });

  testWidgets('Error state surfaces retry button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        publishableItemsProvider.overrideWith((_) async {
          throw Exception('boom');
        }),
        filteredPublishableItemsProvider
            .overrideWithValue(const <PublishableItem>[]),
        outdatedPublishableItemsCountProvider.overrideWithValue(0),
        noPackPublishableItemsCountProvider.overrideWithValue(0),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load publishable items'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  test('Selection provider toggles state via widget controller flow', () {
    // Sanity-check the StateProvider contract used by the screen — tests
    // above exercise the widget-level interaction, this one covers the raw
    // provider plumbing without any Flutter surface area.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(steamPublishSelectionProvider), isEmpty);

    container.read(steamPublishSelectionProvider.notifier).state = {'p1'};
    expect(container.read(steamPublishSelectionProvider), {'p1'});
  });
}
