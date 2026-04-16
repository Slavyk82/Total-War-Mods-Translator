// Unit tests for the Steam Publish screen's transient state providers
// introduced in Plan 5a · Task 4.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';

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
}
