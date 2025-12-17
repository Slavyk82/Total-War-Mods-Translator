import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';

part 'selected_game_provider.g.dart';

/// Model representing a configured game
class ConfiguredGame {
  final String code;
  final String name;
  final String path;

  const ConfiguredGame({
    required this.code,
    required this.name,
    required this.path,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfiguredGame &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// Available games with their display names
const Map<String, String> _availableGames = {
  'wh3': 'Total War: WARHAMMER III',
  'wh2': 'Total War: WARHAMMER II',
  'wh': 'Total War: WARHAMMER',
  'rome2': 'Total War: Rome II',
  'attila': 'Total War: Attila',
  'troy': 'Total War: Troy',
  '3k': 'Total War: Three Kingdoms',
  'pharaoh': 'Total War: Pharaoh',
  'pharaoh_dynasties': 'Total War: Pharaoh Dynasties',
};

/// Provider for the list of configured games (games with a path set in settings)
@riverpod
Future<List<ConfiguredGame>> configuredGames(Ref ref) async {
  final settings = await ref.watch(generalSettingsProvider.future);
  final configuredGames = <ConfiguredGame>[];

  for (final entry in _availableGames.entries) {
    final gameCode = entry.key;
    final gameName = entry.value;
    final pathKey = _getGamePathKey(gameCode);
    final path = settings[pathKey] ?? '';

    if (path.isNotEmpty) {
      configuredGames.add(ConfiguredGame(
        code: gameCode,
        name: gameName,
        path: path,
      ));
    }
  }

  return configuredGames;
}

/// Provider for the currently selected game
@riverpod
class SelectedGame extends _$SelectedGame {
  static const String _selectedGameKey = 'selected_game_code';

  @override
  Future<ConfiguredGame?> build() async {
    final settingsService = ref.read(settingsServiceProvider);
    final configuredGamesList = await ref.watch(configuredGamesProvider.future);

    if (configuredGamesList.isEmpty) {
      return null;
    }

    // Try to load the previously selected game
    final savedGameCode = await settingsService.getString(_selectedGameKey);
    if (savedGameCode.isNotEmpty) {
      // Check if the saved game still exists in configured games
      try {
        final savedGame = configuredGamesList.firstWhere(
          (game) => game.code == savedGameCode,
        );
        return savedGame;
      } catch (_) {
        // Saved game no longer configured, fall through to select first game
      }
    }

    // Default to the first configured game and save it
    final firstGame = configuredGamesList.first;
    await settingsService.setString(_selectedGameKey, firstGame.code);
    return firstGame;
  }

  /// Select a specific game
  Future<void> selectGame(ConfiguredGame game) async {
    final settingsService = ref.read(settingsServiceProvider);
    await settingsService.setString(_selectedGameKey, game.code);
    state = AsyncData(game);
  }

  /// Clear the selected game
  Future<void> clearSelection() async {
    final settingsService = ref.read(settingsServiceProvider);
    await settingsService.setString(_selectedGameKey, '');
    state = const AsyncData(null);
  }
}

String _getGamePathKey(String gameCode) {
  switch (gameCode) {
    case 'wh3':
      return SettingsKeys.gamePathWh3;
    case 'wh2':
      return SettingsKeys.gamePathWh2;
    case 'wh':
      return SettingsKeys.gamePathWh;
    case 'rome2':
      return SettingsKeys.gamePathRome2;
    case 'attila':
      return SettingsKeys.gamePathAttila;
    case 'troy':
      return SettingsKeys.gamePathTroy;
    case '3k':
      return SettingsKeys.gamePath3k;
    case 'pharaoh':
      return SettingsKeys.gamePathPharaoh;
    case 'pharaoh_dynasties':
      return SettingsKeys.gamePathPharaohDynasties;
    default:
      throw ArgumentError('Unknown game code: $gameCode');
  }
}



