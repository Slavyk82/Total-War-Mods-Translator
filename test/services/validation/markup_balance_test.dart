import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

void main() {
  group('Markup Balance Validator', () {
    late ValidationServiceImpl validator;

    setUp(() {
      validator = ValidationServiceImpl();
    });

    test('should validate balanced XML tags', () async {
      const source = '<b>Hello</b> <i>World</i>';
      const translation = '<b>Bonjour</b> <i>Monde</i>';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should detect unbalanced XML tags', () async {
      const source = '<b>Hello</b>';
      const translation = '<b>Bonjour</i>'; // Wrong closing tag

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNotNull);
      expect(error!.message, contains('Unbalanced'));
    });

    test('should handle self-closing tags', () async {
      const source = 'Line 1<br/>Line 2';
      const translation = 'Ligne 1<br/>Ligne 2';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should handle BBCode tags', () async {
      const source = '[color=red]Hello[/color]';
      const translation = '[color=red]Bonjour[/color]';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should handle nested tags', () async {
      const source = '<b>Hello <i>World</i></b>';
      const translation = '<b>Bonjour <i>Monde</i></b>';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should detect incorrectly nested tags', () async {
      const source = '<b>Hello <i>World</i></b>';
      const translation = '<b>Bonjour <i>Monde</b></i>'; // Incorrect nesting

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNotNull);
      expect(error!.message, contains('Unbalanced'));
    });

    test('should handle tags with attributes', () async {
      const source = '<div class="foo">Hello</div>';
      const translation = '<div class="foo">Bonjour</div>';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should detect missing tags', () async {
      const source = '<b>Hello</b> <i>World</i>';
      const translation = '<b>Bonjour</b> Monde'; // Missing <i> tags

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNotNull);
      expect(error!.message, contains('tag count mismatch'));
    });

    test('should handle real-world example: mct_button_client_change', () async {
      // We need to find the actual source text to test this properly
      // For now, let's test common patterns that might appear in game mods

      const source = '<color=#FF0000>Change Client</color>';
      const translation = '<color=#FF0000>Changer de client</color>';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'mct_button_client_change',
      );

      expect(error, isNull);
    });

    test('should handle Total War style color tags', () async {
      const source = '[[col:red]]Important[[/col]]';
      const translation = '[[col:red]]Important[[/col]]';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      expect(error, isNull);
    });

    test('should not treat bracketed printf placeholders as BBCode tags', () async {
      // [%s] should be treated as a variable placeholder, not a BBCode tag
      const source = 'There are pending changes on [%s] that will be lost.';
      const translation = 'Il y a des modifications en attente sur [%s] qui seront perdues.';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      // Should pass - [%s] is not a markup tag
      expect(error, isNull);
    });

    test('should distinguish between [%s] placeholder and [tag] BBCode', () async {
      // Mix of real BBCode and printf placeholder
      const source = '[b]Warning[/b]: Changes on [%s] detected.';
      const translation = '[b]Attention[/b]: Modifications sur [%s] détectées.';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      // Should pass - [%s] is preserved as variable, [b][/b] are balanced
      expect(error, isNull);
    });

    test('should detect unbalanced tags in source text', () async {
      // Source has orphaned closing tag (data quality issue)
      const source = 's Settings[[/col]]';
      const translation = 's Settings[[/col]]';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      // Should return warning about unbalanced source tags
      expect(error, isNotNull);
      expect(error!.severity, ValidationSeverity.warning);
      expect(error.message, contains('Source text has unbalanced'));
    });

    test('should detect unbalanced tags - opening without closing', () async {
      // Source has opening tag without closing
      const source = '[[col:red]]Warning';
      const translation = '[[col:red]]Avertissement';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      // Should return warning about unbalanced source tags
      expect(error, isNotNull);
      expect(error!.severity, ValidationSeverity.warning);
      expect(error.message, contains('Source text has unbalanced'));
    });

    test('should allow translation to preserve unbalanced tags from source', () async {
      // If source has unbalanced tags, translation should preserve them identically
      const source = 'Text[[/col]]';
      const translation = 'Texte[[/col]]';

      final error = await validator.checkMarkupPreservation(
        sourceText: source,
        translatedText: translation,
        key: 'test',
      );

      // Should only warn about source, not fail validation
      expect(error, isNotNull);
      expect(error!.severity, ValidationSeverity.warning);
    });
  });
}
