import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart'
    show glossaryEntriesToDeepLTsv;

/// Regression tests: the DeepL TSV export wrote one line per entry with no
/// source-term dedup. The DB UNIQUE includes case_sensitive, so two entries can
/// share the same trimmed source term; DeepL rejects glossaries with duplicate
/// source entries (HTTP 400), failing createDeepLGlossary for the whole glossary.
GlossaryEntry _entry({
  required String source,
  required String target,
  bool caseSensitive = false,
}) =>
    GlossaryEntry(
      id: 'id-$source-$target-$caseSensitive',
      glossaryId: 'g',
      targetLanguageCode: 'fr',
      sourceTerm: source,
      targetTerm: target,
      caseSensitive: caseSensitive,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  test('deduplicates entries that share a trimmed source term (first wins)', () {
    final tsv = glossaryEntriesToDeepLTsv([
      _entry(source: 'Faction', target: 'Faction', caseSensitive: true),
      _entry(source: 'Faction', target: 'faction', caseSensitive: false),
    ]);

    final lines = tsv.trim().split('\n');
    expect(lines, hasLength(1),
        reason: 'DeepL rejects a glossary with duplicate source terms');
    expect(lines.single, 'Faction\tFaction');
  });

  test('skips entries whose trimmed source or target term is empty', () {
    final tsv = glossaryEntriesToDeepLTsv([
      _entry(source: '   ', target: 'x'),
      _entry(source: 'y', target: '  '),
      _entry(source: 'real', target: 'reel'),
    ]);

    expect(tsv.trim().split('\n'), ['real\treel']);
  });

  test('keeps distinct source terms', () {
    final tsv = glossaryEntriesToDeepLTsv([
      _entry(source: 'A', target: 'a'),
      _entry(source: 'B', target: 'b'),
    ]);

    expect(tsv.trim().split('\n'), ['A\ta', 'B\tb']);
  });
}
