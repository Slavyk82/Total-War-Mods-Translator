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
