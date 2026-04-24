import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../service_locator.dart';
import '../shared/i_logging_service.dart';
import '../steam/models/game_definitions.dart';

/// Creates empty `(game_code, target_language_id)` glossaries on demand.
///
/// Called from three trigger sites:
/// - When a new game path is saved in settings → [provisionForGame].
/// - When a language is added to a project → [provisionForProjectLanguage].
/// - When `project_languages` rows are inserted (create-project, add-language,
///   game-translation, mod import) → [provisionForProject].
class GlossaryAutoProvisioningService {
  final ILoggingService _logger;
  static const _uuid = Uuid();

  GlossaryAutoProvisioningService({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Provision empty glossaries for every distinct target language used by
  /// projects of the given [gameCode] (joined via `game_installations`).
  /// Idempotent: languages already covered by an existing glossary are skipped.
  Future<void> provisionForGame(String gameCode) async {
    final rows = await DatabaseService.database.rawQuery('''
      SELECT DISTINCT pl.language_id AS target_language_id
      FROM project_languages pl
      INNER JOIN projects p ON p.id = pl.project_id
      INNER JOIN game_installations gi ON gi.id = p.game_installation_id
      WHERE gi.game_code = ?
    ''', [gameCode]);
    for (final r in rows) {
      await provisionForProjectLanguage(
        gameCode: gameCode,
        targetLanguageId: r['target_language_id'] as String,
      );
    }
  }

  /// Provision a single empty glossary for [gameCode] + [targetLanguageId].
  /// No-op if a glossary already exists for that pair.
  Future<void> provisionForProjectLanguage({
    required String gameCode,
    required String targetLanguageId,
  }) async {
    final exists = await DatabaseService.database.rawQuery('''
      SELECT 1 FROM glossaries
      WHERE game_code = ? AND target_language_id = ?
      LIMIT 1
    ''', [gameCode, targetLanguageId]);
    if (exists.isNotEmpty) return;

    final lang = await DatabaseService.database.rawQuery(
      'SELECT code FROM languages WHERE id = ? LIMIT 1',
      [targetLanguageId],
    );
    if (lang.isEmpty) {
      _logger.warning(
        'provisionForProjectLanguage: unknown language $targetLanguageId',
      );
      return;
    }

    final gameName = supportedGames[gameCode]?.name ?? gameCode;
    final langCode = lang.first['code'] as String;
    final baseName = '$gameName · $langCode';
    final name = await _uniqueName(baseName);
    final now = DateTime.now().millisecondsSinceEpoch;

    await DatabaseService.database.insert('glossaries', {
      'id': _uuid.v4(),
      'name': name,
      'description': null,
      'game_code': gameCode,
      'target_language_id': targetLanguageId,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Resolves the `game_code` for [projectId] via its `game_installations` row,
  /// then provisions an empty glossary for every `(gameCode, languageId)` pair
  /// in [targetLanguageIds].
  ///
  /// Best-effort: any failure (unknown project, missing game installation, or
  /// per-language provisioning error) is logged and swallowed. The caller's
  /// flow is never interrupted.
  Future<void> provisionForProject({
    required String projectId,
    required List<String> targetLanguageIds,
  }) async {
    if (targetLanguageIds.isEmpty) return;
    try {
      final rows = await DatabaseService.database.rawQuery('''
        SELECT gi.game_code AS game_code
        FROM projects p
        INNER JOIN game_installations gi ON gi.id = p.game_installation_id
        WHERE p.id = ?
        LIMIT 1
      ''', [projectId]);
      if (rows.isEmpty) {
        _logger.warning(
          'provisionForProject: project or game installation not found',
          {'projectId': projectId},
        );
        return;
      }
      final gameCode = rows.first['game_code'] as String;
      for (final languageId in targetLanguageIds) {
        try {
          await provisionForProjectLanguage(
            gameCode: gameCode,
            targetLanguageId: languageId,
          );
        } catch (e) {
          _logger.warning(
            'provisionForProject: per-language provisioning failed',
            {
              'projectId': projectId,
              'gameCode': gameCode,
              'languageId': languageId,
              'error': e.toString(),
            },
          );
        }
      }
    } catch (e) {
      _logger.warning(
        'provisionForProject failed',
        {'projectId': projectId, 'error': e.toString()},
      );
    }
  }

  /// Returns a glossary name that does not collide with any existing row.
  /// Appends ` (2)`, ` (3)`, … to [baseName] until unique.
  Future<String> _uniqueName(String baseName) async {
    String candidate = baseName;
    int suffix = 2;
    // Hard cap to guard against pathological DB states; in practice this
    // loop terminates within a single iteration.
    for (int i = 0; i < 10000; i++) {
      final rows = await DatabaseService.database.rawQuery(
        'SELECT 1 FROM glossaries WHERE name = ? LIMIT 1',
        [candidate],
      );
      if (rows.isEmpty) return candidate;
      candidate = '$baseName ($suffix)';
      suffix++;
    }
    // Fallback: include a uuid fragment to virtually guarantee uniqueness.
    return '$baseName (${_uuid.v4().substring(0, 8)})';
  }
}
