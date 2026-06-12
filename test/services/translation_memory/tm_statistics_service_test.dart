import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tm_statistics_service.dart';

import '../../helpers/noop_logger.dart';

class MockTmRepository extends Mock implements TranslationMemoryRepository {}

class MockLanguageRepository extends Mock implements LanguageRepository {}

class MockSettingsService extends Mock implements SettingsService {}

Language _language(String id, String name) => Language(
      id: id,
      code: name.toLowerCase(),
      name: name,
      nativeName: name,
    );

void main() {
  late MockTmRepository repo;
  late MockLanguageRepository langRepo;
  late MockSettingsService settings;
  late TmCache cache;
  late TmStatisticsService service;

  setUp(() {
    repo = MockTmRepository();
    langRepo = MockLanguageRepository();
    settings = MockSettingsService();
    cache = TmCache();
    service = TmStatisticsService(
      repository: repo,
      languageRepository: langRepo,
      cache: cache,
      logger: NoopLogger(),
      settings: settings,
    );

    // Archive counters default to 0 unless a test overrides them.
    when(() => settings.getInt(any())).thenAnswer((_) async => 0);
    when(() => settings.setInt(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  T errOf<T>(Result result) => (result as Err).error as T;

  group('cleanupUnusedEntries', () {
    test('rejects negative unusedDays', () async {
      final result = await service.cleanupUnusedEntries(unusedDays: -1);
      expect(result, isA<Err>());
      expect(errOf<TmServiceException>(result).message,
          contains('non-negative'));
    });

    test('full wipe deletes all entries and archives reuse counters', () async {
      when(() => repo.deleteAllEntries()).thenAnswer(
        (_) async => Ok((deletedCount: 4, deletedUsageSum: 20)),
      );

      final result = await service.cleanupUnusedEntries(unusedDays: 0);

      expect((result as Ok).value, 4);
      verify(() => repo.deleteAllEntries()).called(1);
      verifyNever(() => repo.deleteByAge(unusedDays: any(named: 'unusedDays')));
      // priorReuse(0) + 20, priorEntries(0) + 4
      verify(() => settings.setInt('tm_archived_reuse_count', 20)).called(1);
      verify(() => settings.setInt('tm_archived_entries_count', 4)).called(1);
    });

    test('age-based cleanup uses deleteByAge and accumulates onto prior '
        'archive counters', () async {
      when(() => settings.getInt('tm_archived_reuse_count'))
          .thenAnswer((_) async => 100);
      when(() => settings.getInt('tm_archived_entries_count'))
          .thenAnswer((_) async => 10);
      when(() => repo.countCleanupCandidates(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => const Ok({'willBeDeleted': 3, 'unusedOnly': 3}));
      when(() => repo.deleteByAge(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => Ok((deletedCount: 3, deletedUsageSum: 7)));

      final result = await service.cleanupUnusedEntries(unusedDays: 30);

      expect((result as Ok).value, 3);
      verify(() => settings.setInt('tm_archived_reuse_count', 107)).called(1);
      verify(() => settings.setInt('tm_archived_entries_count', 13)).called(1);
    });

    test('does not touch archive counters when nothing was deleted', () async {
      when(() => repo.countCleanupCandidates(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => const Ok({'willBeDeleted': 0, 'unusedOnly': 0}));
      when(() => repo.deleteByAge(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => Ok((deletedCount: 0, deletedUsageSum: 0)));

      final result = await service.cleanupUnusedEntries(unusedDays: 30);

      expect((result as Ok).value, 0);
      verifyNever(() => settings.setInt(any(), any()));
    });

    test('returns Err when delete fails', () async {
      when(() => repo.countCleanupCandidates(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => const Ok({'willBeDeleted': 1, 'unusedOnly': 1}));
      when(() => repo.deleteByAge(unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('boom')));

      final result = await service.cleanupUnusedEntries(unusedDays: 30);

      expect(result, isA<Err>());
      expect(errOf<TmServiceException>(result).message,
          contains('Failed to delete entries'));
    });
  });

  group('getStatistics', () {
    void stubLanguagePairs(Map<String, int> pairs, List<Language> langs) {
      when(() => repo.getEntriesByLanguage())
          .thenAnswer((_) async => Ok(pairs));
      when(() => langRepo.getByIds(any()))
          .thenAnswer((_) async => Ok(langs));
    }

    test('computes reuse rate, tokens saved and resolves language names',
        () async {
      when(() => repo.getStatistics(targetLanguageId: any(named: 'targetLanguageId')))
          .thenAnswer((_) async =>
              const Ok({'total_entries': 10, 'total_usage': 5}));
      stubLanguagePairs(
        {'lang_fr': 8, 'lang_de': 2},
        [_language('lang_fr', 'French'), _language('lang_de', 'German')],
      );

      final result = await service.getStatistics();
      final stats = (result as Ok<TmStatistics, TmServiceException>).value;

      expect(stats.totalEntries, 10);
      expect(stats.totalReuseCount, 5);
      // 5 usage * 50 tokens
      expect(stats.tokensSaved, 250);
      // 5 / 10
      expect(stats.reuseRate, closeTo(0.5, 1e-9));
      expect(stats.entriesByLanguagePair, {'French': 8, 'German': 2});
    });

    test('folds archived counters into the unfiltered view', () async {
      when(() => settings.getInt('tm_archived_reuse_count'))
          .thenAnswer((_) async => 15);
      when(() => settings.getInt('tm_archived_entries_count'))
          .thenAnswer((_) async => 5);
      when(() => repo.getStatistics(targetLanguageId: null))
          .thenAnswer((_) async =>
              const Ok({'total_entries': 5, 'total_usage': 5}));
      stubLanguagePairs({}, const []);

      final result = await service.getStatistics();
      final stats = (result as Ok).value;

      // effectiveUsage = 5 + 15 = 20; tokens = 20 * 50
      expect(stats.totalReuseCount, 20);
      expect(stats.tokensSaved, 1000);
      // reuseRate = 20 / (5 + 5) = 2.0 -> clamped to 1.0
      expect(stats.reuseRate, 1.0);
    });

    test('ignores archive counters when filtering by language', () async {
      when(() => settings.getInt(any())).thenAnswer((_) async => 999);
      when(() => repo.getStatistics(targetLanguageId: 'lang_fr'))
          .thenAnswer((_) async =>
              const Ok({'total_entries': 4, 'total_usage': 2}));
      stubLanguagePairs(
        {'lang_fr': 4},
        [_language('lang_fr', 'French')],
      );

      final result = await service.getStatistics(targetLanguageCode: 'fr');
      final stats = (result as Ok).value;

      // Archive counters must NOT be folded in for a per-language view.
      expect(stats.totalReuseCount, 2);
      verifyNever(() => settings.getInt(any()));
    });

    test('falls back to raw id when a language name cannot be resolved',
        () async {
      when(() => repo.getStatistics(targetLanguageId: any(named: 'targetLanguageId')))
          .thenAnswer((_) async =>
              const Ok({'total_entries': 1, 'total_usage': 0}));
      // getByIds returns no matching language -> raw id is kept.
      stubLanguagePairs({'lang_xx': 1}, const []);

      final result = await service.getStatistics();
      final stats = (result as Ok).value;
      expect(stats.entriesByLanguagePair, {'lang_xx': 1});
      expect(stats.reuseRate, 0.0);
    });

    test('returns Err when base statistics query fails', () async {
      when(() => repo.getStatistics(targetLanguageId: any(named: 'targetLanguageId')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('nope')));

      final result = await service.getStatistics();
      expect(result, isA<Err>());
      expect(errOf<TmServiceException>(result).message,
          contains('Failed to get statistics'));
    });

    test('returns Err when language pair query fails', () async {
      when(() => repo.getStatistics(targetLanguageId: any(named: 'targetLanguageId')))
          .thenAnswer((_) async =>
              const Ok({'total_entries': 1, 'total_usage': 1}));
      when(() => repo.getEntriesByLanguage())
          .thenAnswer((_) async => Err(TWMTDatabaseException('nope')));

      final result = await service.getStatistics();
      expect(result, isA<Err>());
      expect(errOf<TmServiceException>(result).message,
          contains('language pair statistics'));
    });
  });

  group('cache operations', () {
    test('clearCache and rebuildCache complete without error', () async {
      service.clearCache();
      final result = await service.rebuildCache();
      expect(result, isA<Ok>());
    });
  });
}
