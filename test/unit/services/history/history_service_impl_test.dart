import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/models/history/history_change_entry.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/history_service_impl.dart';

class _MockHistoryRepo extends Mock
    implements TranslationVersionHistoryRepository {}

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

TranslationVersionHistory _hist(
  String id,
  String versionId, {
  String text = 'txt',
  TranslationVersionStatus status = TranslationVersionStatus.translated,
  String changedBy = 'user1',
  String? reason,
  int createdAt = 100,
}) =>
    TranslationVersionHistory(
      id: id,
      versionId: versionId,
      translatedText: text,
      status: status,
      changedBy: changedBy,
      changeReason: reason,
      createdAt: createdAt,
    );

TranslationVersion _version(String id, {String? text}) => TranslationVersion(
      id: id,
      unitId: 'u',
      projectLanguageId: 'pl',
      translatedText: text,
      createdAt: 0,
      updatedAt: 0,
    );

Ok<T, TWMTDatabaseException> _ok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _err<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() {
    registerFallbackValue(_hist('f', 'v'));
    registerFallbackValue(_version('f'));
    registerFallbackValue(<TranslationVersionHistory>[]);
  });

  late _MockHistoryRepo history;
  late _MockVersionRepo versions;
  late HistoryServiceImpl service;

  setUp(() {
    history = _MockHistoryRepo();
    versions = _MockVersionRepo();
    service = HistoryServiceImpl(
      historyRepository: history,
      versionRepository: versions,
    );
  });

  group('recordChange', () {
    test('inserts a history row with the parsed status', () async {
      when(() => history.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationVersionHistory));

      final r = await service.recordChange(
        versionId: 'v1',
        translatedText: 'Bonjour',
        status: 'translated',
        changedBy: 'user1',
      );

      expect(r.isOk, isTrue);
      final row =
          verify(() => history.insert(captureAny())).captured.single as TranslationVersionHistory;
      expect(row.status, TranslationVersionStatus.translated);
      expect(row.translatedText, 'Bonjour');
    });

    test('an unknown status falls back to pending', () async {
      when(() => history.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationVersionHistory));

      await service.recordChange(
          versionId: 'v', translatedText: 't', status: 'bogus', changedBy: 'u');

      final row =
          verify(() => history.insert(captureAny())).captured.single as TranslationVersionHistory;
      expect(row.status, TranslationVersionStatus.pending);
    });

    test('propagates a repository error', () async {
      when(() => history.insert(any()))
          .thenAnswer((_) async => _err<TranslationVersionHistory>('db'));

      final r = await service.recordChange(
          versionId: 'v', translatedText: 't', status: 'translated', changedBy: 'u');
      expect(r.isErr, isTrue);
    });
  });

  group('recordChangesBatch', () {
    test('is a no-op for an empty list', () async {
      expect((await service.recordChangesBatch([])).isOk, isTrue);
      verifyNever(() => history.insertBatch(any()));
    });

    test('maps entries and inserts them as a batch', () async {
      when(() => history.insertBatch(any())).thenAnswer((_) async => _ok(null));

      final r = await service.recordChangesBatch([
        const HistoryChangeEntry(
            versionId: 'v', translatedText: 't', status: 'translated', changedBy: 'u'),
      ]);

      expect(r.isOk, isTrue);
      final rows = verify(() => history.insertBatch(captureAny())).captured.single
          as List<TranslationVersionHistory>;
      expect(rows, hasLength(1));
    });
  });

  group('simple delegations', () {
    test('getHistory delegates to the repo', () async {
      when(() => history.getByVersion('v'))
          .thenAnswer((_) async => _ok([_hist('h', 'v')]));
      expect((await service.getHistory('v')).unwrap(), hasLength(1));
    });

    test('cleanupOldHistory delegates to deleteOlderThan', () async {
      when(() => history.deleteOlderThan(any())).thenAnswer((_) async => _ok(5));
      expect((await service.cleanupOldHistory(olderThanDays: 30)).unwrap(), 5);
    });
  });

  group('compareVersions', () {
    test('errors when either history entry is missing', () async {
      when(() => history.getById('a')).thenAnswer((_) async => _ok(_hist('a', 'v')));
      when(() => history.getById('b'))
          .thenAnswer((_) async => _err<TranslationVersionHistory>('missing'));

      expect(
        (await service.compareVersions(historyId1: 'a', historyId2: 'b')).isErr,
        isTrue,
      );
    });

    test('builds a comparison with a diff for two entries', () async {
      when(() => history.getById('a'))
          .thenAnswer((_) async => _ok(_hist('a', 'v', text: 'Hello')));
      when(() => history.getById('b'))
          .thenAnswer((_) async => _ok(_hist('b', 'v', text: 'Hello World')));

      final r = await service.compareVersions(historyId1: 'a', historyId2: 'b');

      expect(r.isOk, isTrue);
      expect(r.unwrap().version1.id, 'a');
      expect(r.unwrap().version2.id, 'b');
    });
  });

  group('revertToVersion', () {
    test('rejects a history entry that belongs to another version', () async {
      when(() => history.getById('h'))
          .thenAnswer((_) async => _ok(_hist('h', 'OTHER')));

      final r = await service.revertToVersion(
          versionId: 'v', historyId: 'h', changedBy: 'u');
      expect(r.isErr, isTrue);
    });

    test('records before-state, updates the version, and records the revert',
        () async {
      when(() => history.getById('h')).thenAnswer((_) async =>
          _ok(_hist('h', 'v', text: 'OldText', status: TranslationVersionStatus.translated)));
      when(() => versions.getById('v'))
          .thenAnswer((_) async => _ok(_version('v', text: 'Current')));
      when(() => versions.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationVersion));
      when(() => history.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationVersionHistory));

      final r = await service.revertToVersion(
          versionId: 'v', historyId: 'h', changedBy: 'u');

      expect(r.isOk, isTrue);
      // Before-state + revert action => two history inserts.
      verify(() => history.insert(any())).called(2);
      final updated =
          verify(() => versions.update(captureAny())).captured.single as TranslationVersion;
      expect(updated.translatedText, 'OldText');
    });
  });

  group('getStatisticsForVersion', () {
    test('categorizes changes by attribution and counts reverts', () async {
      when(() => history.getByVersion('v')).thenAnswer((_) async => _ok([
            _hist('1', 'v', changedBy: 'system'),
            _hist('2', 'v', changedBy: 'provider_openai'),
            _hist('3', 'v', changedBy: 'alice'),
            _hist('4', 'v', changedBy: 'alice', reason: 'Reverted to version 1'),
          ]));

      final stats = (await service.getStatisticsForVersion('v')).unwrap();

      expect(stats.totalEntries, 4);
      expect(stats.systemChanges, 1);
      expect(stats.llmTranslations, 1);
      expect(stats.manualEdits, 2);
      expect(stats.reverts, 1);
      expect(stats.changesByLlm['openai'], 1);
      expect(stats.changesByUser['alice'], 2);
    });
  });

  group('getStatistics', () {
    test('aggregates attribution, total, time range and reverts', () async {
      when(() => history.getStatistics()).thenAnswer((_) async =>
          _ok(<String, int>{'system': 2, 'provider_deepl': 3, 'bob': 4}));
      when(() => history.count()).thenAnswer((_) async => _ok(9));
      when(() => history.getTimeRange()).thenAnswer(
          (_) async => _ok(<String, int?>{'newest': 200, 'oldest': 100}));
      when(() => history.countReverts()).thenAnswer((_) async => _ok(1));

      final stats = (await service.getStatistics()).unwrap();

      expect(stats.totalEntries, 9);
      expect(stats.systemChanges, 2);
      expect(stats.llmTranslations, 3);
      expect(stats.manualEdits, 4);
      expect(stats.reverts, 1);
      expect(stats.mostRecentChange, 200);
      expect(stats.oldestChange, 100);
    });
  });
}
