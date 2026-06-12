import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/settings_providers.dart';

class MockSettingsService extends Mock implements SettingsService {}

/// Permissive stubs so any settings notifier `build()` can complete.
void _stubReads(MockSettingsService mock) {
  when(() => mock.getString(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => '');
  when(() => mock.getBool(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => true);
  when(() => mock.getInt(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => 500);
  when(() => mock.getPackPrefix()).thenAnswer((_) async => '!!!!!!!!!!');
  when(() => mock.setString(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setBool(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setInt(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
}

/// Full 9-key game-path settings map (missing keys default to '').
Map<String, String> _settingsMap(Map<String, String> paths) => {
      SettingsKeys.gamePathWh3: paths[SettingsKeys.gamePathWh3] ?? '',
      SettingsKeys.gamePathWh2: paths[SettingsKeys.gamePathWh2] ?? '',
      SettingsKeys.gamePathWh: paths[SettingsKeys.gamePathWh] ?? '',
      SettingsKeys.gamePathRome2: paths[SettingsKeys.gamePathRome2] ?? '',
      SettingsKeys.gamePathAttila: paths[SettingsKeys.gamePathAttila] ?? '',
      SettingsKeys.gamePathTroy: paths[SettingsKeys.gamePathTroy] ?? '',
      SettingsKeys.gamePath3k: paths[SettingsKeys.gamePath3k] ?? '',
      SettingsKeys.gamePathPharaoh: paths[SettingsKeys.gamePathPharaoh] ?? '',
      SettingsKeys.gamePathPharaohDynasties:
          paths[SettingsKeys.gamePathPharaohDynasties] ?? '',
    };

/// Fake GeneralSettings notifier returning a fixed map, so `configuredGames`
/// reads deterministic game paths. `generalSettingsProvider` is a codegen
/// AsyncNotifier, so it must be overridden with a notifier factory (not an
/// `(ref) async => value` closure).
class _FakeGeneralSettings extends GeneralSettings {
  _FakeGeneralSettings(this._data);
  final Map<String, String> _data;
  @override
  Future<Map<String, String>> build() async => _data;
}

void main() {
  group('ConfiguredGame model', () {
    test('equality is by code only (name/path ignored)', () {
      const a = ConfiguredGame(code: 'wh3', name: 'A', path: 'C:/a');
      const b = ConfiguredGame(code: 'wh3', name: 'B', path: 'D:/b');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different codes are not equal', () {
      const a = ConfiguredGame(code: 'wh3', name: 'N', path: 'C:/p');
      const b = ConfiguredGame(code: 'wh2', name: 'N', path: 'C:/p');
      expect(a, isNot(equals(b)));
    });

    test('identical instance is equal to itself', () {
      const a = ConfiguredGame(code: 'rome2', name: 'Rome', path: 'C:/r');
      expect(a, equals(a));
    });

    test('not equal to an unrelated type', () {
      const a = ConfiguredGame(code: 'wh3', name: 'N', path: 'C:/p');
      expect(a == 'wh3', isFalse);
    });

    test('hashCode matches code.hashCode', () {
      const a = ConfiguredGame(code: 'attila', name: 'X', path: 'Y');
      expect(a.hashCode, equals('attila'.hashCode));
    });

    test('stores code, name and path verbatim', () {
      const a = ConfiguredGame(code: 'troy', name: 'Troy', path: 'C:/troy');
      expect(a.code, 'troy');
      expect(a.name, 'Troy');
      expect(a.path, 'C:/troy');
    });
  });

  group('configuredGames provider', () {
    late ProviderContainer container;

    void build(Map<String, String> paths) {
      container = ProviderContainer(overrides: [
        generalSettingsProvider
            .overrideWith(() => _FakeGeneralSettings(_settingsMap(paths))),
      ]);
    }

    tearDown(() => container.dispose());

    test('returns no games when every path is empty', () async {
      build(const {});
      final games = await container.read(configuredGamesProvider.future);
      expect(games, isEmpty);
    });

    test('returns a single game with correct code/name/path', () async {
      build({SettingsKeys.gamePathWh3: 'C:/wh3'});
      final games = await container.read(configuredGamesProvider.future);

      expect(games, hasLength(1));
      expect(games.first.code, 'wh3');
      expect(games.first.name, 'Total War: WARHAMMER III');
      expect(games.first.path, 'C:/wh3');
    });

    test('returns only games whose path is non-empty', () async {
      build({
        SettingsKeys.gamePathWh3: 'C:/wh3',
        SettingsKeys.gamePathWh2: '', // empty => excluded
        SettingsKeys.gamePathRome2: 'C:/rome2',
      });
      final games = await container.read(configuredGamesProvider.future);

      final codes = games.map((g) => g.code).toList();
      expect(codes, containsAll(<String>['wh3', 'rome2']));
      expect(codes, isNot(contains('wh2')));
      expect(games, hasLength(2));
    });

    test('maps every game code to its display name and path key', () async {
      build({
        SettingsKeys.gamePathWh3: 'p_wh3',
        SettingsKeys.gamePathWh2: 'p_wh2',
        SettingsKeys.gamePathWh: 'p_wh',
        SettingsKeys.gamePathRome2: 'p_rome2',
        SettingsKeys.gamePathAttila: 'p_attila',
        SettingsKeys.gamePathTroy: 'p_troy',
        SettingsKeys.gamePath3k: 'p_3k',
        SettingsKeys.gamePathPharaoh: 'p_pharaoh',
        SettingsKeys.gamePathPharaohDynasties: 'p_pd',
      });
      final games = await container.read(configuredGamesProvider.future);

      final byCode = {for (final g in games) g.code: g};
      expect(games, hasLength(9));
      expect(byCode['wh3']!.name, 'Total War: WARHAMMER III');
      expect(byCode['wh2']!.name, 'Total War: WARHAMMER II');
      expect(byCode['wh']!.name, 'Total War: WARHAMMER');
      expect(byCode['rome2']!.name, 'Total War: Rome II');
      expect(byCode['attila']!.name, 'Total War: Attila');
      expect(byCode['troy']!.name, 'Total War: Troy');
      expect(byCode['3k']!.name, 'Total War: Three Kingdoms');
      expect(byCode['pharaoh']!.name, 'Total War: Pharaoh');
      expect(byCode['pharaoh_dynasties']!.name, 'Total War: Pharaoh Dynasties');
      // _getGamePathKey wiring proven: each path came back under its own key.
      expect(byCode['pharaoh_dynasties']!.path, 'p_pd');
      expect(byCode['3k']!.path, 'p_3k');
    });
  });

  group('SelectedGame notifier', () {
    late MockSettingsService mockService;
    late ProviderContainer container;

    ProviderContainer makeContainer(Map<String, String> paths) {
      return ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(mockService),
        generalSettingsProvider
            .overrideWith(() => _FakeGeneralSettings(_settingsMap(paths))),
      ]);
    }

    setUp(() {
      mockService = MockSettingsService();
      _stubReads(mockService);
    });

    tearDown(() => container.dispose());

    test('build() returns null when no games are configured', () async {
      container = makeContainer(const {});
      final selected = await container.read(selectedGameProvider.future);
      expect(selected, isNull);
    });

    test('build() defaults to the first configured game and persists it',
        () async {
      // No saved game => getString(selected_game_code) returns '' (stub).
      container = makeContainer({SettingsKeys.gamePathWh3: 'C:/wh3'});

      final selected = await container.read(selectedGameProvider.future);

      expect(selected, isNotNull);
      expect(selected!.code, 'wh3');
      // Default selection is saved back under the selected-game key.
      verify(() => mockService.setString('selected_game_code', 'wh3'))
          .called(1);
    });

    test('build() restores a previously saved game when still configured',
        () async {
      when(() => mockService.getString('selected_game_code',
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'rome2');

      container = makeContainer({
        SettingsKeys.gamePathWh3: 'C:/wh3',
        SettingsKeys.gamePathRome2: 'C:/rome2',
      });

      final selected = await container.read(selectedGameProvider.future);

      expect(selected!.code, 'rome2');
      // Restoring a still-valid saved game does not re-persist a default.
      verifyNever(() => mockService.setString('selected_game_code', 'wh3'));
    });

    test(
        'build() falls back to first game when the saved code is no longer configured',
        () async {
      // Saved game no longer has a configured path => fall through to first.
      when(() => mockService.getString('selected_game_code',
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'pharaoh');

      container = makeContainer({SettingsKeys.gamePathWh3: 'C:/wh3'});

      final selected = await container.read(selectedGameProvider.future);

      expect(selected!.code, 'wh3');
      verify(() => mockService.setString('selected_game_code', 'wh3'))
          .called(1);
    });

    test('selectGame persists the code and updates state', () async {
      container = makeContainer({
        SettingsKeys.gamePathWh3: 'C:/wh3',
        SettingsKeys.gamePathWh2: 'C:/wh2',
      });
      await container.read(selectedGameProvider.future);

      const target = ConfiguredGame(
        code: 'wh2',
        name: 'Total War: WARHAMMER II',
        path: 'C:/wh2',
      );
      await container.read(selectedGameProvider.notifier).selectGame(target);

      verify(() => mockService.setString('selected_game_code', 'wh2'))
          .called(1);
      final state = await container.read(selectedGameProvider.future);
      expect(state!.code, 'wh2');
    });

    test('clearSelection persists an empty code and nulls the state', () async {
      container = makeContainer({SettingsKeys.gamePathWh3: 'C:/wh3'});
      await container.read(selectedGameProvider.future);

      await container.read(selectedGameProvider.notifier).clearSelection();

      verify(() => mockService.setString('selected_game_code', '')).called(1);
      final state = await container.read(selectedGameProvider.future);
      expect(state, isNull);
    });
  });
}
