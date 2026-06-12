import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';

void main() {
  test('TmServiceException carries its message', () {
    const e = TmServiceException('boom');
    expect(e.message, 'boom');
  });

  test('TmEntryNotFoundException includes id/hash in toString', () {
    const e = TmEntryNotFoundException('missing', entryId: 'e1', sourceHash: 'h');
    expect(e.entryId, 'e1');
    expect(e.toString(), allOf(contains('e1'), contains('h')));
  });

  test('TmLookupException truncates a long source text in toString', () {
    final e = TmLookupException('fail', 'x' * 100, 'fr');
    expect(e.targetLanguageCode, 'fr');
    expect(e.toString(), contains('...'));
  });

  test('TmAddException keeps source/target', () {
    const e = TmAddException('fail', sourceText: 's', targetText: 't');
    expect(e.sourceText, 's');
    expect(e.toString(), contains('fail'));
  });

  test('TmImportException reports processed/failed counts', () {
    const e = TmImportException('fail',
        filePath: 'in.tmx', processedEntries: 9, failedEntries: 1);
    expect(e.toString(), allOf(contains('in.tmx'), contains('9'), contains('1')));
  });

  test('TmExportException reports path and count', () {
    const e = TmExportException('fail', outputPath: 'out.tmx', entriesCount: 5);
    expect(e.toString(), allOf(contains('out.tmx'), contains('5')));
  });

  test('SimilarityCalculationException reports the algorithm', () {
    const e = SimilarityCalculationException('fail', algorithm: 'levenshtein');
    expect(e.toString(), contains('levenshtein'));
  });

  test('NormalizationException truncates a long original text', () {
    final e = NormalizationException('fail', originalText: 'y' * 100);
    expect(e.toString(), contains('...'));
  });

  test('TmCacheException reports key and operation', () {
    const e = TmCacheException('fail', cacheKey: 'k', operation: 'get');
    expect(e.toString(), allOf(contains('k'), contains('get')));
  });
}
