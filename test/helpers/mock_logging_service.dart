import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Mock logger for unit and widget tests.
///
/// Example:
/// ```dart
/// final logger = MockLoggingService();
/// // Pass to system-under-test, then verify log calls:
/// verify(() => logger.error(any())).called(1);
/// ```
class MockLoggingService extends Mock implements ILoggingService {}

/// Silent no-op logger for tests that do not care about log output.
class NoopLoggingService implements ILoggingService {
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
