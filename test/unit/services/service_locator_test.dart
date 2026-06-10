import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/service_locator.dart';

// Regression tests for ServiceLocator.isInitialized.
//
// The getter used to be implemented as
// `_locator.isRegistered<DatabaseService>()`, but DatabaseService is a
// static class that is never registered in GetIt by any code path — so the
// getter was permanently false even after a fully successful initialize().
// main.dart's runZonedGuarded error handler gates on it, so every uncaught
// zone error in production was routed to debugPrint (invisible in a release
// Windows GUI build) instead of the file logger.
//
// The fix backs the getter with the init completer: true only once
// initialize() has completed successfully, false before and after reset().
// A positive 'true after initialize()' test is not feasible here because
// initialize() performs real database/file-system bootstrap (path_provider,
// sqflite file DB, full DI graph); the discriminating regression assertion
// is instead that the getter no longer keys off GetIt registration state.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await ServiceLocator.reset();
  });

  tearDown(() async {
    await ServiceLocator.reset();
  });

  test('isInitialized is false before initialize() has ever run', () {
    expect(ServiceLocator.isInitialized, isFalse);
  });

  test(
      'isInitialized is completer-backed, NOT GetIt-registration-backed: '
      'registering DatabaseService in GetIt must not flip it to true', () {
    // The old implementation (`_locator.isRegistered<DatabaseService>()`)
    // returns true here even though initialize() never ran — exactly the
    // inverse of its actual production behavior (where nothing registers
    // DatabaseService and the getter was always false). The fixed getter
    // reflects initialization state only.
    GetIt.instance.registerSingleton<DatabaseService>(DatabaseService.instance);

    expect(ServiceLocator.isInitialized, isFalse,
        reason: 'isInitialized must track initialize() completion, not '
            'whether DatabaseService happens to be registered in GetIt');
  });

  test('reset() returns isInitialized to false and keeps it truthful', () async {
    await ServiceLocator.reset();
    expect(ServiceLocator.isInitialized, isFalse);

    // Re-registering arbitrary GetIt content after a reset still must not
    // affect the getter.
    GetIt.instance.registerSingleton<DatabaseService>(DatabaseService.instance);
    expect(ServiceLocator.isInitialized, isFalse);
  });
}
