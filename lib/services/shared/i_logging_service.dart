import 'log_entry.dart';

export 'log_entry.dart';

/// Abstraction for the logging service.
///
/// Allows injection via Riverpod / GetIt and substitution with a mock or
/// no-op implementation in tests. The concrete [LoggingService] implements
/// this interface.
abstract class ILoggingService {
  void debug(String message, [dynamic data]);
  void info(String message, [dynamic data]);
  void warning(String message, [dynamic data]);
  void error(String message, [dynamic error, StackTrace? stackTrace]);

  /// Stream of log entries for real-time UI display.
  Stream<LogEntry> get logStream;

  /// Snapshot of recent log entries (most-recent last).
  List<LogEntry> get recentLogs;

  /// Absolute path of the current day's log file, or null if logging has not
  /// been initialized. Its parent directory holds all session log files.
  String? get logFilePath;
}
