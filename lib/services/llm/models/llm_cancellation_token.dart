import 'package:dio/dio.dart';

/// Token for cancelling LLM requests
///
/// Wraps Dio's CancelToken and provides additional functionality
/// for batch translation cancellation.
class LlmCancellationToken {
  final CancelToken _cancelToken;
  bool _isCancelled = false;

  LlmCancellationToken() : _cancelToken = CancelToken();

  /// Get the underlying Dio cancel token
  CancelToken get dioToken => _cancelToken;

  /// Check if this token has been cancelled
  bool get isCancelled => _isCancelled;

  /// Cancel all operations using this token
  void cancel([String? reason]) {
    if (!_isCancelled) {
      _isCancelled = true;
      _cancelToken.cancel(reason ?? 'Translation stopped by user');
    }
  }

  /// Throw if cancelled
  void throwIfCancelled() {
    if (_isCancelled) {
      throw LlmCancelledException('Operation was cancelled');
    }
  }
}

/// Exception thrown when LLM operation is cancelled
class LlmCancelledException implements Exception {
  final String message;

  LlmCancelledException(this.message);

  @override
  String toString() => 'LlmCancelledException: $message';
}

