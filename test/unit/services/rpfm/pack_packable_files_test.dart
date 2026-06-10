import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_pack_operations_mixin.dart'
    show hasPackableLocalizationFiles;

/// Regression test for the empty-pack guard: createPack listed the input
/// directory and, when it contained neither .tsv nor .loc files, ran neither
/// add-branch and returned Ok for the empty pack created in step 1 — silently
/// shipping a translation-less pack into the game's data folder marked
/// "Generated". This pins the file-classification guard.
void main() {
  test('returns true when a .tsv file is present', () {
    expect(
      hasPackableLocalizationFiles([
        'C:/tmp/text_fr.loc.tsv',
        'C:/tmp/notes.txt',
      ]),
      isTrue,
    );
  });

  test('returns true when only a legacy .loc file is present', () {
    expect(
      hasPackableLocalizationFiles(['C:/tmp/text_fr.loc']),
      isTrue,
    );
  });

  test('is case-insensitive on the extension', () {
    expect(hasPackableLocalizationFiles(['C:/tmp/TEXT_FR.LOC.TSV']), isTrue);
  });

  test('returns false for an empty input set', () {
    expect(hasPackableLocalizationFiles(const <String>[]), isFalse);
  });

  test('returns false when no localization files are present', () {
    expect(
      hasPackableLocalizationFiles([
        'C:/tmp/readme.md',
        'C:/tmp/data.bin',
      ]),
      isFalse,
    );
  });
}
