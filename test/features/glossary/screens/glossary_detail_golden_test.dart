// Golden tests for the migrated Glossary detail view (Plan 5b · Task 8).
//
// Selecting a glossary swaps the list view out for the §7.2 detail
// archetype: crumb toolbar + DetailMetaBanner + DetailOverviewLayout
// (main grid, right stats rail). The golden pins the clock so the
// `updated <relative>` subtitle stays byte-stable and overrides the
// statistics provider to surface the full Overview/Usage/Quality rails.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const int _epoch = 1_700_000_000;

Glossary _glossary() => const Glossary(
      id: 'g-1',
      name: 'Warhammer III · FR glossary',
      description:
          'House-brand terminology for Warhammer III French translations.',
      isGlobal: false,
      gameInstallationId: 'install-1',
      targetLanguageId: 'fr',
      entryCount: 234,
      createdAt: _epoch,
      updatedAt: _epoch,
    );

const GlossaryStatistics _stats = GlossaryStatistics(
  totalEntries: 234,
  entriesByLanguagePair: {'en->fr': 234},
  usedInTranslations: 180,
  unusedEntries: 54,
  usageRate: 0.769,
  consistencyScore: 0.95,
  duplicatesDetected: 3,
  missingTranslations: 12,
  forbiddenTerms: 0,
  caseSensitiveTerms: 5,
);

List<GlossaryEntry> _entries() => const [
      GlossaryEntry(
        id: 'e-1',
        glossaryId: 'g-1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Karl Franz',
        targetTerm: 'Karl Franz',
        caseSensitive: true,
        notes: 'Emperor of the Empire; keep untranslated.',
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      GlossaryEntry(
        id: 'e-2',
        glossaryId: 'g-1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Greenskins',
        targetTerm: 'Peaux-Vertes',
        caseSensitive: false,
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      GlossaryEntry(
        id: 'e-3',
        glossaryId: 'g-1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Waaagh!',
        targetTerm: 'Waaagh!',
        caseSensitive: true,
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
    ];

// Pin "now" so the `updated <relative>` subtitle renders as "1 day" —
// keeping the atelier / forge goldens byte-stable across CI runs.
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_epoch * 1000)
        .add(const Duration(days: 1));

List<Override> _overrides() => [
      clockProvider.overrideWithValue(() => _pinnedNow),
      glossariesProvider().overrideWith((_) async => [_glossary()]),
      selectedGlossaryProvider.overrideWith(_PreselectedGlossaryNotifier.new),
      glossaryStatisticsProvider('g-1').overrideWith((_) async => _stats),
      // The inner GlossaryDataGrid reads the entries family — override it so
      // the grid body renders real rows instead of a service-locator error.
      glossaryEntriesProvider(glossaryId: 'g-1')
          .overrideWith((_) async => _entries()),
    ];

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('glossary detail atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(GlossaryScreen),
      matchesGoldenFile('../goldens/glossary_detail_atelier.png'),
    );
  });

  testWidgets('glossary detail forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(GlossaryScreen),
      matchesGoldenFile('../goldens/glossary_detail_forge.png'),
    );
  });
}

/// Test notifier that boots with a preselected glossary so the detail
/// branch renders without having to tap a row first. `SelectedGlossary`
/// is the Riverpod 3 generated class from `@riverpod class SelectedGlossary`;
/// `selectedGlossaryProvider.overrideWith(_PreselectedGlossaryNotifier.new)`
/// returns this subclass which sets `state` in `build`.
class _PreselectedGlossaryNotifier extends SelectedGlossary {
  @override
  Glossary? build() => _glossary();
}
