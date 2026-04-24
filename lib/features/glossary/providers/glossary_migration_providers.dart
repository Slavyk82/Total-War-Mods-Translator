import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'glossary_migration_providers.g.dart';

/// Per-universal conversion choices made by the user in
/// [GlossaryMigrationScreen].
///
/// Maps each universal glossary id to the game `code` it should be reassigned
/// to, or `null` to delete it. The screen seeds this map with a single
/// `{id: null}` entry per universal on first build.
@riverpod
class GlossaryMigrationPlan extends _$GlossaryMigrationPlan {
  @override
  Map<String, String?> build() => const {};

  /// Populates the plan with one entry per universal id, all set to `null`
  /// (i.e. "don't convert"). Idempotent.
  void seed(List<String> universalIds) {
    state = {for (final id in universalIds) id: null};
  }

  /// Updates the user's choice for a single universal glossary.
  ///
  /// Passing `null` for [gameCode] flags the glossary for deletion.
  void setChoice(String universalId, String? gameCode) {
    state = {...state, universalId: gameCode};
  }
}
