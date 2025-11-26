import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// A structured log entry with level, message, and optional data.
class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final dynamic data;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.data,
  });

  /// Format the log entry as a string.
  String format() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}] [$level] $message');
    if (data != null) {
      buffer.write(' | Data: $data');
    }
    return buffer.toString();
  }

  /// Get the color for this log level (for terminal display).
  int get levelColor {
    switch (level) {
      case 'ERROR':
        return 0xFFE53935; // Red
      case 'WARN':
        return 0xFFFFA726; // Orange
      case 'INFO':
        return 0xFF42A5F5; // Blue
      case 'DEBUG':
      default:
        return 0xFF78909C; // Gray
    }
  }
}

/// Logging service for TWMT application.
///
/// Provides structured logging to console and file with different log levels.
/// Logs are stored in AppData\Local\TWMT\logs on Windows.
///
/// Supports real-time log streaming via [logStream] for UI display.
class LoggingService {
  LoggingService._();

  static final LoggingService _instance = LoggingService._();
  static LoggingService get instance => _instance;

  File? _logFile;
  bool _initialized = false;

  /// Stream controller for real-time log streaming.
  final _logStreamController = StreamController<LogEntry>.broadcast();

  /// Stream of log entries for real-time monitoring.
  ///
  /// Use this stream to display logs in UI components like a terminal widget.
  Stream<LogEntry> get logStream => _logStreamController.stream;

  /// Recent log entries buffer for displaying history.
  final List<LogEntry> _recentLogs = [];

  /// Maximum number of recent logs to keep in memory.
  static const int maxRecentLogs = 500;

  /// Get recent log entries (for initial display when opening terminal).
  List<LogEntry> get recentLogs => List.unmodifiable(_recentLogs);

  /// Initialize the logging service.
  ///
  /// Creates the log directory and file if they don't exist.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Get local application directory (AppData\Local\TWMT on Windows)
      final directory = await getApplicationCacheDirectory();
      final logsDir = Directory(path.join(directory.path, 'logs'));

      // Create logs directory if it doesn't exist
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Create log file with date in filename
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final logFileName = 'twmt_$dateStr.log';
      _logFile = File(path.join(logsDir.path, logFileName));

      _initialized = true;
      info('Logging service initialized', {'logFile': _logFile!.path});
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('Failed to initialize logging service: $e');
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  /// Log a debug message.
  ///
  /// Debug messages are only shown in development builds.
  void debug(String message, [dynamic data]) {
    _log('DEBUG', message, data);
  }

  /// Log an info message.
  ///
  /// Info messages indicate normal operation.
  void info(String message, [dynamic data]) {
    _log('INFO', message, data);
  }

  /// Log a warning message.
  ///
  /// Warnings indicate potential issues that don't prevent operation.
  void warning(String message, [dynamic data]) {
    _log('WARN', message, data);
  }

  /// Log an error message.
  ///
  /// Errors indicate failures that prevent normal operation.
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    final errorData = <String, dynamic>{};
    if (error != null) {
      errorData['error'] = error.toString();
    }
    if (stackTrace != null) {
      errorData['stackTrace'] = stackTrace.toString();
    }

    _log('ERROR', message, errorData.isEmpty ? null : errorData);
  }

  /// Internal logging method.
  void _log(String level, String message, [dynamic data]) {
    final timestamp = DateTime.now();

    // Create structured log entry
    final entry = LogEntry(
      timestamp: timestamp,
      level: level,
      message: message,
      data: data,
    );

    final logLine = entry.format();

    // Always log to console
    // ignore: avoid_print
    print(logLine);

    // Add to recent logs buffer
    _recentLogs.add(entry);
    if (_recentLogs.length > maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    // Emit to stream for real-time listeners
    if (!_logStreamController.isClosed) {
      _logStreamController.add(entry);
    }

    // Log to file if initialized
    if (_initialized && _logFile != null) {
      try {
        _logFile!.writeAsStringSync(
          '$logLine\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (e) {
        // ignore: avoid_print
        print('Failed to write to log file: $e');
      }
    }
  }

  /// Clear recent logs buffer.
  void clearRecentLogs() {
    _recentLogs.clear();
  }

  /// Dispose the logging service (close streams).
  void dispose() {
    _logStreamController.close();
  }

  /// Get the current log file path.
  String? get logFilePath => _logFile?.path;

  /// Check if logging is initialized.
  bool get isInitialized => _initialized;

  /// Clear old log files (keep last 7 days).
  Future<void> cleanOldLogs({int daysToKeep = 7}) async {
    if (!_initialized || _logFile == null) return;

    try {
      final logsDir = _logFile!.parent;
      final files = await logsDir.list().toList();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.log')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            info('Deleted old log file', {'path': entity.path});
          }
        }
      }
    } catch (e, stackTrace) {
      error('Failed to clean old logs', e, stackTrace);
    }
  }
}
