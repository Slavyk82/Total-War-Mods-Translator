import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/service_locator.dart';
import '../../services/shared/i_logging_service.dart';

/// Riverpod provider for the application logger.
///
/// Delegates to the ServiceLocator-registered singleton during the DI
/// migration. After Phase 3, this will become the primary access point.
final loggingServiceProvider = Provider<ILoggingService>((ref) {
  return ServiceLocator.get<ILoggingService>();
});
