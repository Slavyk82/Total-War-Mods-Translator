import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/game_translation_creation_state.dart';

void main() {
  late GameTranslationCreationState state;

  setUp(() => state = GameTranslationCreationState());
  tearDown(() => state.dispose());

  group('initial state', () {
    test('has no game, source pack, or selected languages', () {
      expect(state.selectedGameId, isNull);
      expect(state.selectedSourcePack, isNull);
      expect(state.selectedLanguageIds, isEmpty);
    });

    test('seeds controllers with default batch settings', () {
      expect(state.batchSizeController.text, '25');
      expect(state.parallelBatchesController.text, '3');
      expect(state.customPromptController.text, '');
    });
  });

  group('toggleLanguage', () {
    test('adds a language when not yet selected', () {
      state.toggleLanguage('fr');

      expect(state.isLanguageSelected('fr'), isTrue);
      expect(state.selectedLanguageIds, {'fr'});
    });

    test('removes a language that is already selected', () {
      state.toggleLanguage('fr');
      state.toggleLanguage('fr');

      expect(state.isLanguageSelected('fr'), isFalse);
      expect(state.selectedLanguageIds, isEmpty);
    });

    test('tracks multiple distinct languages', () {
      state.toggleLanguage('fr');
      state.toggleLanguage('de');

      expect(state.selectedLanguageIds, {'fr', 'de'});
    });
  });

  test('clearLanguages removes all selections', () {
    state.toggleLanguage('fr');
    state.toggleLanguage('de');

    state.clearLanguages();

    expect(state.selectedLanguageIds, isEmpty);
    expect(state.isLanguageSelected('fr'), isFalse);
  });
}
