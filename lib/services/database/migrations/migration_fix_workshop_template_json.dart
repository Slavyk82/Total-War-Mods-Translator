import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../../steam/workshop_template.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Normalize Workshop title/description templates that were stored as a
/// localized JSON map (`{"fr":"..."}`) instead of plain text.
///
/// Such a value injects escaped quotes (`\"`) into the generated workshop VDF,
/// which breaks steamcmd's KeyValues parser (BBCode `[h1]` is then read as a
/// platform conditional) and crashes the publish with exit code 9. The read
/// paths already unwrap this defensively, but this migration heals the stored
/// data once for upgraded databases so the value is correct at the source.
///
/// Idempotent: re-running on already-plain values is a no-op.
class FixWorkshopTemplateJsonMigration extends Migration {
  final ILoggingService _logger;

  FixWorkshopTemplateJsonMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Settings keys that hold publish templates and must be plain text.
  static const List<String> _keys = [
    'workshop_title_template',
    'workshop_description_template',
  ];

  @override
  String get id => 'fix_workshop_template_json';

  @override
  String get description =>
      'Unwrap JSON-localized Workshop title/description templates to plain text';

  @override
  int get priority => 250;

  @override
  Future<bool> execute() async {
    try {
      var changed = false;
      for (final key in _keys) {
        final rows = await DatabaseService.database.query(
          'settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
        );
        if (rows.isEmpty) continue;
        final raw = rows.first['value'] as String?;
        if (raw == null || raw.isEmpty) continue;

        // Reuse the read-path resolver (no language → first value) so stored
        // data is normalized exactly as the app would interpret it.
        final plain = resolveLocalizedTemplate(raw);
        if (plain == raw) continue;

        await DatabaseService.database.update(
          'settings',
          {'value': plain},
          where: 'key = ?',
          whereArgs: [key],
        );
        changed = true;
        _logger.info('Normalized JSON-localized Workshop template', {
          'key': key,
        });
      }
      return changed;
    } catch (e, stackTrace) {
      // Non-fatal: the read paths still unwrap defensively at publish time.
      _logger.error('Failed to normalize Workshop templates', e, stackTrace);
      return false;
    }
  }
}
