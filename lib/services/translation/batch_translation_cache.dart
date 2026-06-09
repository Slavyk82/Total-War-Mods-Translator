import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Result of a cached translation lookup
sealed class CacheResult {}

/// Translation found in cache
class CacheHit extends CacheResult {
  final String translation;
  CacheHit(this.translation);
}

/// Translation is being processed by another batch - wait for it
class CachePending extends CacheResult {
  final Future<String?> future;
  CachePending(this.future);
}

/// Translation not in cache and not being processed
class CacheMiss extends CacheResult {}

/// Entry in the translation cache
class _CacheEntry {
  final String translation;
  final DateTime createdAt;
  int useCount = 1;

  _CacheEntry({
    required this.translation,
    required this.createdAt,
  });
}

/// Pending translation being processed
class _PendingEntry {
  final Completer<String?> completer;
  final DateTime startedAt;
  final String batchId;

  _PendingEntry({
    required this.completer,
    required this.startedAt,
    required this.batchId,
  });
}

/// Shared cache for translations across parallel batches
///
/// Provides:
/// - Deduplication within a single batch (same source text)
/// - Deduplication across parallel batches (wait for pending translations)
/// - Short-term caching of recent translations
///
/// Dart runs each isolate on a single thread, so the synchronous methods on
/// this class are not interrupted mid-execution and need no real locking.
/// Note this does NOT serialize logical operations that span `await`
/// boundaries: two parallel batches can each observe a [CacheMiss] for the same
/// source text (between a [lookup] and a later [registerPending]) and both
/// translate it. That is a benign redundancy (extra LLM work, correct results),
/// not state corruption — the first batch to call [registerPending] wins and
/// the rest see [CachePending] on their next lookup.
class BatchTranslationCache {
  /// Singleton instance
  static final BatchTranslationCache _instance = BatchTranslationCache._();
  static BatchTranslationCache get instance => _instance;

  BatchTranslationCache._();

  /// Completed translations: sourceHash -> translation
  final Map<String, _CacheEntry> _cache = {};

  /// Pending translations: sourceHash -> completer
  final Map<String, _PendingEntry> _pending = {};

  /// Lock for thread-safe access
  final _lock = Object();

  /// Maximum cache size (LRU eviction when exceeded)
  static const int _maxCacheSize = 10000;

  /// Cache TTL (entries older than this are evicted)
  static const Duration _cacheTtl = Duration(minutes: 30);

  /// Compute hash for source text + target language
  String computeHash(String sourceText, String targetLanguage) {
    final input = '$sourceText|$targetLanguage';
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Check cache for a translation
  ///
  /// Returns:
  /// - [CacheHit] if translation is cached
  /// - [CachePending] if another batch is translating this text (with future to wait)
  /// - [CacheMiss] if not cached and not pending
  CacheResult lookup(String sourceHash) {
    return synchronized(_lock, () {
      // Check completed cache first
      final cached = _cache[sourceHash];
      if (cached != null) {
        // Check TTL
        if (DateTime.now().difference(cached.createdAt) < _cacheTtl) {
          cached.useCount++;
          return CacheHit(cached.translation);
        } else {
          // Expired, remove it
          _cache.remove(sourceHash);
        }
      }

      // Check if pending
      final pending = _pending[sourceHash];
      if (pending != null) {
        return CachePending(pending.completer.future);
      }

      return CacheMiss();
    });
  }

  /// Register that a batch is starting to translate this source text
  ///
  /// Returns true if registration succeeded (this batch should translate).
  /// Returns false if another batch already registered (should wait instead).
  bool registerPending(String sourceHash, String batchId) {
    // Check if already pending or cached
    if (_pending.containsKey(sourceHash)) {
      return false;
    }

    final cached = _cache[sourceHash];
    if (cached != null && DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return false;
    }

    // Register as pending
    _pending[sourceHash] = _PendingEntry(
      completer: Completer<String?>(),
      startedAt: DateTime.now(),
      batchId: batchId,
    );

    return true;
  }

  /// Complete a pending translation with result
  ///
  /// Stores in cache and notifies all waiting batches.
  void complete(String sourceHash, String translation) {
    final pending = _pending.remove(sourceHash);

    // Add to cache
    _cache[sourceHash] = _CacheEntry(
      translation: translation,
      createdAt: DateTime.now(),
    );

    // Evict old entries if cache is too large
    _evictIfNeeded();

    // Notify waiters
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(translation);
    }
  }

  /// Mark a pending translation as failed
  ///
  /// Notifies waiters with null so they can try themselves.
  void fail(String sourceHash) {
    final pending = _pending.remove(sourceHash);
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(null);
    }
  }

  /// Cancel all pending translations for a batch (e.g., on cancellation)
  void cancelBatch(String batchId) {
    final toRemove = <String>[];

    for (final entry in _pending.entries) {
      if (entry.value.batchId == batchId) {
        toRemove.add(entry.key);
      }
    }

    for (final hash in toRemove) {
      fail(hash);
    }
  }

  /// Clear entire cache (for testing or reset)
  void clear() {
    // Fail all pending
    for (final entry in _pending.values) {
      if (!entry.completer.isCompleted) {
        entry.completer.complete(null);
      }
    }
    _pending.clear();
    _cache.clear();
  }

  /// Get cache statistics
  CacheStats getStats() {
    return CacheStats(
      cachedEntries: _cache.length,
      pendingEntries: _pending.length,
      totalUseCount: _cache.values.fold(0, (sum, e) => sum + e.useCount),
    );
  }

  /// Evict old entries if cache exceeds max size
  void _evictIfNeeded() {
    if (_cache.length <= _maxCacheSize) return;

    // Sort by use count (ascending) and age (oldest first)
    final entries = _cache.entries.toList()
      ..sort((a, b) {
        // First by use count
        final useCompare = a.value.useCount.compareTo(b.value.useCount);
        if (useCompare != 0) return useCompare;
        // Then by age
        return a.value.createdAt.compareTo(b.value.createdAt);
      });

    // Remove bottom 20%
    final toRemove = (entries.length * 0.2).ceil();
    for (var i = 0; i < toRemove && i < entries.length; i++) {
      _cache.remove(entries[i].key);
    }
  }

  /// Group units by source text for deduplication
  ///
  /// Returns map of sourceHash -> list of unit IDs with that source text
  Map<String, List<String>> groupBySourceText(
    Map<String, String> unitIdToSourceText,
    String targetLanguage,
  ) {
    final groups = <String, List<String>>{};

    for (final entry in unitIdToSourceText.entries) {
      final hash = computeHash(entry.value, targetLanguage);
      groups.putIfAbsent(hash, () => []).add(entry.key);
    }

    return groups;
  }
}

/// Cache statistics
class CacheStats {
  final int cachedEntries;
  final int pendingEntries;
  final int totalUseCount;

  const CacheStats({
    required this.cachedEntries,
    required this.pendingEntries,
    required this.totalUseCount,
  });

  @override
  String toString() =>
      'CacheStats(cached: $cachedEntries, pending: $pendingEntries, uses: $totalUseCount)';
}

/// Runs [action] and returns its result.
///
/// This is NOT a mutex and provides no mutual exclusion. Dart executes each
/// isolate on a single thread, so a purely synchronous [action] already runs to
/// completion without interruption. The [lock] parameter is unused and kept only
/// to document which state the call is meant to touch. It cannot serialize logic
/// that spans `await` boundaries — use it only around synchronous critical
/// sections.
T synchronized<T>(Object lock, T Function() action) => action();
