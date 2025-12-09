/// Log level for scan messages
enum ScanLogLevel {
  info,
  warning,
  error,
  debug,
}

/// A log message emitted during mod scanning
class ScanLogMessage {
  final String message;
  final ScanLogLevel level;
  final DateTime timestamp;

  ScanLogMessage({
    required this.message,
    this.level = ScanLogLevel.info,
  }) : timestamp = DateTime.now();

  factory ScanLogMessage.info(String message) =>
      ScanLogMessage(message: message, level: ScanLogLevel.info);

  factory ScanLogMessage.warning(String message) =>
      ScanLogMessage(message: message, level: ScanLogLevel.warning);

  factory ScanLogMessage.error(String message) =>
      ScanLogMessage(message: message, level: ScanLogLevel.error);

  factory ScanLogMessage.debug(String message) =>
      ScanLogMessage(message: message, level: ScanLogLevel.debug);
}

