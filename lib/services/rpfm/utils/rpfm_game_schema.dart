import 'package:path/path.dart' as path;

/// Game to schema file name mapping for RPFM operations
///
/// RPFM uses full game names (e.g., 'warhammer_3') for the --game flag,
/// but schema files use short names (e.g., 'wh3')
class RpfmGameSchema {
  RpfmGameSchema._();

  /// Map of game names to schema file name prefixes
  static const Map<String, String> _gameToSchemaMap = {
    'warhammer_3': 'wh3',
    'warhammer_2': 'wh2',
    'warhammer': 'wh',
    'three_kingdoms': '3k',
    'troy': 'troy',
    'pharaoh': 'pharaoh',
    'pharaoh_dynasties': 'pharaoh_dynasties',
    'thrones_of_britannia': 'tob',
    'attila': 'att',
    'rome_2': 'rom2',
    'shogun_2': 'sho2',
    'napoleon': 'nap',
    'empire': 'emp',
    'arena': 'arena',
  };

  /// Get schema file name for a game
  ///
  /// Returns the short schema name (e.g., 'wh3' for 'warhammer_3')
  /// Falls back to the game name itself if not found in mapping
  static String getSchemaFileName(String gameName) {
    return _gameToSchemaMap[gameName] ?? gameName;
  }

  /// Get full schema file path for a game
  ///
  /// Returns path like: schemaDir/schema_wh3.ron
  static String getSchemaFilePath(String schemaDir, String gameName) {
    final schemaFileName = getSchemaFileName(gameName);
    return path.join(schemaDir, 'schema_$schemaFileName.ron');
  }
}
