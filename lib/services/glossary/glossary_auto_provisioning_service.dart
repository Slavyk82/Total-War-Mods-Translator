import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../service_locator.dart';
import '../shared/i_logging_service.dart';
import '../steam/models/game_definitions.dart';

/// Creates empty `(game_code, target_language_id)` glossaries on demand.
///
/// Called from two trigger sites:
/// - When a new game path is saved in settings → [provisionForGame].
/// - When a language is added to a project → [provisionForProjectLanguage].
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
