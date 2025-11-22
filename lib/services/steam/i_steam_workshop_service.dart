import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/steam/models/workshop_item_details.dart';
import 'package:twmt/services/steam/models/workshop_item_update.dart';

/// Service interface for Steam Workshop update tracking operations.
///
/// Provides methods to check for mod updates by querying Steam Workshop API
/// and comparing with local version information.
abstract class ISteamWorkshopService {
  /// Get detailed information about a Workshop item.
  ///
  /// Queries the Steam Web API for detailed metadata about a Workshop item,
  /// including update timestamp and file size.
  ///
  /// Parameters:
  /// - [workshopId]: Steam Workshop item ID
  ///
  /// Returns:
  /// - [Ok] with [WorkshopItemDetails] if successful
  /// - [Err] with [SteamException] if the request fails
  ///
  /// Throws:
  /// - [SteamException] if Workshop ID is invalid
  /// - [SteamException] if API request fails
  /// - [SteamException] if Workshop item not found
  Future<Result<WorkshopItemDetails, SteamException>> getWorkshopItemDetails({
    required String workshopId,
  });

  /// Check for updates for multiple Workshop items.
  ///
  /// Compares the latest update timestamps from Steam Workshop with the
  /// provided last known timestamps to determine which items have updates.
  ///
  /// Parameters:
  /// - [workshopIds]: List of Workshop IDs with their last known update times
  ///
  /// Returns:
  /// - [Ok] with list of [WorkshopItemUpdate] objects
  /// - [Err] with [SteamException] if the request fails
  ///
  /// The returned list will only contain items that were successfully checked.
  /// Items that fail individually will be logged but not cause the entire
  /// operation to fail.
  Future<Result<List<WorkshopItemUpdate>, SteamException>> checkForUpdates({
    required Map<String, DateTime> workshopIds,
  });

  /// Get the last updated timestamp for a Workshop item.
  ///
  /// This is a convenience method that extracts just the update timestamp
  /// without fetching all metadata.
  ///
  /// Parameters:
  /// - [workshopId]: Steam Workshop item ID
  ///
  /// Returns:
  /// - [Ok] with [DateTime] of last update
  /// - [Err] with [SteamException] if the request fails
  Future<Result<DateTime, SteamException>> getLastUpdatedTime({
    required String workshopId,
  });
}
