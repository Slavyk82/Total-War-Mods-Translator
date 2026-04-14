import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Reusable no-op logger fake. Override specific methods in tests that
/// need to assert log side-effects by subclassing this.
///
/// Stubs every method on [ILoggingService] — including `logStream` and
/// `recentLogs` — so production services that hit those getters during
/// instantiation do not crash with a `NoSuchMethodError` from `Fake`.
class FakeLogger extends Fake implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}

  @override
  void info(String message, [dynamic data]) {}

  @override
  void warning(String message, [dynamic data]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  Stream<LogEntry> get logStream => const Stream.empty();

  @override
  List<LogEntry> get recentLogs => const [];
}
