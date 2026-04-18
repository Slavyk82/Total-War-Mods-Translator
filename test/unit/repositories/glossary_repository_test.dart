import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/shared/logging_service.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late GlossaryRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = GlossaryRepository(logger: LoggingService.instance);
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('GlossaryRepository', () {
    Glossary createTestGlossary({
      String? id,
      String? name,
      String? description,
      bool? isGlobal,
      String? gameInstallationId,
      String? targetLanguageId,
      int? createdAt,
      int? updatedAt,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return Glossary(
        id: id ?? 'glossary-id',
        name: name ?? 'Test Glossary',
        description: description,
        isGlobal: isGlobal ?? true,
        gameInstallationId: gameInstallationId,
        // schema requires target_language_id NOT NULL; domain model still
        // keeps it nullable. Tests must provide a value explicitly.
        targetLanguageId: targetLanguageId ?? 'lang_en',
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
      );
    }

    GlossaryEntry createTestEntry({
      String? id,
      String? glossaryId,
      String? targetLanguageCode,
      String? sourceTerm,
      String? targetTerm,
      bool? caseSensitive,
      String? notes,
      int? createdAt,
      int? updatedAt,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final resolvedId = id ?? 'entry-id';
      return GlossaryEntry(
        id: resolvedId,
        glossaryId: glossaryId ?? 'glossary-id',
        targetLanguageCode: targetLanguageCode ?? 'fr',
        // schema enforces UNIQUE(glossary_id, target_language_code,
        // source_term, case_sensitive); derive source_term from id when
        // callers leave it defaulted so distinct ids stay distinct rows.
        sourceTerm: sourceTerm ?? 'Hello-$resolvedId',
        targetTerm: targetTerm ?? 'Bonjour',
        caseSensitive: caseSensitive ?? false,
        notes: notes,
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
      );
    }

    group('Glossary CRUD', () {
      group('insertGlossary', () {
        test('should insert a glossary successfully', () async {
          final glossary = createTestGlossary();

          await repository.insertGlossary(glossary);

          final result = await repository.getGlossaryById(glossary.id);
          expect(result, isNotNull);
          expect(result!.name, equals('Test Glossary'));
        });

        test('should fail when inserting duplicate name', () async {
          final glossary1 = createTestGlossary(id: 'g1');
          final glossary2 = createTestGlossary(id: 'g2');

          await repository.insertGlossary(glossary1);

          expect(
            () => repository.insertGlossary(glossary2),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('getGlossaryById', () {
        test('should return glossary with entry count', () async {
          final glossary = createTestGlossary();
          await repository.insertGlossary(glossary);

          // Add some entries
          final entry1 = createTestEntry(id: 'e1', glossaryId: glossary.id);
          final entry2 = createTestEntry(id: 'e2', glossaryId: glossary.id);
          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          final result = await repository.getGlossaryById(glossary.id);

          expect(result, isNotNull);
          expect(result!.entryCount, equals(2));
        });

        test('should return null when glossary not found', () async {
          final result = await repository.getGlossaryById('non-existent');

          expect(result, isNull);
        });
      });

      group('getByName', () {
        test('should return glossary by name', () async {
          final glossary = createTestGlossary(name: 'Unique Name');
          await repository.insertGlossary(glossary);

          final result = await repository.getByName('Unique Name');

          expect(result, isNotNull);
          expect(result!.name, equals('Unique Name'));
        });

        test('should return null when name not found', () async {
          final result = await repository.getByName('non-existent');

          expect(result, isNull);
        });
      });

      group('getAllGlossaries', () {
        test('should return all glossaries', () async {
          final g1 = createTestGlossary(id: 'g1', name: 'Glossary 1', isGlobal: true);
          final g2 = createTestGlossary(id: 'g2', name: 'Glossary 2', isGlobal: false, gameInstallationId: 'game-1');

          await repository.insertGlossary(g1);
          await repository.insertGlossary(g2);

          final result = await repository.getAllGlossaries();

          expect(result.length, equals(2));
        });

        test('should filter by game installation', () async {
          final universal = createTestGlossary(id: 'g1', name: 'Universal', isGlobal: true);
          final gameSpecific = createTestGlossary(
            id: 'g2',
            name: 'Game Specific',
            isGlobal: false,
            gameInstallationId: 'game-1',
          );
          final otherGame = createTestGlossary(
            id: 'g3',
            name: 'Other Game',
            isGlobal: false,
            gameInstallationId: 'game-2',
          );

          await repository.insertGlossary(universal);
          await repository.insertGlossary(gameSpecific);
          await repository.insertGlossary(otherGame);

          final result = await repository.getAllGlossaries(gameInstallationId: 'game-1');

          expect(result.length, equals(2)); // Universal + game-1 specific
        });

        test('should exclude universal when requested', () async {
          final universal = createTestGlossary(id: 'g1', name: 'Universal', isGlobal: true);
          final gameSpecific = createTestGlossary(
            id: 'g2',
            name: 'Game Specific',
            isGlobal: false,
            gameInstallationId: 'game-1',
          );

          await repository.insertGlossary(universal);
          await repository.insertGlossary(gameSpecific);

          final result = await repository.getAllGlossaries(
            gameInstallationId: 'game-1',
            includeUniversal: false,
          );

          expect(result.length, equals(1));
          expect(result.first.name, equals('Game Specific'));
        });
      });

      group('updateGlossary', () {
        test('should update glossary successfully', () async {
          final glossary = createTestGlossary();
          await repository.insertGlossary(glossary);

          final updated = glossary.copyWith(description: 'Updated description');
          await repository.updateGlossary(updated);

          final result = await repository.getGlossaryById(glossary.id);
          expect(result!.description, equals('Updated description'));
        });
      });

      group('deleteGlossary', () {
        test('should delete glossary', () async {
          final glossary = createTestGlossary();
          await repository.insertGlossary(glossary);

          await repository.deleteGlossary(glossary.id);

          final result = await repository.getGlossaryById(glossary.id);
          expect(result, isNull);
        });
      });
    });

    group('GlossaryEntry CRUD', () {
      setUp(() async {
        // Insert a glossary first
        final glossary = createTestGlossary();
        await repository.insertGlossary(glossary);
      });

      group('insert (BaseRepository)', () {
        test('should insert entry successfully', () async {
          final entry = createTestEntry();

          final result = await repository.insert(entry);

          expect(result.isOk, isTrue);
          expect(result.value.sourceTerm, equals(entry.sourceTerm));
        });
      });

      group('insertEntry', () {
        test('should insert entry successfully', () async {
          final entry = createTestEntry();

          await repository.insertEntry(entry);

          final result = await repository.getEntryById(entry.id);
          expect(result, isNotNull);
          expect(result!.sourceTerm, equals(entry.sourceTerm));
        });
      });

      group('getById', () {
        test('should return entry when found', () async {
          final entry = createTestEntry();
          await repository.insertEntry(entry);

          final result = await repository.getById(entry.id);

          expect(result.isOk, isTrue);
          expect(result.value.id, equals(entry.id));
        });

        test('should return error when not found', () async {
          final result = await repository.getById('non-existent');

          expect(result.isErr, isTrue);
        });
      });

      group('getAll', () {
        test('should return all entries ordered by source_term', () async {
          final entry1 = createTestEntry(id: 'e1', sourceTerm: 'Zebra');
          final entry2 = createTestEntry(id: 'e2', sourceTerm: 'Apple');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          final result = await repository.getAll();

          expect(result.isOk, isTrue);
          expect(result.value.length, equals(2));
          expect(result.value[0].sourceTerm, equals('Apple'));
          expect(result.value[1].sourceTerm, equals('Zebra'));
        });
      });

      group('update', () {
        test('should update entry successfully', () async {
          final entry = createTestEntry();
          await repository.insertEntry(entry);

          final updated = entry.copyWith(targetTerm: 'Salut');
          final result = await repository.update(updated);

          expect(result.isOk, isTrue);
          expect(result.value.targetTerm, equals('Salut'));
        });
      });

      group('delete', () {
        test('should delete entry successfully', () async {
          final entry = createTestEntry();
          await repository.insertEntry(entry);

          final result = await repository.delete(entry.id);

          expect(result.isOk, isTrue);

          final getResult = await repository.getById(entry.id);
          expect(getResult.isErr, isTrue);
        });
      });

      group('getEntriesByGlossary', () {
        test('should return entries for glossary', () async {
          final entry1 = createTestEntry(id: 'e1', glossaryId: 'glossary-id');
          final entry2 = createTestEntry(id: 'e2', glossaryId: 'glossary-id');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          final result = await repository.getEntriesByGlossary(glossaryId: 'glossary-id');

          expect(result.length, equals(2));
        });

        test('should filter by target language code', () async {
          final frenchEntry = createTestEntry(id: 'e1', targetLanguageCode: 'fr');
          final germanEntry = createTestEntry(id: 'e2', targetLanguageCode: 'de');

          await repository.insertEntry(frenchEntry);
          await repository.insertEntry(germanEntry);

          final result = await repository.getEntriesByGlossary(
            glossaryId: 'glossary-id',
            targetLanguageCode: 'fr',
          );

          expect(result.length, equals(1));
          expect(result.first.targetLanguageCode, equals('fr'));
        });
      });

      group('findDuplicateEntry', () {
        test('should find duplicate entry', () async {
          final entry = createTestEntry(
            sourceTerm: 'Hello',
            targetLanguageCode: 'fr',
          );
          await repository.insertEntry(entry);

          final duplicate = await repository.findDuplicateEntry(
            glossaryId: 'glossary-id',
            targetLanguageCode: 'fr',
            sourceTerm: 'Hello',
          );

          expect(duplicate, isNotNull);
          expect(duplicate!.id, equals(entry.id));
        });

        test('should return null when no duplicate', () async {
          final duplicate = await repository.findDuplicateEntry(
            glossaryId: 'glossary-id',
            targetLanguageCode: 'fr',
            sourceTerm: 'NonExistent',
          );

          expect(duplicate, isNull);
        });
      });

      group('searchEntries', () {
        test('should search in source term', () async {
          final entry1 = createTestEntry(id: 'e1', sourceTerm: 'Hello World');
          final entry2 = createTestEntry(id: 'e2', sourceTerm: 'Goodbye');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          final result = await repository.searchEntries(query: 'Hello');

          expect(result.length, equals(1));
          expect(result.first.sourceTerm, contains('Hello'));
        });

        test('should search in target term', () async {
          final entry = createTestEntry(targetTerm: 'Bonjour le monde');
          await repository.insertEntry(entry);

          final result = await repository.searchEntries(query: 'monde');

          expect(result.length, equals(1));
        });

        test('should filter by glossary IDs', () async {
          // Create second glossary
          final g2 = createTestGlossary(id: 'glossary-2', name: 'Glossary 2');
          await repository.insertGlossary(g2);

          final entry1 = createTestEntry(id: 'e1', glossaryId: 'glossary-id', sourceTerm: 'Test');
          final entry2 = createTestEntry(id: 'e2', glossaryId: 'glossary-2', sourceTerm: 'Test');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          final result = await repository.searchEntries(
            query: 'Test',
            glossaryIds: ['glossary-id'],
          );

          expect(result.length, equals(1));
          expect(result.first.glossaryId, equals('glossary-id'));
        });
      });

      group('getEntryCount', () {
        test('should return correct count', () async {
          final entry1 = createTestEntry(id: 'e1');
          final entry2 = createTestEntry(id: 'e2');
          final entry3 = createTestEntry(id: 'e3');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);
          await repository.insertEntry(entry3);

          final count = await repository.getEntryCount('glossary-id');

          expect(count, equals(3));
        });

        test('should return zero for empty glossary', () async {
          final count = await repository.getEntryCount('glossary-id');

          expect(count, equals(0));
        });
      });

      group('incrementUsageCount', () {
        test('should increment usage count for entries', () async {
          final entry1 = createTestEntry(id: 'e1');
          final entry2 = createTestEntry(id: 'e2');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          await repository.incrementUsageCount(['e1', 'e2']);

          // Verify usage count increased
          final maps = await db.query('glossary_entries', where: 'id = ?', whereArgs: ['e1']);
          expect(maps.first['usage_count'], equals(1));
        });

        test('should handle empty list', () async {
          // Should not throw
          await repository.incrementUsageCount([]);
        });
      });

      group('getUsageStats', () {
        test('should return usage statistics', () async {
          final entry1 = createTestEntry(id: 'e1');
          final entry2 = createTestEntry(id: 'e2');

          await repository.insertEntry(entry1);
          await repository.insertEntry(entry2);

          // Increment usage for one entry
          await repository.incrementUsageCount(['e1']);
          await repository.incrementUsageCount(['e1']);

          final stats = await repository.getUsageStats('glossary-id');

          expect(stats['usedCount'], equals(1));
          expect(stats['unusedCount'], equals(1));
          expect(stats['totalUsage'], equals(2));
        });
      });
    });

    group('getByProjectAndLanguage', () {
      test(
          'returns global + game-installation-scoped entries filtered by language',
          () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // project-a lives under game-1; project-b under game-2.
        await db.insert('projects', {
          'id': 'project-a',
          'name': 'Project A',
          'game_installation_id': 'game-1',
          'batch_size': 25,
          'parallel_batches': 3,
          'created_at': now,
          'updated_at': now,
        });
        await db.insert('projects', {
          'id': 'project-b',
          'name': 'Project B',
          'game_installation_id': 'game-2',
          'batch_size': 25,
          'parallel_batches': 3,
          'created_at': now,
          'updated_at': now,
        });

        // Three glossaries: global, game-1, game-2.
        final globalGlossary = createTestGlossary(
          id: 'g-global',
          name: 'Global',
          isGlobal: true,
        );
        final game1Glossary = createTestGlossary(
          id: 'g-game1',
          name: 'Game 1',
          isGlobal: false,
          gameInstallationId: 'game-1',
        );
        final game2Glossary = createTestGlossary(
          id: 'g-game2',
          name: 'Game 2',
          isGlobal: false,
          gameInstallationId: 'game-2',
        );
        await repository.insertGlossary(globalGlossary);
        await repository.insertGlossary(game1Glossary);
        await repository.insertGlossary(game2Glossary);

        // Entries: one FR in each glossary, one DE in game-1.
        await repository.insertEntry(createTestEntry(
          id: 'e-global-fr',
          glossaryId: 'g-global',
          targetLanguageCode: 'fr',
          sourceTerm: 'Hello',
        ));
        await repository.insertEntry(createTestEntry(
          id: 'e-game1-fr',
          glossaryId: 'g-game1',
          targetLanguageCode: 'fr',
          sourceTerm: 'World',
        ));
        await repository.insertEntry(createTestEntry(
          id: 'e-game1-de',
          glossaryId: 'g-game1',
          targetLanguageCode: 'de',
          sourceTerm: 'German',
        ));
        await repository.insertEntry(createTestEntry(
          id: 'e-game2-fr',
          glossaryId: 'g-game2',
          targetLanguageCode: 'fr',
          sourceTerm: 'Other',
        ));

        final result = await repository.getByProjectAndLanguage(
          projectId: 'project-a',
          targetLanguageCode: 'fr',
        );

        expect(result.isOk, isTrue);
        final entries = result.value;
        final ids = entries.map((e) => e.id).toSet();
        // Includes global + game-1 FR entries; excludes game-1 DE entry
        // (wrong language) and game-2 FR entry (wrong game installation).
        expect(ids, equals({'e-global-fr', 'e-game1-fr'}));
      });

      test('matches language code case-insensitively', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('projects', {
          'id': 'project-a',
          'name': 'Project A',
          'game_installation_id': 'game-1',
          'batch_size': 25,
          'parallel_batches': 3,
          'created_at': now,
          'updated_at': now,
        });
        await repository.insertGlossary(
            createTestGlossary(id: 'g-global', name: 'Global', isGlobal: true));
        await repository.insertEntry(createTestEntry(
          id: 'e1',
          glossaryId: 'g-global',
          targetLanguageCode: 'FR',
        ));

        final result = await repository.getByProjectAndLanguage(
          projectId: 'project-a',
          targetLanguageCode: 'fr',
        );

        expect(result.isOk, isTrue);
        expect(result.value, hasLength(1));
      });

      test('returns empty list when project has no matching glossary',
          () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('projects', {
          'id': 'project-a',
          'name': 'Project A',
          'game_installation_id': 'game-1',
          'batch_size': 25,
          'parallel_batches': 3,
          'created_at': now,
          'updated_at': now,
        });

        final result = await repository.getByProjectAndLanguage(
          projectId: 'project-a',
          targetLanguageCode: 'fr',
        );

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('DeepL Glossary Mappings', () {
      setUp(() async {
        final glossary = createTestGlossary();
        await repository.insertGlossary(glossary);
      });

      test('should insert and retrieve DeepL mapping', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('deepl_glossary_mappings', {
          'id': 'mapping-1',
          'twmt_glossary_id': 'glossary-id',
          'deepl_glossary_id': 'deepl-123',
          'deepl_glossary_name': 'Test Glossary EN-FR',
          'source_language_code': 'en',
          'target_language_code': 'fr',
          'entry_count': 5,
          'sync_status': 'synced',
          'synced_at': now,
          'created_at': now,
          'updated_at': now,
        });

        final mapping = await repository.getDeepLMapping(
          twmtGlossaryId: 'glossary-id',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        expect(mapping, isNotNull);
        expect(mapping!.deeplGlossaryId, equals('deepl-123'));
      });

      test('should return null for non-existent mapping', () async {
        final mapping = await repository.getDeepLMapping(
          twmtGlossaryId: 'glossary-id',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        expect(mapping, isNull);
      });

      test('should get all mappings for glossary', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('deepl_glossary_mappings', {
          'id': 'mapping-1',
          'twmt_glossary_id': 'glossary-id',
          'deepl_glossary_id': 'deepl-1',
          'deepl_glossary_name': 'Test Glossary EN-FR',
          'source_language_code': 'en',
          'target_language_code': 'fr',
          'entry_count': 5,
          'sync_status': 'synced',
          'synced_at': now,
          'created_at': now,
          'updated_at': now,
        });
        await db.insert('deepl_glossary_mappings', {
          'id': 'mapping-2',
          'twmt_glossary_id': 'glossary-id',
          'deepl_glossary_id': 'deepl-2',
          'deepl_glossary_name': 'Test Glossary EN-DE',
          'source_language_code': 'en',
          'target_language_code': 'de',
          'entry_count': 3,
          'sync_status': 'synced',
          'synced_at': now,
          'created_at': now,
          'updated_at': now,
        });

        final mappings = await repository.getDeepLMappingsForGlossary('glossary-id');

        expect(mappings.length, equals(2));
      });

      test('should delete all mappings for glossary', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('deepl_glossary_mappings', {
          'id': 'mapping-1',
          'twmt_glossary_id': 'glossary-id',
          'deepl_glossary_id': 'deepl-1',
          'deepl_glossary_name': 'Test Glossary EN-FR',
          'source_language_code': 'en',
          'target_language_code': 'fr',
          'entry_count': 5,
          'sync_status': 'synced',
          'synced_at': now,
          'created_at': now,
          'updated_at': now,
        });

        await repository.deleteDeepLMappingsForGlossary('glossary-id');

        final mappings = await repository.getDeepLMappingsForGlossary('glossary-id');
        expect(mappings, isEmpty);
      });

      test('should check if mapping needs resync', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Insert mapping synced 1 hour ago
        await db.insert('deepl_glossary_mappings', {
          'id': 'mapping-1',
          'twmt_glossary_id': 'glossary-id',
          'deepl_glossary_id': 'deepl-1',
          'deepl_glossary_name': 'Test Glossary EN-FR',
          'source_language_code': 'en',
          'target_language_code': 'fr',
          'entry_count': 5,
          'sync_status': 'synced',
          'synced_at': now - 3600,
          'created_at': now - 7200,
          'updated_at': now - 3600,
        });

        // Insert entry updated after sync
        await db.insert('glossary_entries', {
          'id': 'e1',
          'glossary_id': 'glossary-id',
          'target_language_code': 'fr',
          'source_term': 'New',
          'target_term': 'Nouveau',
          'case_sensitive': 0,
          'created_at': now,
          'updated_at': now,
        });

        final needsResync = await repository.doesMappingNeedResync(
          twmtGlossaryId: 'glossary-id',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        expect(needsResync, isTrue);
      });
    });

    group('Edge cases', () {
      test('should handle special characters in terms', () async {
        final glossary = createTestGlossary();
        await repository.insertGlossary(glossary);

        final entry = createTestEntry(
          sourceTerm: "Hero's Journey",
          targetTerm: "Le voyage du heros",
        );

        await repository.insertEntry(entry);

        final result = await repository.getEntryById(entry.id);
        expect(result!.sourceTerm, equals("Hero's Journey"));
      });

      test('should handle unicode characters', () async {
        final glossary = createTestGlossary();
        await repository.insertGlossary(glossary);

        final entry = createTestEntry(
          sourceTerm: 'Emperor',
          targetTerm: '\u7687\u5e1d', // Chinese characters
        );

        await repository.insertEntry(entry);

        final result = await repository.getEntryById(entry.id);
        expect(result!.targetTerm, equals('\u7687\u5e1d'));
      });
    });
  });
}
