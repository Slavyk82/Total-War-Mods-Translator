import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/repositories/activity_event_repository.dart';
import 'package:twmt/features/activity/services/activity_logger_impl.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../../helpers/test_bootstrap.dart';

class _MockRepo extends Mock implements ActivityEventRepository {}

class _MockLogger extends Mock implements ILoggingService {}

void main() {
  late _MockRepo repo;
  late _MockLogger logger;
  late ActivityLoggerImpl subject;

  setUpAll(() {
    registerFallbackValue(
      ActivityEvent(
        id: 0,
        type: ActivityEventType.glossaryEnriched,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        projectId: null,
        gameCode: null,
        payload: const {},
      ),
    );
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    repo = _MockRepo();
    logger = _MockLogger();
    subject = ActivityLoggerImpl(repository: repo, logger: logger);
  });

  test('log passes event fields to repository.insert', () async {
    when(() => repo.insert(any())).thenAnswer((invocation) async {
      final e = invocation.positionalArguments.first as ActivityEvent;
      return Ok<ActivityEvent, TWMTDatabaseException>(
        ActivityEvent(
          id: 1,
          type: e.type,
          timestamp: e.timestamp,
          projectId: e.projectId,
          gameCode: e.gameCode,
          payload: e.payload,
        ),
      );
    });

    await subject.log(
      ActivityEventType.packCompiled,
      projectId: 'p1',
      gameCode: 'wh3',
      payload: {'projectName': 'X'},
    );

    final captured = verify(() => repo.insert(captureAny())).captured.single
        as ActivityEvent;
    expect(captured.type, ActivityEventType.packCompiled);
    expect(captured.projectId, 'p1');
    expect(captured.gameCode, 'wh3');
    expect(captured.payload, {'projectName': 'X'});
  });

  test('log swallows repo Err and logs it once', () async {
    when(() => repo.insert(any())).thenAnswer(
      (_) async => Err<ActivityEvent, TWMTDatabaseException>(
        const TWMTDatabaseException('boom'),
      ),
    );

    // Must not throw.
    await subject.log(ActivityEventType.glossaryEnriched);

    verify(() => logger.error(any(), any(), any())).called(1);
  });

  test('log never rethrows even if repo throws synchronously', () async {
    when(() => repo.insert(any())).thenThrow(StateError('sync'));

    // Must not throw.
    await subject.log(ActivityEventType.glossaryEnriched);

    verify(() => logger.error(any(), any(), any())).called(1);
  });

  test('log swallows async exception from repo.insert and logs once', () async {
    when(() => repo.insert(any())).thenAnswer((_) async {
      throw StateError('async boom');
    });
    // Must not throw.
    await subject.log(ActivityEventType.glossaryEnriched);
    verify(() => logger.error(any(), any(), any())).called(1);
  });
}
