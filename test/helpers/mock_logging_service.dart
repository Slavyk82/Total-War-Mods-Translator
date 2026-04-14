import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Mock logger for unit and widget tests.
///
/// Use this when you need to assert log side-effects via `verify(...)`.
/// For a silent no-op logger (no verification needed), prefer
/// `test/helpers/fakes/fake_logger.dart::FakeLogger` instead.
///
/// Example:
/// ```dart
/// final logger = MockLoggingService();
/// // Pass to system-under-test, then verify log calls:
/// verify(() => logger.error(any())).called(1);
/// ```
class MockLoggingService extends Mock implements ILoggingService {}
