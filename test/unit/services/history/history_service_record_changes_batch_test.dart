import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/history/history_change_entry.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late HistoryServiceImpl service;
  late TranslationVersionHistoryRepository historyRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    historyRepo = TranslationVersionHistoryRepository();
    service = HistoryServiceImpl(
      historyRepository: historyRepo,
      versionRepository: TranslationVersionRepository(),
    );
  });

  tearDown(() => TestDatabase.close(db));

  group('recordChangesBatch', () {
    test('returns Ok and writes zero rows for empty list', () async {
      final result = await service.recordChangesBatch([]);
      expect(result.isOk, isTrue);
      final rows = await db.query('translation_version_history');
      expect(rows, isEmpty);
    });

    test('writes one row per entry and returns Ok', () async {
      final entries = List.generate(
        50,
        (i) => HistoryChangeEntry(
          versionId: 'v-$i',
          translatedText: 't-$i',
          status: 'translated',
          changedBy: 'tm_exact',
          changeReason: 'TM exact match (100% similarity)',
        ),
      );

      final result = await service.recordChangesBatch(entries);
      expect(result.isOk, isTrue);

      final rows = await db.query('translation_version_history',
          orderBy: 'version_id ASC');
      expect(rows, hasLength(50));
      expect(rows.first['changed_by'], 'tm_exact');
      expect(rows.first['change_reason'], contains('TM exact match'));
    });
  });
}
