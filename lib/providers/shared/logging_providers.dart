import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/service_locator.dart';
import '../../services/shared/i_logging_service.dart';

/// Riverpod provider for the application logger.
///
/// Bridges GetIt's [ILoggingService] registration to Riverpod so UI code can
/// depend on the logger via `ref.watch(loggingServiceProvider)`.
final loggingServiceProvider = Provider<ILoggingService>((ref) {
  return ServiceLocator.get<ILoggingService>();
});
