import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/deepl_glossary_mapping.dart';
import 'package:twmt/services/glossary/models/glossary.dart';

import '../../helpers/fakes/fake_logger.dart';
import '../../helpers/test_database.dart';

// Additional coverage for GlossaryRepository, targeting methods/branches not
// exercised by glossary_repository_test.dart or glossary_repository_resync_test.dart:
//   getGlossariesByIds, updateEntry, deleteEntry, searchEntries target-language
//   branch, getUsageStats empty case, getEntriesByGlossary ordering branch,
//   getEntryCountForLanguage, countByTargetLanguageId (Result), and the DeepL
//   mapping CRUD: getAllDeepLMappings, insertDeepLMapping (incl. replace),
//   updateDeepLMapping, deleteDeepLMapping(byId), deleteDeepLMappingByDeepLId.
//
// Glossary-module convention: *_at columns are SECONDS; created_at <= updated_at
// (a CHECK constraint enforces this even with FK OFF). Small base timestamps are
// used where ordering matters.
void main() {
  late Database db;
  late GlossaryRepository repository;

  // Small, internally-coherent base timestamp in seconds.
  const base = 1000;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = GlossaryRepository(logger: FakeLogger());
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Glossary glossary({
    String id = 'glossary-id',
    String name = 'Test Glossary',
    String? description,
    String gameCode = 'wh3',
    String targetLanguageId = 'lang_en',
    int createdAt = base,
    int updatedAt = base,
  }) {
    return Glossary(
      id: id,
      name: name,
      description: description,
      gameCode: gameCode,
      targetLanguageId: targetLanguageId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  GlossaryEntry entry({
    String id = 'entry-id',
    String glossaryId = 'glossary-id',
    String targetLanguageCode = 'fr',
    String? sourceTerm,
    String targetTerm = 'Bonjour',
    bool caseSensitive = false,
    String? notes,
    int createdAt = base,
    int updatedAt = base,
  }) {
    // UNIQUE(glossary_id, target_language_code, source_term, case_sensitive):
    // derive source_term from id when defaulted so distinct ids stay distinct.
    return GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm ?? 'Hello-$id',
      targetTerm: targetTerm,
      caseSensitive: caseSensitive,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  DeepLGlossaryMapping mapping({
    String id = 'mapping-1',
    String twmtGlossaryId = 'glossary-id',
    String sourceLanguageCode = 'en',
    String targetLanguageCode = 'fr',
    String deeplGlossaryId = 'deepl-1',
    String deeplGlossaryName = 'Test_en_fr',
    int entryCount = 0,
    String syncStatus = 'synced',
    int syncedAt = base,
    int createdAt = base,
    int updatedAt = base,
  }) {
    return DeepLGlossaryMapping(
      id: id,
      twmtGlossaryId: twmtGlossaryId,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
      deeplGlossaryId: deeplGlossaryId,
      deeplGlossaryName: deeplGlossaryName,
      entryCount: entryCount,
      syncStatus: syncStatus,
      syncedAt: syncedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('GlossaryRepository (additional coverage)', () {
    group('getGlossariesByIds', () {
      test('returns matching glossaries with entry counts', () async {
        await repository.insertGlossary(
          glossary(id: 'g1', name: 'G1', gameCode: 'wh3', targetLanguageId: 'lang_fr'),
        );
        await repository.insertGlossary(
          glossary(id: 'g2', name: 'G2', gameCode: 'wh2', targetLanguageId: 'lang_fr'),
        );
        await repository.insertGlossary(
          glossary(id: 'g3', name: 'G3', gameCode: 'wh3', targetLanguageId: 'lang_de'),
        );
        await repository.insertEntry(entry(id: 'e1', glossaryId: 'g1'));
        await repository.insertEntry(entry(id: 'e2', glossaryId: 'g1'));

        final result = await repository.getGlossariesByIds(['g1', 'g3']);

        expect(result.map((g) => g.id).toSet(), equals({'g1', 'g3'}));
        final g1 = result.firstWhere((g) => g.id == 'g1');
        expect(g1.entryCount, equals(2));
        final g3 = result.firstWhere((g) => g.id == 'g3');
        expect(g3.entryCount, equals(0));
      });

      test('returns empty list for empty ids (early return)', () async {
        await repository.insertGlossary(glossary(id: 'g1'));

        final result = await repository.getGlossariesByIds([]);

        expect(result, isEmpty);
      });

      test('skips ids that do not exist', () async {
        await repository.insertGlossary(glossary(id: 'g1'));

        final result = await repository.getGlossariesByIds(['g1', 'missing']);

        expect(result.map((g) => g.id), equals(['g1']));
      });
    });

    group('updateEntry', () {
      test('persists changes to an existing entry', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(entry(id: 'e1', targetTerm: 'Bonjour'));

        final updated = entry(id: 'e1', targetTerm: 'Salut', notes: 'informal');
        await repository.updateEntry(updated);

        final stored = await repository.getEntryById('e1');
        expect(stored, isNotNull);
        expect(stored!.targetTerm, equals('Salut'));
        expect(stored.notes, equals('informal'));
      });

      test('is a no-op when no entry matches the id (no throw)', () async {
        await repository.insertGlossary(glossary());

        // database.update returns 0 rows; updateEntry returns Future<void>
        // without surfacing a not-found error.
        await repository.updateEntry(entry(id: 'missing'));

        final stored = await repository.getEntryById('missing');
        expect(stored, isNull);
      });
    });

    group('deleteEntry', () {
      test('removes the entry', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(entry(id: 'e1'));

        await repository.deleteEntry('e1');

        final stored = await repository.getEntryById('e1');
        expect(stored, isNull);
      });

      test('is a no-op for a non-existent id (no throw)', () async {
        await repository.insertGlossary(glossary());

        await repository.deleteEntry('missing');

        final rows = await db.query('glossary_entries');
        expect(rows, isEmpty);
      });
    });

    group('searchEntries target-language branch', () {
      test('filters by targetLanguageCode', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(
          entry(id: 'e-fr', targetLanguageCode: 'fr', sourceTerm: 'Sword'),
        );
        await repository.insertEntry(
          entry(id: 'e-de', targetLanguageCode: 'de', sourceTerm: 'Sword'),
        );

        final result = await repository.searchEntries(
          query: 'Sword',
          targetLanguageCode: 'fr',
        );

        expect(result, hasLength(1));
        expect(result.first.id, equals('e-fr'));
        expect(result.first.targetLanguageCode, equals('fr'));
      });

      test('returns empty when nothing matches the query', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(entry(id: 'e1', sourceTerm: 'Sword'));

        final result = await repository.searchEntries(query: 'Nonexistent');

        expect(result, isEmpty);
      });
    });

    group('getEntriesByGlossary ordering branch', () {
      test('orders by source_term ASC with no language filter', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(entry(id: 'e1', sourceTerm: 'Zebra'));
        await repository.insertEntry(entry(id: 'e2', sourceTerm: 'Apple'));
        await repository.insertEntry(entry(id: 'e3', sourceTerm: 'Mango'));

        final result = await repository.getEntriesByGlossary(glossaryId: 'glossary-id');

        expect(
          result.map((e) => e.sourceTerm),
          equals(['Apple', 'Mango', 'Zebra']),
        );
      });

      test('returns empty list for a glossary with no entries', () async {
        await repository.insertGlossary(glossary());

        final result = await repository.getEntriesByGlossary(glossaryId: 'glossary-id');

        expect(result, isEmpty);
      });
    });

    group('getUsageStats edge', () {
      test('returns all-zero stats for a glossary with no entries', () async {
        await repository.insertGlossary(glossary());

        final stats = await repository.getUsageStats('glossary-id');

        expect(stats['usedCount'], equals(0));
        expect(stats['unusedCount'], equals(0));
        expect(stats['totalUsage'], equals(0));
      });
    });

    group('getEntryCountForLanguage', () {
      test('counts entries for the language pair case-insensitively', () async {
        await repository.insertGlossary(glossary());
        await repository.insertEntry(
          entry(id: 'e1', targetLanguageCode: 'FR', sourceTerm: 'A'),
        );
        await repository.insertEntry(
          entry(id: 'e2', targetLanguageCode: 'fr', sourceTerm: 'B'),
        );
        await repository.insertEntry(
          entry(id: 'e3', targetLanguageCode: 'de', sourceTerm: 'C'),
        );

        final count = await repository.getEntryCountForLanguage(
          glossaryId: 'glossary-id',
          targetLanguageCode: 'fr',
        );

        expect(count, equals(2));
      });

      test('returns zero when nothing matches', () async {
        await repository.insertGlossary(glossary());

        final count = await repository.getEntryCountForLanguage(
          glossaryId: 'glossary-id',
          targetLanguageCode: 'fr',
        );

        expect(count, equals(0));
      });
    });

    group('countByTargetLanguageId', () {
      test('returns the count of glossaries for a language id', () async {
        await repository.insertGlossary(
          glossary(id: 'g1', gameCode: 'wh3', targetLanguageId: 'lang_fr'),
        );
        await repository.insertGlossary(
          glossary(id: 'g2', gameCode: 'wh2', targetLanguageId: 'lang_fr'),
        );
        await repository.insertGlossary(
          glossary(id: 'g3', gameCode: 'wh3', targetLanguageId: 'lang_de'),
        );

        final result = await repository.countByTargetLanguageId('lang_fr');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('returns zero (Ok) when no glossary uses the language', () async {
        final result = await repository.countByTargetLanguageId('lang_unused');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('DeepL mapping CRUD', () {
      setUp(() async {
        await repository.insertGlossary(glossary());
      });

      group('insertDeepLMapping', () {
        test('inserts a mapping retrievable via getDeepLMapping', () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm1', deeplGlossaryId: 'deepl-aaa', entryCount: 3),
          );

          final stored = await repository.getDeepLMapping(
            twmtGlossaryId: 'glossary-id',
            sourceLanguageCode: 'en',
            targetLanguageCode: 'fr',
          );
          expect(stored, isNotNull);
          expect(stored!.deeplGlossaryId, equals('deepl-aaa'));
          expect(stored.entryCount, equals(3));
        });

        test('replaces an existing row on id conflict (ConflictAlgorithm.replace)',
            () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm1', deeplGlossaryId: 'deepl-old', entryCount: 1),
          );
          await repository.insertDeepLMapping(
            mapping(id: 'm1', deeplGlossaryId: 'deepl-new', entryCount: 9),
          );

          final rows = await db.query('deepl_glossary_mappings');
          expect(rows, hasLength(1));
          expect(rows.first['deepl_glossary_id'], equals('deepl-new'));
          expect(rows.first['entry_count'], equals(9));
        });
      });

      group('updateDeepLMapping', () {
        test('updates an existing mapping by id', () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm1', entryCount: 2, syncStatus: 'pending'),
          );

          final updated = mapping(
            id: 'm1',
            entryCount: 7,
            syncStatus: 'synced',
            deeplGlossaryName: 'Renamed_en_fr',
          );
          await repository.updateDeepLMapping(updated);

          final stored = await repository.getDeepLMapping(
            twmtGlossaryId: 'glossary-id',
            sourceLanguageCode: 'en',
            targetLanguageCode: 'fr',
          );
          expect(stored, isNotNull);
          expect(stored!.entryCount, equals(7));
          expect(stored.syncStatus, equals('synced'));
          expect(stored.deeplGlossaryName, equals('Renamed_en_fr'));
        });

        test('is a no-op when no mapping matches the id', () async {
          await repository.updateDeepLMapping(mapping(id: 'missing'));

          final rows = await db.query('deepl_glossary_mappings');
          expect(rows, isEmpty);
        });
      });

      group('getAllDeepLMappings', () {
        test('returns all mappings ordered by synced_at DESC', () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm-old', targetLanguageCode: 'fr', deeplGlossaryId: 'd-old', syncedAt: base),
          );
          await repository.insertDeepLMapping(
            mapping(id: 'm-new', targetLanguageCode: 'de', deeplGlossaryId: 'd-new', syncedAt: base + 100),
          );

          final all = await repository.getAllDeepLMappings();

          expect(all.map((m) => m.id), equals(['m-new', 'm-old']));
        });

        test('returns empty list when there are no mappings', () async {
          final all = await repository.getAllDeepLMappings();

          expect(all, isEmpty);
        });
      });

      group('deleteDeepLMapping (by id)', () {
        test('deletes only the matching mapping', () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm1', targetLanguageCode: 'fr', deeplGlossaryId: 'd1'),
          );
          await repository.insertDeepLMapping(
            mapping(id: 'm2', targetLanguageCode: 'de', deeplGlossaryId: 'd2'),
          );

          await repository.deleteDeepLMapping('m1');

          final remaining = await repository.getAllDeepLMappings();
          expect(remaining.map((m) => m.id), equals(['m2']));
        });

        test('is a no-op for a non-existent id', () async {
          await repository.insertDeepLMapping(mapping(id: 'm1'));

          await repository.deleteDeepLMapping('missing');

          final remaining = await repository.getAllDeepLMappings();
          expect(remaining, hasLength(1));
        });
      });

      group('deleteDeepLMappingByDeepLId', () {
        test('deletes the mapping with the matching deepl_glossary_id', () async {
          await repository.insertDeepLMapping(
            mapping(id: 'm1', targetLanguageCode: 'fr', deeplGlossaryId: 'deepl-keep'),
          );
          await repository.insertDeepLMapping(
            mapping(id: 'm2', targetLanguageCode: 'de', deeplGlossaryId: 'deepl-drop'),
          );

          await repository.deleteDeepLMappingByDeepLId('deepl-drop');

          final remaining = await repository.getAllDeepLMappings();
          expect(remaining.map((m) => m.deeplGlossaryId), equals(['deepl-keep']));
        });

        test('is a no-op when no mapping has the DeepL id', () async {
          await repository.insertDeepLMapping(mapping(id: 'm1', deeplGlossaryId: 'deepl-1'));

          await repository.deleteDeepLMappingByDeepLId('deepl-unknown');

          final remaining = await repository.getAllDeepLMappings();
          expect(remaining, hasLength(1));
        });
      });
    });
  });
}
