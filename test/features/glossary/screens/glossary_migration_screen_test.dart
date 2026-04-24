// Widget tests for [GlossaryMigrationScreen].
//
// These tests validate rendering of the two sections (universals +
// duplicates) and the double-confirmation guard before apply. No action
// that would trigger `FilePicker` or `applyMigration` is dispatched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/glossary/screens/glossary_migration_screen.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  testWidgets('shows universals section when universals exist',
      (tester) async {
    const pending = PendingGlossaryMigration(
      universals: [
        UniversalGlossaryInfo(
          id: 'u1',
          name: 'Legacy Universal',
          description: null,
          targetLanguageId: 'lang_fr',
          targetLanguageCode: 'fr',
          entryCount: 3,
        ),
      ],
      duplicates: [],
    );

    await tester.pumpWidget(
      createThemedTestableWidget(
        GlossaryMigrationScreen(pending: pending, onDone: () {}),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          configuredGamesProvider.overrideWith((ref) async => [
                const ConfiguredGame(code: 'wh3', name: 'WH3', path: '/p'),
              ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Glossary migration required'), findsOneWidget);
    expect(find.text('Universal glossaries'), findsOneWidget);
    expect(find.text('Legacy Universal'), findsOneWidget);
    expect(
      find.byKey(const Key('glossary-migration-export-u1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('glossary-migration-convert-u1')),
      findsOneWidget,
    );
  });

  testWidgets('shows duplicates section when duplicates exist',
      (tester) async {
    const pending = PendingGlossaryMigration(
      universals: [],
      duplicates: [
        DuplicateGlossaryGroup(
          gameCode: 'wh3',
          targetLanguageId: 'lang_fr',
          targetLanguageCode: 'fr',
          members: [
            DuplicateGlossaryMember(
              id: 'a',
              name: 'A',
              entryCount: 2,
              createdAt: 0,
            ),
            DuplicateGlossaryMember(
              id: 'b',
              name: 'B',
              entryCount: 1,
              createdAt: 1,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      createThemedTestableWidget(
        GlossaryMigrationScreen(pending: pending, onDone: () {}),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          configuredGamesProvider.overrideWith((ref) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Duplicate glossaries'), findsOneWidget);
    expect(find.textContaining('A (2 entries)'), findsOneWidget);
    expect(find.textContaining('B (1 entries)'), findsOneWidget);
  });

  testWidgets(
      'apply button opens a confirmation dialog when any universal is left '
      'on "Don\'t convert"', (tester) async {
    const pending = PendingGlossaryMigration(
      universals: [
        UniversalGlossaryInfo(
          id: 'u1',
          name: 'Legacy Universal',
          description: null,
          targetLanguageId: 'lang_fr',
          targetLanguageCode: 'fr',
          entryCount: 5,
        ),
      ],
      duplicates: [],
    );

    await tester.pumpWidget(
      createThemedTestableWidget(
        GlossaryMigrationScreen(pending: pending, onDone: () {}),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          configuredGamesProvider.overrideWith((ref) async => [
                const ConfiguredGame(code: 'wh3', name: 'WH3', path: '/p'),
              ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('glossary-migration-apply')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('glossary-migration-confirm-delete')),
      findsOneWidget,
    );
    expect(find.text('Delete universal glossaries?'), findsOneWidget);
    expect(find.textContaining('Legacy Universal'), findsWidgets);

    // Go back dismisses the dialog and leaves the migration screen intact.
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('glossary-migration-confirm-delete')),
      findsNothing,
    );
    expect(find.text('Glossary migration required'), findsOneWidget);
  });
}
