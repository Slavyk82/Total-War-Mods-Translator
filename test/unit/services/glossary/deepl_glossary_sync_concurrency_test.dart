import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/deepl_glossary_sync_service.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart';
import 'package:twmt/services/glossary/models/deepl_glossary_mapping.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryRepo extends Mock implements GlossaryRepository {}

class _MockDeepL extends Mock implements GlossaryDeepLService {}

/// Regression test: ensureGlossarySynced was an unguarded check-then-act. In
/// the parallel LLM batch flow several chunks call it concurrently with the
/// SAME (glossaryId, source, target), all observe existingMapping == null, and
/// each then creates a server-side DeepL glossary + inserts a mapping —
/// leaking N-1 orphaned DeepL glossaries (limited account slots) and duplicate
/// mappings. Concurrent calls for the same triple must collapse to one sync.
void main() {
  setUpAll(() {
    registerFallbackValue(const DeepLGlossaryMapping(
      id: 'x',
      twmtGlossaryId: 'g',
      sourceLanguageCode: 'en',
      targetLanguageCode: 'fr',
      deeplGlossaryId: 'd',
      deeplGlossaryName: 'n',
      entryCount: 1,
      syncStatus: 'synced',
      syncedAt: 0,
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  late _MockGlossaryRepo repo;
  late _MockDeepL deepl;
  late DeepLGlossarySyncService service;

  setUp(() {
    repo = _MockGlossaryRepo();
    deepl = _MockDeepL();
    service = DeepLGlossarySyncService(
      glossaryRepository: repo,
      deeplService: deepl,
      logging: FakeLogger(),
    );

    when(() => repo.getEntryCountForLanguage(
          glossaryId: any(named: 'glossaryId'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => 3);
    when(() => repo.getDeepLMapping(
          twmtGlossaryId: any(named: 'twmtGlossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => null);
    when(() => repo.doesMappingNeedResync(
          twmtGlossaryId: any(named: 'twmtGlossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => true);
    when(() => repo.getGlossaryById(any())).thenAnswer((_) async => null);
    when(() => repo.insertDeepLMapping(any())).thenAnswer((_) async {});
    when(() => deepl.createDeepLGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async {
      // A real network round-trip; the race window is while this is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return Ok<String, GlossaryException>('deepl-id');
    });
  });

  test(
      'concurrent calls for the same triple create exactly one DeepL glossary',
      () async {
    final results = await Future.wait([
      for (var i = 0; i < 5; i++)
        service.ensureGlossarySynced(
          glossaryId: 'g1',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        ),
    ]);

    for (final r in results) {
      expect(r.isOk, isTrue, reason: r.toString());
      expect(r.value, 'deepl-id');
    }
    verify(() => deepl.createDeepLGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(1);
    verify(() => repo.insertDeepLMapping(any())).called(1);
  });

  test('different triples are still synced independently', () async {
    await Future.wait([
      service.ensureGlossarySynced(
          glossaryId: 'g1', sourceLanguageCode: 'en', targetLanguageCode: 'fr'),
      service.ensureGlossarySynced(
          glossaryId: 'g1', sourceLanguageCode: 'en', targetLanguageCode: 'de'),
    ]);

    verify(() => deepl.createDeepLGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(2);
  });
}
