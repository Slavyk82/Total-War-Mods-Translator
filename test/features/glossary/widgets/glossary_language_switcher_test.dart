// Widget tests for [GlossaryLanguageSwitcher] — the popover chip used by the
// glossary screen to pick which (gameCode, targetLanguageId) pair is shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_language_switcher.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

Language _lang(String id, String code, String name) => Language(
      id: id,
      code: code,
      name: name,
      nativeName: name,
    );

/// Captures calls to [setLanguageId] so the tap test can assert routing
/// without needing a real settings service underneath.
class _RecordingSelectedGlossaryLanguage extends SelectedGlossaryLanguage {
  final List<(String, String?)> calls = [];
  String? _value;

  _RecordingSelectedGlossaryLanguage({String? initial}) : _value = initial;

  @override
  Future<String?> build(String gameCode) async => _value;

  @override
  Future<void> setLanguageId(String gameCode, String? languageId) async {
    calls.add((gameCode, languageId));
    _value = languageId;
    state = AsyncData(languageId);
  }
}

void main() {
  setUp(setupMockServices);
  tearDown(tearDownMockServices);

  testWidgets('chip shows "—" when no language is selected', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: Center(
          child: GlossaryLanguageSwitcher(
            gameCode: 'wh3',
            currentLanguageId: null,
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        glossaryAvailableLanguagesProvider('wh3').overrideWith(
          (_) async => [
            _lang('fr-id', 'fr', 'French'),
            _lang('de-id', 'de', 'German'),
          ],
        ),
      ],
    ));
    await tester.pumpAndSettle();

    // The chip renders the dash placeholder when `currentLanguageId` has no
    // match in the language list.
    expect(
      find.descendant(
        of: find.byKey(const Key('glossary-language-switcher-chip')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('menu lists every language from the provider', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: Center(
          child: GlossaryLanguageSwitcher(
            gameCode: 'wh3',
            currentLanguageId: 'fr-id',
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        glossaryAvailableLanguagesProvider('wh3').overrideWith(
          (_) async => [
            _lang('fr-id', 'fr', 'French'),
            _lang('de-id', 'de', 'German'),
            _lang('es-id', 'es', 'Spanish'),
          ],
        ),
      ],
    ));
    await tester.pumpAndSettle();

    // Chip shows the current language name.
    expect(
      find.descendant(
        of: find.byKey(const Key('glossary-language-switcher-chip')),
        matching: find.text('French'),
      ),
      findsOneWidget,
    );

    // Open the menu.
    await tester
        .tap(find.byKey(const Key('glossary-language-switcher-chip')));
    await tester.pumpAndSettle();

    // Every language is listed in the popover (identified by stable keys).
    expect(
      find.byKey(const Key('glossary-language-switcher-item-fr-id')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('glossary-language-switcher-item-de-id')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('glossary-language-switcher-item-es-id')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a language item calls setLanguageId on the notifier',
      (tester) async {
    final fakeNotifier = _RecordingSelectedGlossaryLanguage(initial: 'fr-id');

    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: Center(
          child: GlossaryLanguageSwitcher(
            gameCode: 'wh3',
            currentLanguageId: 'fr-id',
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        glossaryAvailableLanguagesProvider('wh3').overrideWith(
          (_) async => [
            _lang('fr-id', 'fr', 'French'),
            _lang('de-id', 'de', 'German'),
          ],
        ),
        selectedGlossaryLanguageProvider('wh3')
            .overrideWith(() => fakeNotifier),
      ],
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('glossary-language-switcher-chip')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('glossary-language-switcher-item-de-id')));
    await tester.pumpAndSettle();

    expect(fakeNotifier.calls, [('wh3', 'de-id')]);
  });
}
