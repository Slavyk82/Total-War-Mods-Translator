import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/compilation_editor_state.dart';

void main() {
  group('defaultPrefixForLanguage', () {
    test('uses the default marker when none is provided', () {
      expect(
        CompilationEditorState.defaultPrefixForLanguage('fr'),
        '!!!!!!!!!!_fr_compilation_twmt_',
      );
    });

    test('uses a custom marker when provided', () {
      expect(
        CompilationEditorState.defaultPrefixForLanguage('fr', marker: 'zzz'),
        'zzz_fr_compilation_twmt_',
      );
    });
  });
}
