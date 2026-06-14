import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/steam/workshop_template.dart';

void main() {
  group('resolveLocalizedTemplate', () {
    test('returns plain text unchanged', () {
      expect(
        resolveLocalizedTemplate('Français - \$modName par Slavyk',
            languageCode: 'fr'),
        'Français - \$modName par Slavyk',
      );
    });

    test('unwraps a single-language JSON map to its inner text', () {
      // The exact shape that crashed steamcmd's KeyValues parser: a localized
      // map stored as the template instead of plain text.
      const raw = '{"fr":"[h1]Traduction Française[/h1]\\r\\n[i]abo[/i]"}';
      expect(
        resolveLocalizedTemplate(raw, languageCode: 'fr'),
        '[h1]Traduction Française[/h1]\r\n[i]abo[/i]',
      );
    });

    test('picks the requested language from a multi-language map', () {
      const raw = '{"en":"English text","fr":"Texte français"}';
      expect(resolveLocalizedTemplate(raw, languageCode: 'fr'),
          'Texte français');
      expect(resolveLocalizedTemplate(raw, languageCode: 'en'),
          'English text');
    });

    test('falls back to the first value when language missing or null', () {
      const raw = '{"fr":"Texte français","de":"Deutsch"}';
      expect(resolveLocalizedTemplate(raw, languageCode: 'es'),
          'Texte français');
      expect(resolveLocalizedTemplate(raw), 'Texte français');
    });

    test('leaves a non-language JSON object untouched', () {
      // A description that legitimately *is* JSON-shaped must not be unwrapped.
      const raw = '{"title":"My Mod","note":"v2"}';
      expect(resolveLocalizedTemplate(raw, languageCode: 'fr'), raw);
    });

    test('leaves a JSON map with non-string values untouched', () {
      const raw = '{"fr":123}';
      expect(resolveLocalizedTemplate(raw, languageCode: 'fr'), raw);
    });

    test('leaves invalid JSON that merely starts with a brace untouched', () {
      const raw = '{not really json';
      expect(resolveLocalizedTemplate(raw, languageCode: 'fr'), raw);
    });

    test('returns empty string unchanged', () {
      expect(resolveLocalizedTemplate('', languageCode: 'fr'), '');
    });

    test('supports region-qualified language codes', () {
      const raw = '{"pt_BR":"Português BR","en":"English"}';
      expect(resolveLocalizedTemplate(raw, languageCode: 'pt_BR'),
          'Português BR');
    });
  });
}
