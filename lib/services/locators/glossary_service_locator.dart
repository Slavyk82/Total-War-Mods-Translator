import 'package:get_it/get_it.dart';

import '../../repositories/glossary_repository.dart';
import '../glossary/glossary_service_impl.dart';
import '../glossary/i_glossary_service.dart';
import '../settings/settings_service.dart';
import '../shared/logging_service.dart';

/// Registers glossary-related services.
///
/// This includes:
/// - Glossary service for managing translation glossaries
class GlossaryServiceLocator {
  GlossaryServiceLocator._();

  /// Register all glossary services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering glossary services');

    locator.registerLazySingleton<IGlossaryService>(
      () => GlossaryServiceImpl(
        repository: locator<GlossaryRepository>(),
        settingsService: locator<SettingsService>(),
      ),
    );

    logging.info('Glossary services registered successfully');
  }
}
