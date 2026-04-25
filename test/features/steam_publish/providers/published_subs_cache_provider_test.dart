import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';

void main() {
  group('publishedSubsCacheProvider', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(publishedSubsCacheProvider), isEmpty);
    });
  });
}
