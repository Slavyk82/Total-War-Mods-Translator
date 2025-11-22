import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/steam/i_steam_workshop_service.dart';
import 'package:twmt/services/steam/models/workshop_item_details.dart';
import 'package:twmt/services/steam/models/workshop_item_update.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Steam Workshop service for update tracking.
///
/// Uses Steam Web API's GetPublishedFileDetails endpoint to fetch
/// Workshop item metadata and detect updates.
class SteamWorkshopServiceImpl implements ISteamWorkshopService {
  /// Steam Web API base URL
  static const String _apiBaseUrl =
      'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/';

  /// HTTP client for API requests
  final http.Client _httpClient;

  /// Logger instance
  final LoggingService _logger = LoggingService.instance;

  /// Create service with optional HTTP client (for testing)
  SteamWorkshopServiceImpl({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  Future<Result<WorkshopItemDetails, SteamException>> getWorkshopItemDetails({
    required String workshopId,
  }) async {
    try {
      // Validate Workshop ID
      if (!_isValidWorkshopId(workshopId)) {
        return Err(SteamException(
          'Invalid Workshop ID format: $workshopId',
          workshopId: workshopId,
        ));
      }

      _logger.info('Fetching Workshop item details for: $workshopId');

      // Make API request
      final response = await _httpClient.post(
        Uri.parse(_apiBaseUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'itemcount': '1',
          'publishedfileids[0]': workshopId,
        },
      );

      if (response.statusCode != 200) {
        return Err(SteamException(
          'Steam API request failed with status ${response.statusCode}',
          workshopId: workshopId,
        ));
      }

      // Parse JSON response
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final responseData = jsonData['response'] as Map<String, dynamic>?;

      if (responseData == null ||
          responseData['publishedfiledetails'] == null) {
        return Err(SteamException(
          'Invalid API response format',
          workshopId: workshopId,
        ));
      }

      final details =
          (responseData['publishedfiledetails'] as List).firstOrNull;

      if (details == null) {
        return Err(SteamException(
          'Workshop item not found',
          workshopId: workshopId,
        ));
      }

      // Check result code (1 = success)
      final result = details['result'] as int?;
      if (result != 1) {
        return Err(SteamException(
          'Workshop item not accessible (result code: $result)',
          workshopId: workshopId,
        ));
      }

      // Parse item details
      final itemDetails = _parseWorkshopItemDetails(details, workshopId);

      _logger.info(
          'Successfully fetched details for: ${itemDetails.title}');

      return Ok(itemDetails);
    } on FormatException catch (e, stackTrace) {
      return Err(SteamException(
        'Failed to parse Steam API response: $e',
        workshopId: workshopId,
        error: e,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      return Err(SteamException(
        'Failed to fetch Workshop item details: $e',
        workshopId: workshopId,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<WorkshopItemUpdate>, SteamException>> checkForUpdates({
    required Map<String, DateTime> workshopIds,
  }) async {
    try {
      if (workshopIds.isEmpty) {
        return const Ok([]);
      }

      _logger.info('Checking updates for ${workshopIds.length} Workshop items');

      // Build request body for multiple items
      final body = <String, String>{
        'itemcount': workshopIds.length.toString(),
      };

      int index = 0;
      for (final workshopId in workshopIds.keys) {
        body['publishedfileids[$index]'] = workshopId;
        index++;
      }

      // Make API request
      final response = await _httpClient.post(
        Uri.parse(_apiBaseUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode != 200) {
        return Err(SteamException(
          'Steam API request failed with status ${response.statusCode}',
        ));
      }

      // Parse JSON response
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final responseData = jsonData['response'] as Map<String, dynamic>?;

      if (responseData == null ||
          responseData['publishedfiledetails'] == null) {
        return Err(const SteamException('Invalid API response format'));
      }

      final detailsList =
          responseData['publishedfiledetails'] as List<dynamic>;
      final updates = <WorkshopItemUpdate>[];

      for (final details in detailsList) {
        final workshopId =
            (details['publishedfileid'] ?? '').toString();

        // Skip if result is not successful
        if (details['result'] != 1) {
          _logger.warning(
              'Skipping Workshop item $workshopId: result=${details['result']}');
          continue;
        }

        if (!workshopIds.containsKey(workshopId)) {
          continue;
        }

        final lastKnownUpdate = workshopIds[workshopId]!;
        final timeUpdated = details['time_updated'] as int?;

        if (timeUpdated == null) {
          _logger.warning(
              'Workshop item $workshopId has no time_updated field');
          continue;
        }

        final latestUpdate =
            DateTime.fromMillisecondsSinceEpoch(timeUpdated * 1000);
        final title = (details['title'] ?? 'Unknown').toString();

        final update = WorkshopItemUpdate.fromTimestamps(
          workshopId: workshopId,
          modName: title,
          lastKnownUpdate: lastKnownUpdate,
          latestUpdate: latestUpdate,
        );

        updates.add(update);

        if (update.hasUpdate) {
          _logger.info('Update available for $title ($workshopId)');
        }
      }

      _logger.info(
          'Found ${updates.where((u) => u.hasUpdate).length} updates out of ${updates.length} items');

      return Ok(updates);
    } on FormatException catch (e, stackTrace) {
      return Err(SteamException(
        'Failed to parse Steam API response: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      return Err(SteamException(
        'Failed to check for updates: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<DateTime, SteamException>> getLastUpdatedTime({
    required String workshopId,
  }) async {
    final result = await getWorkshopItemDetails(workshopId: workshopId);

    return result.when(
      ok: (details) => Ok(details.timeUpdated),
      err: (error) => Err(error),
    );
  }

  /// Validate Workshop ID format (must be numeric)
  bool _isValidWorkshopId(String workshopId) {
    return RegExp(r'^\d+$').hasMatch(workshopId) && workshopId.isNotEmpty;
  }

  /// Parse Workshop item details from API response
  WorkshopItemDetails _parseWorkshopItemDetails(
    Map<String, dynamic> details,
    String workshopId,
  ) {
    final timeUpdated = details['time_updated'] as int? ?? 0;
    final timeCreated = details['time_created'] as int?;
    final fileSize = details['file_size'] as int? ?? 0;

    // Parse tags
    final tagsList = details['tags'] as List<dynamic>?;
    final tags = tagsList
        ?.map((t) => (t['tag'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .toList();

    return WorkshopItemDetails(
      publishedFileId: workshopId,
      title: (details['title'] ?? 'Unknown').toString(),
      timeUpdated: DateTime.fromMillisecondsSinceEpoch(timeUpdated * 1000),
      fileSize: fileSize,
      timeCreated: timeCreated != null
          ? DateTime.fromMillisecondsSinceEpoch(timeCreated * 1000)
          : null,
      subscriptions: details['subscriptions'] as int?,
      tags: tags,
    );
  }
}
