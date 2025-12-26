import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/glossary_repository.dart';
import '../glossary/glossary_service_impl.dart';
import '../glossary/glossary_deepl_service.dart';
import '../glossary/deepl_glossary_sync_service.dart';
import '../glossary/i_glossary_service.dart';
import '../shared/logging_service.dart';

/// Registers glossary-related services.
///
/// This includes:
/// - Glossary service for managing translation glossaries
/// - DeepL glossary service for DeepL API integration
/// - DeepL sync service for automatic glossary synchronization
class GlossaryServiceLocator {
  GlossaryServiceLocator._();

  /// Register all glossary services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering glossary services');

    // Main glossary service
    locator.registerLazySingleton<IGlossaryService>(
      () => GlossaryServiceImpl(
        repository: locator<GlossaryRepository>(),
      ),
    );

    // DeepL API service
    locator.registerLazySingleton<GlossaryDeepLService>(
      () => GlossaryDeepLService(
        glossaryRepository: locator<GlossaryRepository>(),
        secureStorage: const FlutterSecureStorage(),
      ),
    );

    // DeepL sync service
    locator.registerLazySingleton<DeepLGlossarySyncService>(
      () => DeepLGlossarySyncService(
        glossaryRepository: locator<GlossaryRepository>(),
        deeplService: locator<GlossaryDeepLService>(),
        logging: locator<LoggingService>(),
      ),
    );

    logging.info('Glossary services registered successfully');
  }
}
