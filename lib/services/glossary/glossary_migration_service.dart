import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Transaction;

import '../database/database_service.dart';
import 'models/pending_glossary_migration.dart';

export 'models/pending_glossary_migration.dart';

/// Detects and applies the one-shot migration from universal/duplicate
/// glossaries to strictly game-scoped glossaries.
class GlossaryMigrationService {
  GlossaryMigrationService();

  /// Returns non-null iff any universals exist or any (game_code, target_language_id)
  /// has more than one glossary.
  Future<PendingGlossaryMigration?> detectPendingMigration() async {
    final universals = await _queryUniversals();
    final duplicates = await _queryDuplicates();
    if (universals.isEmpty && duplicates.isEmpty) return null;
    return PendingGlossaryMigration(
      universals: universals,
      duplicates: duplicates,
    );
  }

  /// Applies the user's conversion choices, merges duplicates, and finalizes
  /// the schema in a single transaction.
  Future<void> applyMigration(MigrationPlan plan) async {
    // The schema rebuild inside the transaction needs `legacy_alter_table = 1`
    // for the same reason as [GlossaryGameCodePartialMigration] — the stale
    // `v_translations_needing_review` view references a non-existent column
    // and trips SQLite's full-schema validation during table rename. PRAGMA
    // must be toggled outside the transaction to avoid issues with
    // transactional pragma state.
    await DatabaseService.database.execute('PRAGMA legacy_alter_table = 1');
    try {
      await DatabaseService.database.transaction((txn) async {
        // 1. Apply user decisions on universals the user chose to convert.
        for (final entry in plan.conversions.entries) {
          final universalId = entry.key;
          final gameCode = entry.value;
          if (gameCode == null) {
            await txn.delete(
              'glossaries',
              where: 'id = ?',
              whereArgs: [universalId],
            );
            continue;
          }
          final uniRows = await txn.query(
            'glossaries',
            where: 'id = ?',
            whereArgs: [universalId],
            limit: 1,
          );
          if (uniRows.isEmpty) continue;
          final targetLanguageId = uniRows.first['target_language_id'] as String;
          final existingRows = await txn.query(
            'glossaries',
            where: 'game_code = ? AND target_language_id = ? AND id != ?',
            whereArgs: [gameCode, targetLanguageId, universalId],
            limit: 1,
          );
          if (existingRows.isEmpty) {
            await txn.update(
              'glossaries',
              {'game_code': gameCode, 'is_global': 0},
              where: 'id = ?',
              whereArgs: [universalId],
            );
          } else {
            await _mergeEntriesDedup(
              txn,
              sourceGlossaryId: universalId,
              survivorGlossaryId: existingRows.first['id'] as String,
            );
            await txn.delete(
              'glossaries',
              where: 'id = ?',
              whereArgs: [universalId],
            );
          }
        }

        // 2. Delete any remaining universals that were not mentioned in the plan.
        await txn.delete('glossaries', where: 'game_code IS NULL');

        // 3. Merge duplicate (game_code, target_language_id) groups. Survivor
        //    = member with smallest created_at (id tiebreak).
        final dupRows = await txn.rawQuery('''
          SELECT game_code, target_language_id
          FROM glossaries
          WHERE game_code IS NOT NULL
          GROUP BY game_code, target_language_id
          HAVING COUNT(*) > 1
        ''');
        for (final row in dupRows) {
          final members = await txn.query(
            'glossaries',
            columns: ['id'],
            where: 'game_code = ? AND target_language_id = ?',
            whereArgs: [row['game_code'], row['target_language_id']],
            orderBy: 'created_at ASC, id ASC',
          );
          final survivor = members.first['id'] as String;
          for (final m in members.skip(1)) {
            await _mergeEntriesDedup(
              txn,
              sourceGlossaryId: m['id'] as String,
              survivorGlossaryId: survivor,
            );
            await txn.delete(
              'glossaries',
              where: 'id = ?',
              whereArgs: [m['id']],
            );
          }
        }

        // 4. Finalize schema (same transaction).
        await _finalizeSchemaInTxn(txn);
      });
    } finally {
      await DatabaseService.database.execute('PRAGMA legacy_alter_table = 0');
    }
  }

  /// Rebuilds the `glossaries` table to enforce `game_code NOT NULL` and
  /// `UNIQUE(game_code, target_language_id)`, dropping the legacy
  /// `is_global` and `game_installation_id` columns. Idempotent.
  Future<void> finalizeSchema() async {
    await DatabaseService.database.execute('PRAGMA legacy_alter_table = 1');
    try {
      await DatabaseService.database.transaction(_finalizeSchemaInTxn);
    } finally {
      await DatabaseService.database.execute('PRAGMA legacy_alter_table = 0');
    }
  }

  Future<void> _mergeEntriesDedup(
    Transaction txn, {
    required String sourceGlossaryId,
    required String survivorGlossaryId,
  }) async {
    final sourceEntries = await txn.query(
      'glossary_entries',
      where: 'glossary_id = ?',
      whereArgs: [sourceGlossaryId],
    );
    for (final entry in sourceEntries) {
      final srcTermKey = (entry['source_term'] as String).trim().toLowerCase();
      final tlc = entry['target_language_code'] as String;
      final conflicting = await txn.rawQuery('''
        SELECT id, updated_at
        FROM glossary_entries
        WHERE glossary_id = ?
          AND LOWER(TRIM(source_term)) = ?
          AND LOWER(target_language_code) = LOWER(?)
        LIMIT 1
      ''', [survivorGlossaryId, srcTermKey, tlc]);
      if (conflicting.isEmpty) {
        await txn.update(
          'glossary_entries',
          {'glossary_id': survivorGlossaryId},
          where: 'id = ?',
          whereArgs: [entry['id']],
        );
      } else {
        final conflictUpdatedAt = (conflicting.first['updated_at'] as num).toInt();
        final entryUpdatedAt = (entry['updated_at'] as num).toInt();
        if (entryUpdatedAt > conflictUpdatedAt) {
          await txn.delete(
            'glossary_entries',
            where: 'id = ?',
            whereArgs: [conflicting.first['id']],
          );
          await txn.update(
            'glossary_entries',
            {'glossary_id': survivorGlossaryId},
            where: 'id = ?',
            whereArgs: [entry['id']],
          );
        } else {
          await txn.delete(
            'glossary_entries',
            where: 'id = ?',
            whereArgs: [entry['id']],
          );
        }
      }
    }
  }

