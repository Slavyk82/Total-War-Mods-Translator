/// Token bucket for rate limiting
///
/// Implements the token bucket algorithm for smooth rate limiting.
/// Tokens are added at a constant rate and consumed by requests.
class TokenBucket {
  /// Maximum tokens in bucket (capacity)
  final int capacity;

  /// Refill rate (tokens per second)
  final double refillRate;

  /// Current tokens in bucket
  double _tokens;

  /// Last refill timestamp
  DateTime _lastRefill;

  TokenBucket({
    required this.capacity,
    required this.refillRate,
  })  : _tokens = capacity.toDouble(),
        _lastRefill = DateTime.now();

  /// Try to consume tokens
  ///
  /// Returns true if tokens were consumed, false if not enough tokens available.
  ///
  /// [tokens] - Number of tokens to consume
  bool tryConsume(int tokens) {
    _refill();

    if (_tokens >= tokens) {
      _tokens -= tokens;
      return true;
    }

    return false;
  }

  /// Wait until tokens are available and consume them
  ///
  /// Calculates wait time and returns it.
  /// Caller should await this duration before making request.
  ///
  /// [tokens] - Number of tokens to consume
  ///
  /// Returns duration to wait (zero if tokens available immediately)
  Duration waitAndConsume(int tokens) {
    _refill();

    if (_tokens >= tokens) {
      _tokens -= tokens;
      return Duration.zero;
    }

    // Calculate tokens needed
    final tokensNeeded = tokens - _tokens;

    // Calculate wait time based on refill rate
    final waitSeconds = tokensNeeded / refillRate;

    // Mark tokens as consumed (will be negative, will refill while waiting)
    _tokens -= tokens;

    return Duration(milliseconds: (waitSeconds * 1000).ceil());
  }

  /// Refill tokens based on elapsed time
  void _refill() {
    final now = DateTime.now();
    final elapsedSeconds = now.difference(_lastRefill).inMilliseconds / 1000.0;

    if (elapsedSeconds > 0) {
      // Add tokens based on elapsed time
      final tokensToAdd = elapsedSeconds * refillRate;
      _tokens = (_tokens + tokensToAdd).clamp(0.0, capacity.toDouble());
      _lastRefill = now;
    }
  }

  /// Get current tokens available
  double get availableTokens {
    _refill();
    return _tokens;
  }

  /// Check if bucket is full
  bool get isFull {
    _refill();
    return _tokens >= capacity;
  }

  /// Check if bucket is empty
  bool get isEmpty {
    _refill();
    return _tokens <= 0;
  }

  /// Reset bucket to full capacity
  void reset() {
    _tokens = capacity.toDouble();
    _lastRefill = DateTime.now();
  }

  @override
  String toString() {
    return 'TokenBucket(capacity: $capacity, refillRate: $refillRate/s, '
        'available: ${availableTokens.toStringAsFixed(1)})';
  }
}
