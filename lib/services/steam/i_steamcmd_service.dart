import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/steamcmd_download_result.dart';

/// Service interface for SteamCMD operations
///
/// Handles downloading Workshop mods using SteamCMD
abstract class ISteamCmdService {
  /// Stream of download progress (0.0 to 1.0)
  Stream<double> get progressStream;

  /// Download a Workshop mod by ID
  ///
  /// Downloads the mod to the specified directory or default workshop cache.
  /// Returns download result with metadata.
  ///
  /// Parameters:
  /// - [workshopId]: Steam Workshop item ID
  /// - [appId]: Game app ID (e.g., 594570 for TW:WH2)
  /// - [outputDirectory]: Optional custom download directory
  /// - [forceUpdate]: Force re-download even if already cached
  ///
  /// Throws:
  /// - [InvalidWorkshopIdException] if workshop ID is invalid
  /// - [WorkshopDownloadException] if download fails
  /// - [SteamCmdNotFoundException] if SteamCMD not available
  Future<Result<SteamCmdDownloadResult, SteamServiceException>> downloadMod({
    required String workshopId,
    required int appId,
    String? outputDirectory,
    bool forceUpdate = false,
  });

  /// Check if a Workshop mod needs updating
  ///
  /// Compares local mod timestamp with Workshop metadata.
  ///
  /// Returns true if update available, false if up-to-date.
  Future<Result<bool, SteamServiceException>> checkForUpdate({
    required String workshopId,
    required int appId,
    required String localPath,
  });

  /// Get local mod directory path
  ///
  /// Returns the path where a Workshop mod would be downloaded.
  Future<String> getModPath({
    required String workshopId,
    required int appId,
  });

  /// Cancel current download operation
  Future<void> cancel();

  /// Check if SteamCMD is available and ready
  Future<bool> isSteamCmdAvailable();

  /// Get SteamCMD version
  Future<Result<String, SteamServiceException>> getSteamCmdVersion();
}
