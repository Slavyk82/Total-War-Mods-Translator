import 'package:riverpod_annotation/riverpod_annotation.dart';

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
    // Filled in by Task 3.
  }
}
