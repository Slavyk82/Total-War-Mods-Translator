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
