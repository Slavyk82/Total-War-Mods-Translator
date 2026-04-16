// Golden tests for the migrated Glossary list view (Plan 5a · Task 5).
//
// Fixtures exercise both glossary types (universal + game-specific) and
// three target-language pairs with varied entry counts. Relative date
// cells read the [clockProvider] override so rendering stays byte-stable.
// No golden is taken for the editor view — that surface is covered in
// Plan 5b when the entry-detail panel is redone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/app_theme.dart';

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
      _glossary(
        id: 'g1',
        name: 'Warhammer Lore',
        description: 'Shared terminology across every campaign.',
        isGlobal: true,
        targetLanguageId: 'fr',
        entryCount: 128,
        updatedAt: _baseEpoch,
      ),
      _glossary(
        id: 'g2',
        name: 'Three Kingdoms — Names',
        description: 'Faction leaders and unique unit names.',
        gameInstallationId: 'install-1',
        targetLanguageId: 'de',
        entryCount: 42,
        updatedAt: _baseEpoch - 86400 * 3,
      ),
      _glossary(
        id: 'g3',
        name: 'Troy — Heroes',
        gameInstallationId: 'install-2',
        targetLanguageId: 'es',
        entryCount: 0,
        updatedAt: _baseEpoch - 86400 * 30,
      ),
    ];

// Pinned "now" so the "UPDATED" column renders deterministically:
//   g1 → "1 day" (baseEpoch + 1 day)
//   g2 → "4 days"
//   g3 → "1 month"
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
        .add(const Duration(days: 1));

List<Override> _populatedOverrides() => [
      clockProvider.overrideWithValue(() => _pinnedNow),
      glossariesProvider().overrideWith((_) async => _populatedGlossaries()),
      selectedGlossaryProvider.overrideWith(_MockSelectedGlossaryNotifier.new),
    ];

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    List<Override> overrides,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('glossary atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(GlossaryScreen),
      matchesGoldenFile('../goldens/glossary_atelier_populated.png'),
    );
  });

  testWidgets('glossary forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(GlossaryScreen),
      matchesGoldenFile('../goldens/glossary_forge_populated.png'),
    );
  });
}

class _MockSelectedGlossaryNotifier extends SelectedGlossary {
  @override
  Glossary? build() => null;

  @override
  void select(Glossary? glossary) {
    state = glossary;
  }

  @override
  void clear() {
    state = null;
  }
}
