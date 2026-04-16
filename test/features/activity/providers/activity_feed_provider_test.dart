import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/features/activity/repositories/activity_event_repository.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/selected_game_provider.dart';

import '../../../helpers/test_bootstrap.dart';

class _MockRepo extends Mock implements ActivityEventRepository {}

/// Test double for [SelectedGame] that returns a fixed [ConfiguredGame]
/// (or null) without touching settings services.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

void main() {
  late _MockRepo repo;

  setUp(() async {
    await TestBootstrap.registerFakes();
    repo = _MockRepo();
  });

  test('returns empty list on repo error', () async {
    when(
      () => repo.getRecent(
        gameCode: any(named: 'gameCode'),
        limit: 20,
      ),
    ).thenAnswer(
      (_) async => Err<List<ActivityEvent>, TWMTDatabaseException>(
        const TWMTDatabaseException('db down'),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        activityEventRepositoryProvider.overrideWithValue(repo),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(activityFeedProvider.future), isEmpty);
  });

  test('passes null gameCode when no game selected', () async {
    when(() => repo.getRecent(gameCode: null, limit: 20)).thenAnswer(
      (_) async => Ok<List<ActivityEvent>, TWMTDatabaseException>(
        const <ActivityEvent>[],
      ),
    );

    final container = ProviderContainer(
      overrides: [
        activityEventRepositoryProvider.overrideWithValue(repo),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(activityFeedProvider.future), isEmpty);
    verify(() => repo.getRecent(gameCode: null, limit: 20)).called(1);
  });

  test('filters by code of the selected game', () async {
    final events = [
      ActivityEvent(
        id: 1,
        type: ActivityEventType.glossaryEnriched,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        projectId: null,
        gameCode: 'wh3',
        payload: const {},
      ),
    ];
    when(() => repo.getRecent(gameCode: 'wh3', limit: 20)).thenAnswer(
      (_) async => Ok<List<ActivityEvent>, TWMTDatabaseException>(events),
    );

    const game = ConfiguredGame(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      path: 'C:/games/wh3',
    );

    final container = ProviderContainer(
      overrides: [
        activityEventRepositoryProvider.overrideWithValue(repo),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(game)),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(activityFeedProvider.future);
    expect(result, hasLength(1));
    expect(result.first.gameCode, 'wh3');
    verify(() => repo.getRecent(gameCode: 'wh3', limit: 20)).called(1);
  });
}
