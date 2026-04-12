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
}
