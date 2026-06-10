// Regression tests for TmImportExportService.exportToTmx export options.
//
// 2026-06-10 review (LOW / L14): the TMX export dialog rendered a
// "What to export" scope (all / frequently used >5 times) and two format
// toggles (include metadata / include statistics), but none of them were
// passed to the export call — every export silently contained all entries
// with all metadata. These tests lock in the now-wired options at the
// service seam:
//   - minUsageCount is pushed down to the repository page query (and to the
//     stats COUNT) so "frequently used" exports only matching entries;
//   - includeMetadata: false omits the per-TU TWMT <prop> elements;
//   - includeStats controls the export-summary <prop> elements in the TMX
//     header (and whether the COUNT query runs at all).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_import_export_service.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}

TranslationMemoryEntry _entry(int i, {int usageCount = 0}) =>
    TranslationMemoryEntry(
      id: 'id-$i',
      sourceText: 'source $i',
      sourceHash: 'hash-$i',
      sourceLanguageId: 'lang_en',
      translatedText: 'target $i',
      targetLanguageId: 'lang_fr',
      usageCount: usageCount,
      createdAt: 1000,
      updatedAt: 1000,
      lastUsedAt: 1000,
    );

void main() {
  late _MockRepo repo;
  late TmImportExportService service;
  late Directory tmpDir;

  setUp(() {
    repo = _MockRepo();
    service = TmImportExportService(
      repository: repo,
      tmxService: TmxService(
        repository: repo,
        normalizer: TextNormalizer(),
        logger: FakeLogger(),
      ),
      logger: FakeLogger(),
    );
    tmpDir = Directory.systemTemp.createTempSync('tm_export_options_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  /// Stubs getPage to return [page] on the first page and empty afterwards,
  /// regardless of filters (the filter forwarding is asserted via verify).
  void stubPages(List<TranslationMemoryEntry> page) {
    when(() => repo.getPage(
          offset: any(named: 'offset'),
          pageSize: any(named: 'pageSize'),
          targetLanguageId: any(named: 'targetLanguageId'),
          minUsageCount: any(named: 'minUsageCount'),
        )).thenAnswer((invocation) async {
      final offset = invocation.namedArguments[#offset] as int;
      return Ok(offset == 0 ? page : const []);
    });
  }

  test(
      'minUsageCount is pushed down to the page query and the exported file '
      'contains exactly the returned entries', () async {
    final frequentlyUsed = [_entry(0, usageCount: 9), _entry(1, usageCount: 6)];
    stubPages(frequentlyUsed);
    when(() => repo.countWithFilters(
          targetLanguageId: any(named: 'targetLanguageId'),
          minUsageCount: any(named: 'minUsageCount'),
        )).thenAnswer((_) async => const Ok(2));

    final outputPath = p.join(tmpDir.path, 'frequent.tmx');
    final result = await service.exportToTmx(
      outputPath: outputPath,
      targetLanguageCode: 'fr',
      minUsageCount: 6,
    );

    expect(result.isOk, true, reason: 'export should succeed: $result');
    expect(result.unwrap(), 2);

    // The usage-count filter must reach the SQL layer (paging offsets only
    // stay consistent when the filter is applied in the query itself).
    verify(() => repo.getPage(
          offset: 0,
          pageSize: any(named: 'pageSize'),
          targetLanguageId: 'lang_fr',
          minUsageCount: 6,
        )).called(1);
    verify(() => repo.countWithFilters(
          targetLanguageId: 'lang_fr',
          minUsageCount: 6,
        )).called(1);

    final xml = File(outputPath).readAsStringSync();
    expect(xml, contains('source 0'));
    expect(xml, contains('source 1'));
    expect(xml, contains('<prop type="x-min-usage-count">6</prop>'));
  });

  test('includeStats: true writes an export summary into the TMX header',
      () async {
    stubPages([_entry(0)]);
    when(() => repo.countWithFilters(
          targetLanguageId: any(named: 'targetLanguageId'),
          minUsageCount: any(named: 'minUsageCount'),
        )).thenAnswer((_) async => const Ok(1));

    final outputPath = p.join(tmpDir.path, 'stats.tmx');
    final result = await service.exportToTmx(
      outputPath: outputPath,
      targetLanguageCode: 'fr',
    );

    expect(result.isOk, true);
    final xml = File(outputPath).readAsStringSync();
    expect(xml, contains('<prop type="x-entry-count">1</prop>'));
    expect(xml, contains('x-export-date'));
  });

  test(
      'includeStats: false skips the COUNT query and writes no header stats',
      () async {
    stubPages([_entry(0)]);

    final outputPath = p.join(tmpDir.path, 'no_stats.tmx');
    final result = await service.exportToTmx(
      outputPath: outputPath,
      targetLanguageCode: 'fr',
      includeStats: false,
    );

    expect(result.isOk, true);
    verifyNever(() => repo.countWithFilters(
          targetLanguageId: any(named: 'targetLanguageId'),
          minUsageCount: any(named: 'minUsageCount'),
        ));
    final xml = File(outputPath).readAsStringSync();
    expect(xml, isNot(contains('x-entry-count')));
    expect(xml, isNot(contains('x-export-date')));
  });

  test('includeMetadata: false omits per-TU TWMT props', () async {
    stubPages([_entry(0, usageCount: 3)]);

    final outputPath = p.join(tmpDir.path, 'no_meta.tmx');
    final result = await service.exportToTmx(
      outputPath: outputPath,
      targetLanguageCode: 'fr',
      includeMetadata: false,
      includeStats: false,
    );

    expect(result.isOk, true);
    final xml = File(outputPath).readAsStringSync();
    expect(xml, isNot(contains('x-usage-count')));
    expect(xml, isNot(contains('x-provider-id')));
    // The actual translation content is unaffected.
    expect(xml, contains('source 0'));
    expect(xml, contains('target 0'));
  });

  test('defaults (all entries, metadata + stats on) keep legacy behavior',
      () async {
    stubPages([_entry(0, usageCount: 4)]);
    when(() => repo.countWithFilters(
          targetLanguageId: any(named: 'targetLanguageId'),
          minUsageCount: any(named: 'minUsageCount'),
        )).thenAnswer((_) async => const Ok(1));

    final outputPath = p.join(tmpDir.path, 'defaults.tmx');
    final result = await service.exportToTmx(
      outputPath: outputPath,
      targetLanguageCode: 'fr',
    );

    expect(result.isOk, true);
    verify(() => repo.getPage(
          offset: 0,
          pageSize: any(named: 'pageSize'),
          targetLanguageId: 'lang_fr',
          minUsageCount: null,
        )).called(1);
    final xml = File(outputPath).readAsStringSync();
    expect(xml, contains('<prop type="x-usage-count">4</prop>'));
  });
}
