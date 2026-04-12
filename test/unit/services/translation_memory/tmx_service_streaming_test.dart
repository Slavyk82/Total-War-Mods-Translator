import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}

class _FakeLogger extends Fake implements LoggingService {
  @override
  void debug(String m, [dynamic d]) {}

  @override
  void warning(String m, [dynamic d]) {}

  @override
  void info(String m, [dynamic d]) {}

  @override
  void error(String m, [dynamic e, StackTrace? s]) {}
}

void main() {
  late _MockRepo repo;
  late TmxService service;
  late Directory tmpDir;

  setUp(() {
    repo = _MockRepo();
    service = TmxService(
      repository: repo,
      normalizer: TextNormalizer(),
      logger: _FakeLogger(),
    );
    tmpDir = Directory.systemTemp.createTempSync('tmx_stream_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('TmxService.exportToTmxStreaming', () {
    test('round-trips TMX entries across multiple pages', () async {
      // Build 7 entries across 3 pages of pageSize=3 (3+3+1)
      final entries = List.generate(
        7,
        (i) => TranslationMemoryEntry(
          id: 'id-$i',
          sourceText: 'source $i',
          sourceHash: 'hash-$i',
          sourceLanguageId: 'en',
          translatedText: 'target $i',
          targetLanguageId: 'fr',
          usageCount: i,
          createdAt: 1000,
          updatedAt: 1000,
          lastUsedAt: 1000,
        ),
      );

      final outputPath = p.join(tmpDir.path, 'out.tmx');

      final result = await service.exportToTmxStreaming(
        filePath: outputPath,
        pageFetcher: (offset, pageSize) async {
          final slice = entries.skip(offset).take(pageSize).toList();
          return Ok(slice);
        },
        sourceLanguage: 'en',
        targetLanguage: 'fr',
        pageSize: 3,
      );

      expect(result.isOk, true, reason: 'streaming export should succeed');
      expect(result.unwrap(), 7, reason: 'should report 7 entries written');

      // Round-trip: read back via the existing importer
      final importResult = await service.importFromTmx(filePath: outputPath);
      expect(importResult.isOk, true,
          reason: 'output must be a valid TMX file');
      final imported = importResult.unwrap();
      expect(imported.length, 7, reason: '7 entries round-trip');
      expect(imported.first.sourceText, 'source 0');
      expect(imported.last.sourceText, 'source 6');
    });

    test('returns Ok(0) when pageFetcher returns empty first page', () async {
      final outputPath = p.join(tmpDir.path, 'empty.tmx');

      final result = await service.exportToTmxStreaming(
        filePath: outputPath,
        pageFetcher: (offset, pageSize) async => const Ok([]),
        sourceLanguage: 'en',
        targetLanguage: 'fr',
        pageSize: 5000,
      );

      expect(result.isOk, true);
      expect(result.unwrap(), 0);
      expect(File(outputPath).existsSync(), true,
          reason: 'even an empty export should produce a valid TMX file');
    });
  });
}
