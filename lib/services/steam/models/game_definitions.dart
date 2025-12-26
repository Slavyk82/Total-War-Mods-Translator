/// Centralized definitions for Total War games supported by TWMT
/// This is the single source of truth for game information
library;

/// Information about a Total War game
class GameInfo {
  final String code;
  final String name;
  final String steamAppId;
  final String folderName;

  const GameInfo({
    required this.code,
    required this.name,
    required this.steamAppId,
    required this.folderName,
  });
}

/// All supported Total War games with their Steam App IDs and folder names
/// This map is the single source of truth for game definitions
const Map<String, GameInfo> supportedGames = {
  'wh3': GameInfo(
    code: 'wh3',
    name: 'Total War: WARHAMMER III',
    steamAppId: '1142710',
    folderName: 'Total War WARHAMMER III',
  ),
  'wh2': GameInfo(
    code: 'wh2',
    name: 'Total War: WARHAMMER II',
    steamAppId: '594570',
    folderName: 'Total War WARHAMMER II',
  ),
  'wh': GameInfo(
    code: 'wh',
    name: 'Total War: WARHAMMER',
    steamAppId: '364360',
    folderName: 'Total War WARHAMMER',
  ),
  'rome2': GameInfo(
    code: 'rome2',
    name: 'Total War: Rome II',
    steamAppId: '214950',
    folderName: 'Total War Rome II',
  ),
  'attila': GameInfo(
    code: 'attila',
    name: 'Total War: Attila',
    steamAppId: '325610',
    folderName: 'Total War Attila',
  ),
  'troy': GameInfo(
    code: 'troy',
    name: 'Total War: Troy',
    steamAppId: '1099410',
    folderName: 'Troy',
  ),
  '3k': GameInfo(
    code: '3k',
    name: 'Total War: Three Kingdoms',
    steamAppId: '779340',
    folderName: 'Total War THREE KINGDOMS',
  ),
  'pharaoh': GameInfo(
    code: 'pharaoh',
    name: 'Total War: Pharaoh',
    steamAppId: '1937780',
    folderName: 'Total War PHARAOH',
  ),
  'pharaoh_dynasties': GameInfo(
    code: 'pharaoh_dynasties',
    name: 'Total War: Pharaoh Dynasties',
    steamAppId: '2951630',
    folderName: 'Total War PHARAOH DYNASTIES',
  ),
};

/// Get game info by Steam App ID
GameInfo? getGameByAppId(String appId) {
  for (final game in supportedGames.values) {
    if (game.steamAppId == appId) {
      return game;
    }
  }
  return null;
}

/// Get game info by code
GameInfo? getGameByCode(String code) => supportedGames[code];
