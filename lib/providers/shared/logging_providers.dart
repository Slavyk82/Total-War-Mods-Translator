import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/service_locator.dart';
import '../../services/shared/i_logging_service.dart';
import '../../services/shared/logging_service.dart';

/// Riverpod provider for the application logger.
///
/// Delegates to the ServiceLocator-registered singleton during the DI
/// migration. After Phase 3, this will become the primary access point.
///
/// Falls back to the concrete [LoggingService.instance] when the
/// ServiceLocator has not been initialized (e.g. in widget tests that
/// do not bootstrap the full DI container).
final loggingServiceProvider = Provider<ILoggingService>((ref) {
  if (ServiceLocator.isRegistered<ILoggingService>()) {
    return ServiceLocator.get<ILoggingService>();
  }
  return LoggingService.instance;
});
