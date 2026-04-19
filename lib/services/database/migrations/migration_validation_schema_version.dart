import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'migration_base.dart';

/// Adds `validation_schema_version` to `translation_versions`.
///
/// Rows written with the pre-structured (`List<String>`) format keep the
/// default value 0; any row re-validated after this release is bumped to 1
/// by the persistence layer. A one-shot rescan at app startup migrates all
/// remaining version-0 rows to the new structured format.
class ValidationSchemaVersionMigration extends Migration {
  final ILoggingService _logger;

  ValidationSchemaVersionMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'validation_schema_version_column';

  @override
  String get description =>
      'Add validation_schema_version column to translation_versions';

  // Must run before ValidationIssuesJsonMigration (priority 110) so the
  // column exists when any downstream migration inspects rows, but after
  // basic column-adding migrations. 105 is unused upstream.
  @override
  int get priority => 105;

  @override
  Future<bool> isApplied() async {
    final cols = await DatabaseService.database
        .rawQuery('PRAGMA table_info(translation_versions)');
    return cols.any((c) => c['name'] == 'validation_schema_version');
  }

  @override
  Future<bool> execute() async {
    if (await isApplied()) {
      _logger.debug('validation_schema_version column already present');
      return false;
    }
    await DatabaseService.database.execute('''
      ALTER TABLE translation_versions
      ADD COLUMN validation_schema_version INTEGER NOT NULL DEFAULT 0
    ''');
    _logger.info('Added validation_schema_version column');
    return true;
  }
}
