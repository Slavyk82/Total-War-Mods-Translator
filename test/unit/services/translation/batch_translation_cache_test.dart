import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';

void main() {
  // The cache is a process-wide singleton; clear it before each test so state
  // does not leak between cases.
  final cache = BatchTranslationCache.instance;

  setUp(cache.clear);
  tearDown(cache.clear);

  group('BatchTranslationCache.lookup', () {
    test('returns CacheMiss for an unknown hash', () {
      final hash = cache.computeHash('unknown source', 'fr');

      expect(cache.lookup(hash), isA<CacheMiss>());
    });

    test('returns CacheHit for a completed entry', () {
      final hash = cache.computeHash('Hello', 'fr');
      cache.complete(hash, 'Bonjour');

      final result = cache.lookup(hash);

      expect(result, isA<CacheHit>());
      expect((result as CacheHit).translation, 'Bonjour');
    });

    test('returns CachePending while another batch is translating', () {
      final hash = cache.computeHash('Hello', 'fr');

      expect(cache.registerPending(hash, 'batch-1'), isTrue);

      final result = cache.lookup(hash);

      expect(result, isA<CachePending>());
    });

    test(
        'increments useCount by exactly 1 per lookup hit (Bug 1 regression)',
        () {
      final hash = cache.computeHash('Hello', 'fr');

      // complete() inserts a fresh entry with useCount == 1.
      cache.complete(hash, 'Bonjour');
      expect(cache.getStats().totalUseCount, 1);

      // Each successful lookup must bump useCount by exactly 1 (not 2, which
      // was the double-increment symptom of the discarded synchronized()
      // return value).
      cache.lookup(hash);
      expect(cache.getStats().totalUseCount, 2);

      cache.lookup(hash);
      expect(cache.getStats().totalUseCount, 3);

      cache.lookup(hash);
      expect(cache.getStats().totalUseCount, 4);
    });

    test('a CacheMiss lookup does not change useCount', () {
      final hitHash = cache.computeHash('Hello', 'fr');
      cache.complete(hitHash, 'Bonjour');
      expect(cache.getStats().totalUseCount, 1);

      // Looking up an unrelated, uncached hash must not touch existing counters.
      cache.lookup(cache.computeHash('Goodbye', 'fr'));

      expect(cache.getStats().totalUseCount, 1);
    });
  });

  group('BatchTranslationCache.registerPending', () {
    test('first caller wins, second caller is rejected', () {
      final hash = cache.computeHash('Hello', 'fr');

      expect(cache.registerPending(hash, 'batch-1'), isTrue);
      expect(cache.registerPending(hash, 'batch-2'), isFalse);
    });

    test('registration is rejected when already cached', () {
      final hash = cache.computeHash('Hello', 'fr');
      cache.complete(hash, 'Bonjour');

      expect(cache.registerPending(hash, 'batch-1'), isFalse);
    });

    test('completing a pending entry resolves the pending future', () async {
      final hash = cache.computeHash('Hello', 'fr');

      expect(cache.registerPending(hash, 'batch-1'), isTrue);

      final pending = cache.lookup(hash);
      expect(pending, isA<CachePending>());

      cache.complete(hash, 'Bonjour');

      await expectLater((pending as CachePending).future, completion('Bonjour'));
    });
  });
}
