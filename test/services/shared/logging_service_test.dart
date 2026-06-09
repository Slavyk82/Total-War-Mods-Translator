import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/shared/log_entry.dart';

void main() {
  group('LoggingService recent-logs buffer', () {
    setUp(() => LoggingService.instance.clearRecentLogs());

    test('caps recentLogs at maxRecentLogs and evicts oldest', () {
      expect(LoggingService.maxRecentLogs, 5000);
      final logger = LoggingService.instance;
      for (var i = 0; i < LoggingService.maxRecentLogs + 10; i++) {
        logger.info('entry $i');
      }
      expect(logger.recentLogs.length, LoggingService.maxRecentLogs);
      expect(
        logger.recentLogs.last.message,
        'entry ${LoggingService.maxRecentLogs + 9}',
      );
    });
  });

  group('LogEntry.colorForLevel', () {
    test('maps known levels and defaults unknown to gray', () {
      expect(LogEntry.colorForLevel('ERROR'), 0xFFE53935);
      expect(LogEntry.colorForLevel('WARN'), 0xFFFFA726);
      expect(LogEntry.colorForLevel('INFO'), 0xFF42A5F5);
      expect(LogEntry.colorForLevel('DEBUG'), 0xFF78909C);
      expect(LogEntry.colorForLevel('ANYTHING'), 0xFF78909C);
    });
  });
}
