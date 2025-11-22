import 'dart:async';
import 'package:twmt/services/shared/logging_service.dart';

/// Performance monitoring service for tracking operation durations and metrics.
///
/// This service helps identify performance bottlenecks by:
/// - Tracking operation execution times
/// - Logging slow operations
/// - Collecting performance metrics
/// - Providing performance statistics
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final LoggingService _logger = LoggingService.instance;

  /// Threshold for slow operation warning (in milliseconds)
  int slowOperationThresholdMs = 1000;

  /// Threshold for very slow operation error (in milliseconds)
  int verySlowOperationThresholdMs = 5000;

  /// Whether to log all operations (useful for debugging)
  bool logAllOperations = false;

  /// Map to store operation metrics
  final Map<String, _OperationMetrics> _metrics = {};

  /// Track and time an async operation.
  ///
  /// Automatically logs warnings for slow operations and collects metrics.
  ///
  /// Example:
  /// ```dart
  /// final result = await PerformanceMonitor().track(
  ///   'database_query',
  ///   () => repository.getAll(),
  ///   metadata: {'table': 'users'},
  /// );
  /// ```
  ///
  /// [operationName] - Name of the operation (used for logging and metrics)
  /// [operation] - The async operation to execute
  /// [metadata] - Optional metadata to include in logs
  ///
  /// Returns the result of the operation
  Future<T> track<T>(
    String operationName,
    Future<T> Function() operation, {
    Map<String, dynamic>? metadata,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();

      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;

      // Record metrics
      _recordMetric(operationName, durationMs);

      // Log based on duration
      if (durationMs >= verySlowOperationThresholdMs) {
        _logger.error(
          'Very slow operation: $operationName took ${durationMs}ms',
          metadata,
        );
      } else if (durationMs >= slowOperationThresholdMs) {
        _logger.warning(
          'Slow operation: $operationName took ${durationMs}ms',
          metadata,
        );
      } else if (logAllOperations) {
        _logger.debug(
          'Operation completed: $operationName in ${durationMs}ms',
          metadata,
        );
      }

      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;

      _logger.error(
        'Operation failed: $operationName after ${durationMs}ms',
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  /// Track and time a synchronous operation.
  ///
  /// Similar to [track] but for synchronous operations.
  ///
  /// Example:
  /// ```dart
  /// final result = PerformanceMonitor().trackSync(
  ///   'calculation',
  ///   () => complexCalculation(),
  /// );
  /// ```
  T trackSync<T>(
    String operationName,
    T Function() operation, {
    Map<String, dynamic>? metadata,
  }) {
    final stopwatch = Stopwatch()..start();

    try {
      final result = operation();

      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;

      // Record metrics
      _recordMetric(operationName, durationMs);

      // Log based on duration
      if (durationMs >= verySlowOperationThresholdMs) {
        _logger.error(
          'Very slow sync operation: $operationName took ${durationMs}ms',
          metadata,
        );
      } else if (durationMs >= slowOperationThresholdMs) {
        _logger.warning(
          'Slow sync operation: $operationName took ${durationMs}ms',
          metadata,
        );
      } else if (logAllOperations) {
        _logger.debug(
          'Sync operation completed: $operationName in ${durationMs}ms',
          metadata,
        );
      }

      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;

      _logger.error(
        'Sync operation failed: $operationName after ${durationMs}ms',
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  /// Record a metric for an operation.
  void _recordMetric(String operationName, int durationMs) {
    final metric = _metrics.putIfAbsent(
      operationName,
      () => _OperationMetrics(operationName),
    );

    metric.recordDuration(durationMs);
  }

  /// Get metrics for a specific operation.
  ///
  /// Returns null if no metrics are available for the operation.
  OperationMetrics? getMetrics(String operationName) {
    final metric = _metrics[operationName];
    if (metric == null) return null;

    return OperationMetrics(
      operationName: operationName,
      executionCount: metric.executionCount,
      totalDurationMs: metric.totalDurationMs,
      averageDurationMs: metric.averageDurationMs,
      minDurationMs: metric.minDurationMs,
      maxDurationMs: metric.maxDurationMs,
      lastDurationMs: metric.lastDurationMs,
    );
  }

  /// Get metrics for all tracked operations.
  Map<String, OperationMetrics> getAllMetrics() {
    return Map.fromEntries(
      _metrics.entries.map((entry) {
        final metric = entry.value;
        return MapEntry(
          entry.key,
          OperationMetrics(
            operationName: metric.operationName,
            executionCount: metric.executionCount,
            totalDurationMs: metric.totalDurationMs,
            averageDurationMs: metric.averageDurationMs,
            minDurationMs: metric.minDurationMs,
            maxDurationMs: metric.maxDurationMs,
            lastDurationMs: metric.lastDurationMs,
          ),
        );
      }),
    );
  }

  /// Get slowest operations.
  ///
  /// Returns a list of operations sorted by average duration (slowest first).
  ///
  /// [limit] - Maximum number of operations to return
  List<OperationMetrics> getSlowestOperations({int limit = 10}) {
    final allMetrics = getAllMetrics().values.toList();
    allMetrics.sort((a, b) => b.averageDurationMs.compareTo(a.averageDurationMs));
    return allMetrics.take(limit).toList();
  }

  /// Get most frequently executed operations.
  ///
  /// Returns a list of operations sorted by execution count (most frequent first).
  ///
  /// [limit] - Maximum number of operations to return
  List<OperationMetrics> getMostFrequentOperations({int limit = 10}) {
    final allMetrics = getAllMetrics().values.toList();
    allMetrics.sort((a, b) => b.executionCount.compareTo(a.executionCount));
    return allMetrics.take(limit).toList();
  }

  /// Clear all collected metrics.
  void clearMetrics() {
    _metrics.clear();
    _logger.debug('Performance metrics cleared');
  }

  /// Log a summary of all performance metrics.
  void logSummary() {
    if (_metrics.isEmpty) {
      _logger.info('No performance metrics available');
      return;
    }

    _logger.info('=== Performance Metrics Summary ===');
    _logger.info('Total operations tracked: ${_metrics.length}');

    final slowest = getSlowestOperations(limit: 5);
    if (slowest.isNotEmpty) {
      _logger.info('\nTop 5 Slowest Operations (by average):');
      for (var i = 0; i < slowest.length; i++) {
        final metric = slowest[i];
        _logger.info(
          '  ${i + 1}. ${metric.operationName}: '
          '${metric.averageDurationMs}ms avg '
          '(${metric.executionCount} executions)',
        );
      }
    }

    final frequent = getMostFrequentOperations(limit: 5);
    if (frequent.isNotEmpty) {
      _logger.info('\nTop 5 Most Frequent Operations:');
      for (var i = 0; i < frequent.length; i++) {
        final metric = frequent[i];
        _logger.info(
          '  ${i + 1}. ${metric.operationName}: '
          '${metric.executionCount} executions '
          '(${metric.averageDurationMs}ms avg)',
        );
      }
    }

    _logger.info('===================================');
  }
}

/// Internal class for tracking operation metrics.
class _OperationMetrics {
  final String operationName;
  int executionCount = 0;
  int totalDurationMs = 0;
  int minDurationMs = 0;
  int maxDurationMs = 0;
  int lastDurationMs = 0;

  _OperationMetrics(this.operationName);

  double get averageDurationMs =>
      executionCount > 0 ? totalDurationMs / executionCount : 0.0;

  void recordDuration(int durationMs) {
    executionCount++;
    totalDurationMs += durationMs;
    lastDurationMs = durationMs;

    if (minDurationMs == 0 || durationMs < minDurationMs) {
      minDurationMs = durationMs;
    }

    if (durationMs > maxDurationMs) {
      maxDurationMs = durationMs;
    }
  }
}

/// Public metrics data class.
class OperationMetrics {
  final String operationName;
  final int executionCount;
  final int totalDurationMs;
  final double averageDurationMs;
  final int minDurationMs;
  final int maxDurationMs;
  final int lastDurationMs;

  const OperationMetrics({
    required this.operationName,
    required this.executionCount,
    required this.totalDurationMs,
    required this.averageDurationMs,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.lastDurationMs,
  });

  @override
  String toString() {
    return 'OperationMetrics($operationName: '
        'avg=${averageDurationMs.toStringAsFixed(1)}ms, '
        'count=$executionCount, '
        'min=${minDurationMs}ms, '
        'max=${maxDurationMs}ms)';
  }
}
