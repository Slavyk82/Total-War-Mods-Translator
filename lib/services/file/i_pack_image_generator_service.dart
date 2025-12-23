import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Service interface for generating pack images with language flag overlays
///
/// Handles the creation of Steam Workshop preview images for translation packs
/// by overlaying language flags on the original mod images.
abstract class IPackImageGeneratorService {
  /// Ensure pack image exists, generating it if necessary
  ///
  /// Checks if a pack image already exists in the game data folder.
  /// If not, generates one by overlaying a language flag on the mod image.
  ///
  /// [packFileName]: Name of the pack file (e.g., "!!!!!!!!!!_fr_twmt_mod.pack")
  /// [gameDataPath]: Path to the game's data folder
  /// [languageCode]: Language code for the flag (e.g., "fr", "en", "de")
  /// [modImageUrl]: URL to the mod's Steam Workshop image (optional)
  /// [localModImagePath]: Local path to the mod image (optional, used if URL fails)
  /// [generateImage]: If false, skip generation entirely
  /// [useAppIcon]: If true, use the TWMT app icon as the base image instead of mod image
  ///
  /// Returns the path to the generated image, or null if:
  /// - Generation is disabled
  /// - Image already exists
  /// - No source image available
  Future<Result<String?, FileServiceException>> ensurePackImage({
    required String packFileName,
    required String gameDataPath,
    required String languageCode,
    String? modImageUrl,
    String? localModImagePath,
    required bool generateImage,
    bool useAppIcon = false,
  });
}
