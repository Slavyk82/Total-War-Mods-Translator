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

  /// Replace the cache wholesale with the result of a fresh Workshop API
  /// query. On error, the prior state is left untouched.
  Future<void> refreshFromWorkshop() async {
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) return;

    final game = getGameByCode(selectedGame.code);
    if (game == null) return;
    final appId = int.tryParse(game.steamAppId);
    if (appId == null) return;

    final installRepo = ref.read(gameInstallationRepositoryProvider);
    final installResult = await installRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return;
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

    if (ids.isEmpty) {
      state = const {};
      return;
    }

    final api = ref.read(workshopApiServiceProvider);
    final result = await api.getMultipleModInfo(
      workshopIds: ids.toList(),
      appId: appId,
    );
    if (result.isErr) return;

    final next = <String, int>{};
    for (final info in result.value) {
      final subs = info.subscriptions;
      if (subs != null) next[info.workshopId] = subs;
    }
    state = next;
  }
}
