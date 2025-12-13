/// Base class for database migrations.
///
/// Each migration implements a specific database schema change or data fix
/// that can be applied to existing databases. Migrations are run incrementally
/// during application startup via [MigrationRegistry].
abstract class Migration {
  /// Unique identifier for this migration.
  ///
  /// Used to track which migrations have been applied and for logging.
  /// Should be descriptive, e.g., 'add_translation_source_column'.
  String get id;

  /// Human-readable description of what this migration does.
  String get description;

  /// Order in which this migration should run relative to others.
  ///
  /// Lower numbers run first. Migrations with the same priority
  /// run in registration order.
  int get priority => 100;

  /// Execute the migration.
  ///
  /// Implementations should:
  /// - Check if the migration is needed (e.g., column exists)
  /// - Apply changes if needed
  /// - Be idempotent (safe to run multiple times)
  /// - Handle errors gracefully (non-fatal migrations should catch exceptions)
  ///
  /// Returns true if migration was applied, false if skipped.
  Future<bool> execute();

  /// Check if this migration has already been applied.
  ///
  /// Override this for migrations that need custom detection logic.
  /// Default returns false (always try to execute).
  Future<bool> isApplied() async => false;
}

/// Result of running a migration.
class MigrationResult {
  final String migrationId;
  final bool success;
  final bool skipped;
  final String? errorMessage;
  final Duration duration;

  const MigrationResult({
    required this.migrationId,
    required this.success,
    required this.skipped,
    this.errorMessage,
    required this.duration,
  });

  factory MigrationResult.success(String id, Duration duration) => MigrationResult(
        migrationId: id,
        success: true,
        skipped: false,
        duration: duration,
      );

  factory MigrationResult.skipped(String id) => MigrationResult(
        migrationId: id,
        success: true,
        skipped: true,
        duration: Duration.zero,
      );

  factory MigrationResult.error(String id, String error, Duration duration) =>
      MigrationResult(
        migrationId: id,
        success: false,
        skipped: false,
        errorMessage: error,
        duration: duration,
      );

  @override
  String toString() {
    if (skipped) return '$migrationId: skipped';
    if (success) return '$migrationId: success (${duration.inMilliseconds}ms)';
    return '$migrationId: error - $errorMessage';
  }
}
