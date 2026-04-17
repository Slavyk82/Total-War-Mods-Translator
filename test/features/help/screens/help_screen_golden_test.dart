// Golden tests for the retokenised Help screen (Plan 5d · Task 4).
//
// The HelpScreen drops FluentScaffold in favour of a Material + Column
// skeleton styled entirely through `context.tokens`. These goldens lock in
// the token-driven look across both Atelier and Forge dark themes and make
// sure the header / TOC sidebar / section content render the populated
// branch without surfacing the CircularProgressIndicator.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/help/models/help_section.dart';
import 'package:twmt/features/help/providers/help_providers.dart';
import 'package:twmt/features/help/screens/help_screen.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

List<HelpSection> _sections() => const [
      HelpSection(
        title: 'Getting started',
        anchor: 'getting-started',
        content:
            '## Getting started\n\nWelcome to the **TWMT** translator. Use '
            'the Table of Contents to jump between documentation sections.\n\n'
            '- Import a mod\n- Translate its strings\n- Compile a pack\n',
      ),
      HelpSection(
        title: 'Translate a mod',
        anchor: 'translate-a-mod',
        content:
            '## Translate a mod\n\nOpen a project and edit localised strings '
            'inline. Use the glossary to keep terminology consistent across '
            'every pack.\n\n'
            '> Tip: press `Ctrl+S` to save the current row.\n\n'
            '```bash\ntwmt export --target fr\n```\n',
      ),
      HelpSection(
        title: 'Publish to Workshop',
        anchor: 'publish-to-workshop',
        content:
            '## Publish to Workshop\n\nCompile a pack, then upload it to the '
            'Steam Workshop directly from the publish screen.\n',
      ),
    ];

List<Override> _overrides() => [
      helpSectionsProvider.overrideWith((_) async => _sections()),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const HelpScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('help screen atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(HelpScreen),
      matchesGoldenFile('../goldens/help_atelier.png'),
    );
  });

  testWidgets('help screen forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(HelpScreen),
      matchesGoldenFile('../goldens/help_forge.png'),
    );
  });
}
