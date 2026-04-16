// Screen tests for the migrated Glossary list view (Plan 5a · Task 5).
//
// The legacy GlossaryListHeader + card layout was dropped; the list view
// now renders a FilterToolbar + tokenised SfDataGrid. These tests exercise
// the new chrome and the editor-view switch triggered by tapping a row.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/features/glossary/widgets/glossary_list.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

Glossary _glossary({
  required String id,
  required String name,
  String? description,
  bool isGlobal = false,
  String? gameInstallationId,
  String? targetLanguageId,
  int entryCount = 0,
  int? updatedAt,
}) =>
    Glossary(
      id: id,
      name: name,
      description: description,
      isGlobal: isGlobal,
      gameInstallationId: gameInstallationId,
      targetLanguageId: targetLanguageId,
      entryCount: entryCount,
      createdAt: _baseEpoch,
      updatedAt: updatedAt ?? _baseEpoch,
    );

List<Glossary> _populatedGlossaries() => [
      // Universal glossary (no game scoping).
      _glossary(
        id: 'g1',
        name: 'Warhammer Lore',
        description: 'Shared terminology across every campaign.',
        isGlobal: true,
        targetLanguageId: 'fr',
        entryCount: 128,
        updatedAt: _baseEpoch,
      ),
      // Game-specific glossary, German target.
      _glossary(
        id: 'g2',
        name: 'Three Kingdoms — Names',
        description: 'Faction leaders and unique unit names.',
        gameInstallationId: 'install-1',
        targetLanguageId: 'de',
        entryCount: 42,
        updatedAt: _baseEpoch - 86400 * 3, // 3 days before baseEpoch
      ),
      // Second game-specific glossary, Spanish target — empty.
      _glossary(
        id: 'g3',
        name: 'Troy — Heroes',
        gameInstallationId: 'install-2',
        targetLanguageId: 'es',
        entryCount: 0,
        updatedAt: _baseEpoch - 86400 * 30, // 30 days before baseEpoch
      ),
    ];

List<Override> _populatedOverrides({List<Glossary>? glossaries}) {
  final data = glossaries ?? _populatedGlossaries();
  return [
    // Pin the clock to the fixture's baseEpoch + 1 day so relative dates
    // render deterministically ("1 day", "4 days", "1 month").
    clockProvider.overrideWithValue(
      () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
          .add(const Duration(days: 1)),
    ),
    glossariesProvider().overrideWith((_) async => data),
    selectedGlossaryProvider.overrideWith(_MockSelectedGlossaryNotifier.new),
  ];
}

void main() {
  setUp(() async {
    // The screen reads gameInstallationRepositoryProvider in initState, which
    // resolves via ServiceLocator — setupMockServices registers a mock that
    // returns an empty list so the async init completes without throwing.
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets('GlossaryScreen list view uses FilterToolbar + SfDataGrid',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(GlossaryList), findsOneWidget);
    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.text('Warhammer Lore'), findsOneWidget);
    expect(find.text('Three Kingdoms — Names'), findsOneWidget);
    expect(find.text('Troy — Heroes'), findsOneWidget);
  });

  testWidgets('Tapping a glossary row swaps in the editor view',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = _MockSelectedGlossaryNotifier();
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
              .add(const Duration(days: 1)),
        ),
        glossariesProvider().overrideWith((_) async => _populatedGlossaries()),
        selectedGlossaryProvider.overrideWith(() => notifier),
      ],
    ));
    await tester.pumpAndSettle();

    // List view visible.
    expect(find.byType(GlossaryList), findsOneWidget);

    // Tap a row cell — the grid's onCellTap switches the selected glossary
    // via the notifier which triggers the editor view on rebuild.
    await tester.tap(find.text('Warhammer Lore'));
    await tester.pump();

    expect(notifier.selected?.id, 'g1');
  });

  testWidgets('Empty glossary list renders the empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(glossaries: const <Glossary>[]),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsNothing);
    expect(find.text('No glossaries yet'), findsOneWidget);
  });

  testWidgets('List search field filters visible glossaries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Warhammer Lore'), findsOneWidget);
    expect(find.text('Troy — Heroes'), findsOneWidget);

    // Type "troy" into the shared ListSearchField — in-memory filtering
    // should narrow the grid to the single matching glossary.
    await tester.enterText(find.byType(ListSearchField), 'troy');
    await tester.pumpAndSettle();

    expect(find.text('Warhammer Lore'), findsNothing);
    expect(find.text('Troy — Heroes'), findsOneWidget);
  });

  testWidgets('Search with no matches surfaces the no-matches state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(ListSearchField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsNothing);
    expect(
      find.text('No glossaries match the current search'),
      findsOneWidget,
    );
  });

  testWidgets('Error state renders a tokenised error block', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        glossariesProvider().overrideWith((_) async => throw Exception('boom')),
        selectedGlossaryProvider.overrideWith(_MockSelectedGlossaryNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const SizedBox(
          width: 1920,
          height: 1080,
          child: GlossaryScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Error loading glossaries'), findsOneWidget);
  });
}

/// Test notifier for [selectedGlossaryProvider] that captures the currently
/// selected glossary so assertions can verify row-tap routing without
/// relying on the editor view's downstream widgets.
class _MockSelectedGlossaryNotifier extends SelectedGlossary {
  Glossary? selected;

  @override
  Glossary? build() => selected;

  @override
  void select(Glossary? glossary) {
    selected = glossary;
    state = glossary;
  }

  @override
  void clear() {
    selected = null;
    state = null;
  }
}
