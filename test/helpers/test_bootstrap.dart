import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import 'fakes/fake_logger.dart';

/// Test-only entry point that installs baseline fakes into [ServiceLocator].
///
/// Call from `setUp` in any test that instantiates production services
/// that internally fall back to `ServiceLocator.get<...>()`. Individual
/// tests can override specific slots by calling `GetIt.I.registerSingleton`
/// (or `registerFactory`) after this runs.
class TestBootstrap {
  TestBootstrap._();

  /// Register default fakes. Idempotent — safe to call per-test. Returns a
  /// future because [ServiceLocator.reset] is async (GetIt invokes async
  /// disposers on registered singletons before clearing).
  static Future<void> registerFakes({ILoggingService? logger}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ServiceLocator.reset();
    GetIt.I.registerSingleton<ILoggingService>(logger ?? FakeLogger());
  }
}
