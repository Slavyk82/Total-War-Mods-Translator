import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/pack_image_generator_service.dart';

/// Pins the flag-code resolution: variant/regional language codes must map to
/// the actual flag asset file names (e.g. Brazilian Portuguese `ptbr` -> `br`),
/// while plain codes pass through unchanged.
void main() {
  group('PackImageGeneratorService.flagCodeFor', () {
    test('maps Brazilian Portuguese variants to br', () {
      expect(PackImageGeneratorService.flagCodeFor('ptbr'), 'br');
      expect(PackImageGeneratorService.flagCodeFor('pt-BR'), 'br');
      expect(PackImageGeneratorService.flagCodeFor('PT_BR'), 'br');
    });

    test('maps Total War pack codes to their flag file names', () {
      expect(PackImageGeneratorService.flagCodeFor('jp'), 'ja');
      expect(PackImageGeneratorService.flagCodeFor('kr'), 'ko');
      expect(PackImageGeneratorService.flagCodeFor('cz'), 'cs');
      expect(PackImageGeneratorService.flagCodeFor('cn'), 'zh');
      expect(PackImageGeneratorService.flagCodeFor('tw'), 'zh');
    });

    test('passes plain codes through, lowercased', () {
      expect(PackImageGeneratorService.flagCodeFor('fr'), 'fr');
      expect(PackImageGeneratorService.flagCodeFor('PT'), 'pt');
      expect(PackImageGeneratorService.flagCodeFor('de'), 'de');
    });
  });
}
