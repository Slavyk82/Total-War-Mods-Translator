import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/steam/models/game_definitions.dart';

part 'published_subs_cache_provider.g.dart';

/// Session-level cache of Workshop subscriber counts for translation mods
/// the user has published from this app.
///
/// Keys are `publishedSteamId` strings (Workshop item ids of *published
/// translation mods*, distinct from the original game mods). Values are
/// the subscriber counts last fetched from the Steam Workshop API.
///
/// The cache is populated once per app session by `refreshFromWorkshop`,
/// invoked from the boot-time `ModScanBootDialog` after the mod scan
/// completes. It is `keepAlive: true` so revisiting the Publish screen
/// does not retrigger the fetch.
@Riverpod(keepAlive: true)
class PublishedSubsCache extends _$PublishedSubsCache {
  @override
  Map<String, int> build() => const {};

  /// Collects unique non-empty `publishedSteamId` values from every project
  /// and compilation of the currently selected game. Returns an empty list
  /// when no game is selected, the game is unknown, or no published items
  /// exist for the user.
  ///
  /// Pure DB read — does not mutate state.
  Future<List<String>> collectPublishedIds() async {
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) return const [];

    final game = getGameByCode(selectedGame.code);
    if (game == null) return const [];

    final installRepo = ref.read(gameInstallationRepositoryProvider);
    final installResult = await installRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return const [];
    final installationId = installResult.value.id;

    final ids = <String>{};

    final projectRepo = ref.read(projectRepositoryProvider);
    final projectsResult =
        await projectRepo.getByGameInstallation(installationId);
    if (projectsResult.isOk) {
      for (final p in projectsResult.value) {
        final id = p.publishedSteamId;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }

    final compilationRepo = ref.read(compilationRepositoryProvider);
    final compsResult =
        await compilationRepo.getByGameInstallation(installationId);
    if (compsResult.isOk) {
      for (final c in compsResult.value) {
        final id = c.publishedSteamId;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }

    return ids.toList();
  }

  /// Fetches subscriber counts for the given IDs in chunks of ≤100 and
  /// replaces state on success. On any chunk failure, leaves prior state
  /// untouched and returns `false`.
  ///
  /// Returns `true` when the cache was updated, `false` on failure or when
  /// the input is empty.
  Future<bool> refreshForIds(List<String> ids) async {
    if (ids.isEmpty) return false;

    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) return false;
    final game = getGameByCode(selectedGame.code);
    if (game == null) return false;
    final appId = int.tryParse(game.steamAppId);
    if (appId == null) return false;

    final api = ref.read(workshopApiServiceProvider);
    final next = <String, int>{};
    const chunkSize = 100;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize) > ids.length ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final result = await api.getMultipleModInfo(
        workshopIds: chunk,
        appId: appId,
      );
      if (result.isErr) return false;
      for (final info in result.value) {
        next[info.workshopId] = info.subscriptions ?? 0;
      }
    }
    state = next;
    return true;
  }

  /// Convenience wrapper: collect IDs and refresh in one call. Returns the
  /// number of IDs that were processed (0 when there is nothing to refresh).
  Future<void> refreshFromWorkshop() async {
    final ids = await collectPublishedIds();
    if (ids.isEmpty) return;
    await refreshForIds(ids);
  }
}
