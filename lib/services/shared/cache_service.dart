import 'dart:async';
import 'dart:collection';

/// Generic cache service with LRU eviction and TTL support
///
/// Features:
/// - LRU (Least Recently Used) eviction policy
/// - TTL (Time To Live) support per entry
/// - Cache statistics (hits, misses, evictions)
/// - Configurable max size
/// - Thread-safe operations
///
/// Example:
/// ```dart
/// final cache = CacheService<String, UserData>(maxSize: 100);
///
/// // Set with TTL
/// cache.set('user_123', userData, ttl: Duration(minutes: 5));
///
/// // Get
/// final user = cache.get('user_123');
///
/// // Check if exists
/// if (cache.has('user_123')) {
///   // ...
/// }
/// ```
class CacheService<K, V> {
  /// Maximum cache entries
  final int maxSize;

  /// Default TTL for entries (null = no expiration)
  final Duration? defaultTtl;

  /// Internal cache storage (LRU-ordered)
  final LinkedHashMap<K, _CacheEntry<V>> _cache = LinkedHashMap();

  /// Cache statistics
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _expirations = 0;

  /// Timer for periodic cleanup
  Timer? _cleanupTimer;

  CacheService({
    required this.maxSize,
    this.defaultTtl,
    Duration? cleanupInterval,
  }) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be positive');
    }

    // Start periodic cleanup if TTL is used
    if (defaultTtl != null || cleanupInterval != null) {
      _startCleanup(cleanupInterval ?? const Duration(minutes: 1));
    }
  }

  /// Get value from cache
  ///
  /// Returns null if not found or expired.
  /// Updates LRU order on hit.
  V? get(K key) {
    final entry = _cache[key];

    if (entry == null) {
      _misses++;
      return null;
    }

    // Check if expired
    if (entry.isExpired) {
      _cache.remove(key);
      _expirations++;
      _misses++;
      return null;
    }

    // Move to end (most recently used)
    _cache.remove(key);
    _cache[key] = entry;

    _hits++;
    return entry.value;
  }

  /// Set value in cache
  ///
  /// Parameters:
  /// - [key]: Cache key
  /// - [value]: Value to cache
  /// - [ttl]: Time to live (overrides default)
  void set(K key, V value, {Duration? ttl}) {
    // Remove if already exists
    _cache.remove(key);

    // Create entry
    final expiresAt = _calculateExpiration(ttl ?? defaultTtl);
    final entry = _CacheEntry<V>(
      value: value,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );

    // Add to cache (end = most recently used)
    _cache[key] = entry;

    // Evict oldest if size exceeded
    if (_cache.length > maxSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _evictions++;
    }
  }

  /// Check if key exists in cache
  ///
  /// Does not update LRU order.
  /// Returns false if expired.
  bool has(K key) {
    final entry = _cache[key];

    if (entry == null) return false;

    if (entry.isExpired) {
      _cache.remove(key);
      _expirations++;
      return false;
    }

    return true;
  }

  /// Remove entry from cache
  ///
  /// Returns true if entry was removed.
  bool remove(K key) {
    return _cache.remove(key) != null;
  }

  /// Clear all entries
  void clear() {
    _cache.clear();
    _resetStatistics();
  }

  /// Get or compute value
  ///
  /// If key exists, returns cached value.
  /// If key doesn't exist, computes value and caches it.
  ///
  /// Example:
  /// ```dart
  /// final user = cache.getOrPut('user_123', () async {
  ///   return await fetchUserFromApi('123');
  /// });
  /// ```
  Future<V> getOrPut(
    K key,
    Future<V> Function() compute, {
    Duration? ttl,
  }) async {
    final cached = get(key);
    if (cached != null) return cached;

    final value = await compute();
    set(key, value, ttl: ttl);
    return value;
  }

  /// Get synchronous or compute
  ///
  /// Synchronous version of getOrPut.
  V getOrPutSync(
    K key,
    V Function() compute, {
    Duration? ttl,
  }) {
    final cached = get(key);
    if (cached != null) return cached;

    final value = compute();
    set(key, value, ttl: ttl);
    return value;
  }

  /// Get all keys currently in cache
  ///
  /// Does not filter out expired entries.
  List<K> get keys => _cache.keys.toList();

  /// Get all values currently in cache
  ///
  /// Does not filter out expired entries.
  List<V> get values => _cache.values.map((e) => e.value).toList();

  /// Get cache size
  int get size => _cache.length;

  /// Check if cache is empty
  bool get isEmpty => _cache.isEmpty;

  /// Check if cache is not empty
  bool get isNotEmpty => _cache.isNotEmpty;

  /// Get cache hit rate (0.0 - 1.0)
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 0.0 : _hits / total;
  }

  /// Get cache statistics
  CacheStatistics get statistics => CacheStatistics(
        size: _cache.length,
        maxSize: maxSize,
        hits: _hits,
        misses: _misses,
        evictions: _evictions,
        expirations: _expirations,
        hitRate: hitRate,
      );

  /// Remove expired entries
  ///
  /// Returns number of entries removed.
  int removeExpired() {
    int count = 0;

    final keysToRemove = <K>[];
    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      count++;
      _expirations++;
    }

    return count;
  }

  /// Resize cache
  ///
  /// If new size is smaller than current, evicts oldest entries.
  void resize(int newMaxSize) {
    if (newMaxSize <= 0) {
      throw ArgumentError('maxSize must be positive');
    }

    while (_cache.length > newMaxSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _evictions++;
    }
  }

  /// Reset statistics
  void _resetStatistics() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _expirations = 0;
  }

  /// Calculate expiration time
  DateTime? _calculateExpiration(Duration? ttl) {
    return ttl != null ? DateTime.now().add(ttl) : null;
  }

  /// Start periodic cleanup timer
  void _startCleanup(Duration interval) {
    _cleanupTimer = Timer.periodic(interval, (_) {
      removeExpired();
    });
  }

  /// Dispose of resources
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
  }
}

/// Cache entry with metadata
class _CacheEntry<V> {
  final V value;
  final DateTime createdAt;
  final DateTime? expiresAt;

  _CacheEntry({
    required this.value,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}

/// Cache statistics
class CacheStatistics {
  /// Current cache size
  final int size;

  /// Maximum cache size
  final int maxSize;

  /// Number of cache hits
  final int hits;

  /// Number of cache misses
  final int misses;

  /// Number of evictions (due to size limit)
  final int evictions;

  /// Number of expirations (due to TTL)
  final int expirations;

  /// Hit rate (0.0 - 1.0)
  final double hitRate;

  /// Fill rate (size / maxSize)
  double get fillRate => size / maxSize;

  const CacheStatistics({
    required this.size,
    required this.maxSize,
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.expirations,
    required this.hitRate,
  });

  @override
  String toString() {
    return 'CacheStatistics(size: $size/$maxSize, hits: $hits, misses: $misses, '
        'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%, '
        'evictions: $evictions, expirations: $expirations)';
  }
}
