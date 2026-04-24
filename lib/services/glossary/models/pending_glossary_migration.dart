/// DTOs describing the state detected by [GlossaryMigrationService].
///
/// These are in-memory value objects (no persistence) produced by the
/// migration detection pass and consumed by the migration UI. They capture
/// the two conditions that trigger the one-shot migration:
///
///  * Universal glossaries (`game_code IS NULL`) that need to be scoped
///    to a specific game, and
///  * Groups of glossaries sharing the same `(game_code, target_language_id)`
///    that must be consolidated into a single glossary per pair.
class PendingGlossaryMigration {
  final List<UniversalGlossaryInfo> universals;
  final List<DuplicateGlossaryGroup> duplicates;

  const PendingGlossaryMigration({
    required this.universals,
    required this.duplicates,
  });

  bool get isEmpty => universals.isEmpty && duplicates.isEmpty;
}

/// A universal glossary (one with `game_code IS NULL`) awaiting assignment
/// to a specific game.
class UniversalGlossaryInfo {
  final String id;
  final String name;
  final String? description;
  final String targetLanguageId;
  final String targetLanguageCode;
  final int entryCount;

  const UniversalGlossaryInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.targetLanguageId,
    required this.targetLanguageCode,
    required this.entryCount,
  });
}

/// A set of glossaries that share the same `(game_code, target_language_id)`
/// and therefore need to be merged into a single glossary.
class DuplicateGlossaryGroup {
  final String gameCode;
  final String targetLanguageId;
  final String targetLanguageCode;
  final List<DuplicateGlossaryMember> members;

  const DuplicateGlossaryGroup({
    required this.gameCode,
    required this.targetLanguageId,
    required this.targetLanguageCode,
    required this.members,
  });
}

/// One glossary belonging to a [DuplicateGlossaryGroup].
class DuplicateGlossaryMember {
  final String id;
  final String name;
  final int entryCount;
  final int createdAt;

  const DuplicateGlossaryMember({
    required this.id,
    required this.name,
    required this.entryCount,
    required this.createdAt,
  });
}

/// User-supplied decisions for the one-shot migration.
///
/// [conversions] maps a universal glossary id to the `game_code` it should be
/// reassigned to, or `null` to delete the glossary. Universals not present in
/// this map are deleted by [GlossaryMigrationService.applyMigration].
class MigrationPlan {
  final Map<String, String?> conversions;

  const MigrationPlan({required this.conversions});
}
