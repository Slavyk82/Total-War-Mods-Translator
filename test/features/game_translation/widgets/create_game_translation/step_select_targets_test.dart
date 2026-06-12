import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/game_translation_creation_state.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/step_select_targets.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/wizard/language_selection_tile.dart';

Language _lang(String code) => Language(
      id: 'id-$code',
      code: code,
      name: code.toUpperCase(),
      nativeName: code,
    );

DetectedLocalPack _pack(String code) => DetectedLocalPack(
      languageCode: code,
      languageName: code.toUpperCase(),
      packFilePath: 'local_$code.pack',
      fileSizeBytes: 0,
      lastModified: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required GameTranslationCreationState state,
  required List<Language> languages,
  VoidCallback? onChanged,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => languages),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          // StatefulBuilder mirrors the wizard parent: onStateChanged rebuilds
          // the step so state-derived UI (selection summary) reflects updates.
          body: StatefulBuilder(
            builder: (context, setInner) => SingleChildScrollView(
              child: StepSelectTargets(
                state: state,
                onStateChanged: () {
                  setInner(() {});
                  onChanged?.call();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a tile for each available language', (tester) async {
    await _pump(
      tester,
      state: GameTranslationCreationState(),
      languages: [_lang('fr'), _lang('de'), _lang('es')],
    );

    expect(find.byType(LanguageSelectionTile), findsNWidgets(3));
  });

  testWidgets('excludes the source language resolved from the pack',
      (tester) async {
    final state = GameTranslationCreationState()
      ..selectedSourcePack = _pack('cn'); // 'cn' -> DB 'zh'

    await _pump(
      tester,
      state: state,
      languages: [_lang('zh'), _lang('fr'), _lang('de')],
    );

    // 'zh' is the source and must not be offered as a target.
    expect(find.byType(LanguageSelectionTile), findsNWidgets(2));
    expect(find.text(t.gameTranslation.stepTargets.translatingFrom),
        findsOneWidget);
  });

  testWidgets('tapping a language toggles it and shows the selection count',
      (tester) async {
    final state = GameTranslationCreationState();
    var notified = 0;

    await _pump(
      tester,
      state: state,
      languages: [_lang('fr')],
      onChanged: () => notified++,
    );

    await tester.tap(find.byType(LanguageSelectionTile));
    await tester.pumpAndSettle();

    expect(state.isLanguageSelected('id-fr'), isTrue);
    expect(notified, 1);
    expect(
      find.text(t.gameTranslation.stepTargets.selectionCount(count: 1)),
      findsOneWidget,
    );
  });

  testWidgets('select-all selects every language, clear empties the selection',
      (tester) async {
    final state = GameTranslationCreationState();

    await _pump(
      tester,
      state: state,
      languages: [_lang('fr'), _lang('de')],
    );

    await tester.tap(find.text(t.gameTranslation.stepTargets.actions.selectAll));
    await tester.pumpAndSettle();
    expect(state.selectedLanguageIds, {'id-fr', 'id-de'});

    await tester.tap(find.text(t.gameTranslation.stepTargets.actions.clear));
    await tester.pumpAndSettle();
    expect(state.selectedLanguageIds, isEmpty);
  });
}
