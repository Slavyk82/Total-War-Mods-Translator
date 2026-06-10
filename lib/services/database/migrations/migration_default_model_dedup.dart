import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Repair migration that collapses duplicate per-provider default models.
///
/// Earlier versions of [OpenAiGpt5xModelsMigration] and
/// [AnthropicOpus47Sonnet46Migration] INSERTed their new flagship rows with
/// `is_default = 1`. The single-default trigger
/// (`trg_llm_models_single_default`) is `BEFORE UPDATE OF is_default` only —
/// it never fires on INSERT — so on upgraded databases where the user had
/// starred another model the provider ended up with TWO `is_default = 1`
/// rows, making `getDefaultByProvider` (LIMIT 1, no ORDER BY)
/// nondeterministic. Those migrations now insert with `is_default = 0`, but
/// databases they already ran on still carry the duplicates; this migration
/// collapses each provider back to a single default.
///
/// Keeper selection (deterministic): non-archived rows win over archived
/// ones, user-starred rows win over the rows the buggy migrations inserted,
/// then most recently updated wins, with the row id as the final tiebreak.
///
/// No settings marker is needed (unlike [DeepSeekChatRestoreMigration]):
/// [isApplied] checks the live state — no provider with more than one
/// default — so the migration is naturally idempotent and self-healing, and
/// clearing surplus flags can never override a legitimate user choice
/// because duplicate defaults are always an invalid state.
class DefaultModelDedupMigration extends Migration {
  final ILoggingService _logger;

  DefaultModelDedupMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Rows the buggy model migrations inserted with `is_default = 1`. When a
  /// duplicate set contains one of these next to a user-starred row, the
  /// migration-inserted row loses its flag (the user's choice wins) — these
  /// rows carry the migration timestamp, so "most recently updated" alone
  /// would wrongly prefer them over the user's earlier star.
  static const Set<String> _migrationSeededDefaultIds = {
    'model_gpt_5_5',
    'model_claude_sonnet_4_6',
  };

  @override
  String get id => 'default_model_dedup';

  @override
  String get description =>
      'Collapse duplicate per-provider default LLM models to a single one';

  @override
  int get priority => 210;

  @override
  Future<bool> isApplied() async {
    final duplicated = await DatabaseService.database.rawQuery('''
      SELECT provider_code FROM llm_provider_models
      WHERE is_default = 1
      GROUP BY provider_code
      HAVING COUNT(*) > 1
    ''');
    return duplicated.isEmpty;
  }

  @override
  Future<bool> execute() async {
    try {
      final rows = await DatabaseService.database.rawQuery('''
        SELECT id, provider_code, is_archived, updated_at
        FROM llm_provider_models
        WHERE is_default = 1
      ''');

      final byProvider = <String, List<Map<String, Object?>>>{};
      for (final row in rows) {
        byProvider
            .putIfAbsent(row['provider_code'] as String, () => [])
            .add(row);
      }

      final loserIds = <String>[];
      for (final entry in byProvider.entries) {
        final defaults = entry.value;
        if (defaults.length < 2) continue;

        defaults.sort(_compareKeeperFirst);
        loserIds.addAll(
          defaults.skip(1).map((row) => row['id'] as String),
        );
      }

      if (loserIds.isEmpty) {
        return false; // Nothing to repair
      }

      final placeholders = List.filled(loserIds.length, '?').join(', ');
      // Setting is_default = 0 does not fire trg_llm_models_single_default
      // (its WHEN clause requires NEW.is_default = 1).
      await DatabaseService.database.rawUpdate(
        '''
        UPDATE llm_provider_models
        SET is_default = 0,
            updated_at = strftime('%s', 'now')
        WHERE id IN ($placeholders)
        ''',
        loserIds,
      );

      _logger.info(
        'Collapsed duplicate default LLM models to one per provider',
        {'clearedIds': loserIds},
      );
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to dedup default LLM models', e, stackTrace);
      return false;
    }
  }

  /// Orders duplicate default rows so the row to KEEP sorts first.
  static int _compareKeeperFirst(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    // Non-archived rows win over archived ones.
    final archivedA = (a['is_archived'] as int?) ?? 0;
    final archivedB = (b['is_archived'] as int?) ?? 0;
    if (archivedA != archivedB) return archivedA.compareTo(archivedB);

    // User-starred rows win over the migration-inserted duplicates.
    final seededA = _migrationSeededDefaultIds.contains(a['id']) ? 1 : 0;
    final seededB = _migrationSeededDefaultIds.contains(b['id']) ? 1 : 0;
    if (seededA != seededB) return seededA.compareTo(seededB);

    // Most recently updated wins.
    final updatedA = (a['updated_at'] as int?) ?? 0;
    final updatedB = (b['updated_at'] as int?) ?? 0;
    if (updatedA != updatedB) return updatedB.compareTo(updatedA);

    // Deterministic final tiebreak.
    return (a['id'] as String).compareTo(b['id'] as String);
  }
}
