import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

void main() {
  test('LoggingService implements ILoggingService', () {
    final svc = LoggingService.instance;
    expect(svc, isA<ILoggingService>());
  });

  test('ILoggingService exposes the four log levels', () {
    final svc = LoggingService.instance as ILoggingService;
    // Should not throw — just check call sites compile and don't crash
    svc.debug('test');
    svc.info('test');
    svc.warning('test');
    svc.error('test');
  });
}
