import 'package:twmt/services/shared/i_logging_service.dart';

/// Silent logger for tests that do not need to assert on logging output.
class NoopLogger implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}

  @override
  void info(String message, [dynamic data]) {}

  @override
  void warning(String message, [dynamic data]) {}

  @override
  void error(String message, [dynamic error, StackTrace? stackTrace]) {}

  @override
  Stream<LogEntry> get logStream => const Stream.empty();

  @override
  List<LogEntry> get recentLogs => const [];
}
