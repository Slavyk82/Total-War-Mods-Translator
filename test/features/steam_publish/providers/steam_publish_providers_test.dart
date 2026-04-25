// Unit tests for the Steam Publish screen's transient state providers
// introduced in Plan 5a · Task 4.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/models/domain/project.dart';

class _StubSubsCache extends PublishedSubsCache {
  _StubSubsCache(this._initial);
  final Map<String, int> _initial;

  @override
  Map<String, int> build() => _initial;
}

PublishableItem _stubItem({required String? publishedSteamId}) {
  return ProjectPublishItem(
    export: null,
    project: Project(
      id: 'p-${publishedSteamId ?? "none"}',
      name: 'P',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1700000000 : null,
    ),
    languageCodes: const ['en'],
  );
}

void main() {
  group('steamPublishSelectionProvider', () {
    test('defaults to an empty set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(steamPublishSelectionProvider), isEmpty);
    });

    test('toggles ids via direct state assignment', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(steamPublishSelectionProvider.notifier).state = {'a'};
      expect(container.read(steamPublishSelectionProvider), {'a'});

      container.read(steamPublishSelectionProvider.notifier).state = {'a', 'b'};
      expect(container.read(steamPublishSelectionProvider), {'a', 'b'});

      container.read(steamPublishSelectionProvider.notifier).state = {};
      expect(container.read(steamPublishSelectionProvider), isEmpty);
    });
  });

  group('steamPublishSearchQueryProvider', () {
    test('defaults to empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(steamPublishSearchQueryProvider), isEmpty);
    });

    test('round-trips search query updates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(steamPublishSearchQueryProvider.notifier).state = 'sigmar';
      expect(container.read(steamPublishSearchQueryProvider), 'sigmar');
    });
  });

  group('steamPublishDisplayFilterProvider', () {
    test('defaults to SteamPublishDisplayFilter.all', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(steamPublishDisplayFilterProvider),
        SteamPublishDisplayFilter.all,
      );
    });

    test('transitions between filter values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(steamPublishDisplayFilterProvider.notifier).state =
          SteamPublishDisplayFilter.outdated;
      expect(
        container.read(steamPublishDisplayFilterProvider),
        SteamPublishDisplayFilter.outdated,
      );
    });
  });

  group('steamPublishSortModeProvider', () {
    test('defaults to exportDate descending', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(steamPublishSortModeProvider),
        SteamPublishSortMode.exportDate,
      );
      expect(
        container.read(steamPublishSortAscendingProvider),
        isFalse,
      );
    });
  });

  group('filteredPublishableItemsSubsTotalProvider', () {
    test('sums cache values across filtered items, ignoring missing ids', () {
      final container = ProviderContainer(
        overrides: [
          // Stub the upstream filtered-items list. Each item exposes the
          // `publishedSteamId` we care about; other fields are irrelevant.
          filteredPublishableItemsProvider.overrideWith((ref) => [
                _stubItem(publishedSteamId: '111'),
                _stubItem(publishedSteamId: '222'),
                _stubItem(publishedSteamId: '333'), // not in cache
                _stubItem(publishedSteamId: null), // unpublished
              ]),
          publishedSubsCacheProvider.overrideWith(
            () => _StubSubsCache(const {'111': 100, '222': 50}),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(filteredPublishableItemsSubsTotalProvider),
        150,
      );
    });

    test('returns 0 when cache is empty', () {
      final container = ProviderContainer(
        overrides: [
          filteredPublishableItemsProvider.overrideWith((ref) => [
                _stubItem(publishedSteamId: '111'),
              ]),
          publishedSubsCacheProvider.overrideWith(
            () => _StubSubsCache(const {}),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(filteredPublishableItemsSubsTotalProvider), 0);
    });
  });
}
