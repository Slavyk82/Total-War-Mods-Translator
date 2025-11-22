import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';

/// Service interface for Steam Workshop API operations
///
/// Provides read-only access to Steam Workshop data
abstract class IWorkshopApiService {
  /// Get Workshop mod information by ID
  ///
  /// Queries Steam Workshop API for mod details.
  ///
  /// Parameters:
  /// - [workshopId]: Steam Workshop item ID
  /// - [appId]: Game app ID (e.g., 594570 for TW:WH2)
  ///
  /// Throws:
  /// - [InvalidWorkshopIdException] if workshop ID is invalid
  /// - [WorkshopModNotFoundException] if mod doesn't exist
  /// - [WorkshopApiException] if API request fails
  Future<Result<WorkshopModInfo, SteamServiceException>> getModInfo({
    required String workshopId,
    required int appId,
  });

  /// Get information for multiple Workshop mods
  ///
  /// Batch query for multiple mods (max 100 per request).
  ///
  /// Returns partial results if some mods fail to load.
  Future<Result<List<WorkshopModInfo>, SteamServiceException>> getMultipleModInfo({
    required List<String> workshopIds,
    required int appId,
  });

  /// Check if Workshop mod exists
  ///
  /// Quick check without fetching full metadata.
  Future<Result<bool, SteamServiceException>> modExists({
    required String workshopId,
    required int appId,
  });

  /// Search Workshop items by query
  ///
  /// Note: Steam Workshop API has limited search capabilities.
  /// Consider using web scraping as fallback.
  ///
  /// Parameters:
  /// - [query]: Search query string
  /// - [appId]: Game app ID
  /// - [page]: Page number (1-indexed)
  /// - [pageSize]: Results per page (max 100)
  Future<Result<List<WorkshopModInfo>, SteamServiceException>> searchMods({
    required String query,
    required int appId,
    int page = 1,
    int pageSize = 20,
  });

  /// Check for updates on multiple mods by comparing timestamps
  ///
  /// Compares local timestamps with Steam API timestamps to detect updates.
  ///
  /// Returns map of workshop ID to boolean (true = updated, false = no update)
  Future<Result<Map<String, bool>, SteamServiceException>> checkForUpdates({
    required Map<String, int> modsWithTimestamps,
    required int appId,
  });
}
