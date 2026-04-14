import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import 'fakes/fake_logger.dart';
import 'test_bootstrap.dart';

void main() {
  test('registerFakes installs a FakeLogger by default', () async {
    await TestBootstrap.registerFakes();
    expect(ServiceLocator.get<ILoggingService>(), isA<FakeLogger>());
  });

  test('registerFakes honors logger override', () async {
    final custom = FakeLogger();
    await TestBootstrap.registerFakes(logger: custom);
    expect(ServiceLocator.get<ILoggingService>(), same(custom));
  });

  test('registerFakes is idempotent', () async {
    await TestBootstrap.registerFakes();
    await TestBootstrap.registerFakes();
    expect(ServiceLocator.get<ILoggingService>(), isA<FakeLogger>());
  });
}