  Future<void> _finalizeSchemaInTxn(Transaction txn) async {
    final cols = await txn.rawQuery('PRAGMA table_info(glossaries)');
    final hasIsGlobal = cols.any((c) => c['name'] == 'is_global');
    final hasGameInstallationId =
        cols.any((c) => c['name'] == 'game_installation_id');
    final indexes = await txn.rawQuery('PRAGMA index_list(glossaries)');
    final hasUniqueIndex =
        indexes.any((i) => i['name'] == 'glossaries_game_lang_uq');
    if (!hasIsGlobal && !hasGameInstallationId && hasUniqueIndex) {
      return; // already finalized
    }

    await txn.execute('''
      CREATE TABLE glossaries_final (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        game_code TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        CHECK (created_at <= updated_at)
      )
    ''');
    await txn.execute('''
      INSERT INTO glossaries_final
        (id, name, description, game_code, target_language_id, created_at, updated_at)
      SELECT id, name, description, game_code, target_language_id, created_at, updated_at
      FROM glossaries
    ''');
    await txn.execute('DROP TABLE glossaries');
    await txn.execute('ALTER TABLE glossaries_final RENAME TO glossaries');
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS glossaries_game_lang_uq
      ON glossaries(game_code, target_language_id)
    ''');
    // Recreate the remaining indexes and the updated_at trigger dropped with
    // the original table. The trigger body mirrors lib/database/schema.sql
    // lines 887-892 exactly.
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossaries_game ON glossaries(game_code)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossaries_target_language ON glossaries(target_language_id)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossaries_name ON glossaries(name)',
    );
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_glossaries_updated_at
      AFTER UPDATE ON glossaries
      WHEN NEW.updated_at = OLD.updated_at
      BEGIN
          UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');
  }

  Future<List<UniversalGlossaryInfo>> _queryUniversals() async {
    final rows = await DatabaseService.database.rawQuery('''
      SELECT g.id, g.name, g.description,
             g.target_language_id AS target_language_id,
             l.code AS target_language_code,
             COALESCE(COUNT(ge.id), 0) AS entry_count
      FROM glossaries g
      LEFT JOIN glossary_entries ge ON ge.glossary_id = g.id
      INNER JOIN languages l ON l.id = g.target_language_id
      WHERE g.game_code IS NULL
      GROUP BY g.id
      ORDER BY g.name ASC
    ''');
    return rows
        .map((r) => UniversalGlossaryInfo(
              id: r['id'] as String,
              name: r['name'] as String,
              description: r['description'] as String?,
              targetLanguageId: r['target_language_id'] as String,
              targetLanguageCode: r['target_language_code'] as String,
              entryCount: (r['entry_count'] as num).toInt(),
            ))
        .toList();
  }

  Future<List<DuplicateGlossaryGroup>> _queryDuplicates() async {
    // Find (game_code, target_language_id) pairs with > 1 glossary, then fetch
    // their members with entry counts. A two-step approach sidesteps SQLite
    // version differences around tuple IN expressions.
    final duplicateKeys = await DatabaseService.database.rawQuery('''
      SELECT game_code, target_language_id
      FROM glossaries
      WHERE game_code IS NOT NULL
      GROUP BY game_code, target_language_id
      HAVING COUNT(*) > 1
    ''');

    if (duplicateKeys.isEmpty) return [];

    final List<DuplicateGlossaryGroup> groups = [];
    for (final key in duplicateKeys) {
      final gameCode = key['game_code'] as String;
      final targetLanguageId = key['target_language_id'] as String;

      final memberRows = await DatabaseService.database.rawQuery('''
        SELECT g.id, g.name, g.created_at,
               l.code AS target_language_code,
               COALESCE(COUNT(ge.id), 0) AS entry_count
        FROM glossaries g
        INNER JOIN languages l ON l.id = g.target_language_id
        LEFT JOIN glossary_entries ge ON ge.glossary_id = g.id
        WHERE g.game_code = ? AND g.target_language_id = ?
        GROUP BY g.id
        ORDER BY g.created_at ASC, g.id ASC
      ''', [gameCode, targetLanguageId]);

      if (memberRows.isEmpty) continue;

      final targetLanguageCode =
          memberRows.first['target_language_code'] as String;
      final members = memberRows
          .map((r) => DuplicateGlossaryMember(
                id: r['id'] as String,
                name: r['name'] as String,
                entryCount: (r['entry_count'] as num).toInt(),
                createdAt: (r['created_at'] as num).toInt(),
              ))
          .toList();

      groups.add(DuplicateGlossaryGroup(
        gameCode: gameCode,
        targetLanguageId: targetLanguageId,
        targetLanguageCode: targetLanguageCode,
        members: members,
      ));
    }

    return groups;
  }
}
