import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/llm/utils/rate_limiter.dart';

/// Implementation of Workshop API service
///
/// Uses Steam Web API to query Workshop item metadata
class WorkshopApiServiceImpl implements IWorkshopApiService {
  /// Steam Web API base URL
  static const String _apiBaseUrl =
      'https://api.steampowered.com/ISteamRemoteStorage/';

  /// GetPublishedFileDetails endpoint
  static const String _fileDetailsEndpoint = 'GetPublishedFileDetails/v1/';

  /// Dio client for API requests
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Logger
  final LoggingService _logger = LoggingService.instance;

  /// Rate limiter (100 requests per minute)
  final RateLimiter _rateLimiter = RateLimiter(requestsPerMinute: 100);

  @override
  Future<Result<WorkshopModInfo, SteamServiceException>> getModInfo({
    required String workshopId,
    required int appId,
  }) async {
    try {
      // Validate Workshop ID
      if (!_isValidWorkshopId(workshopId)) {
        return Err(InvalidWorkshopIdException(
          'Invalid Workshop ID format',
          invalidId: workshopId,
        ));
      }

      // Wait for rate limit
      await _rateLimiter.acquire();

      _logger.info('Fetching Workshop mod info: $workshopId');

      // Call Steam API
      final response = await _dio.post(
        _fileDetailsEndpoint,
        data: {
          'itemcount': 1,
          'publishedfileids[0]': workshopId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode != 200) {
        return Err(WorkshopApiException(
          'API request failed',
          statusCode: response.statusCode,
          workshopId: workshopId,
        ));
      }

      // Parse response
      final data = response.data;
      if (data == null ||
          data['response'] == null ||
          data['response']['publishedfiledetails'] == null) {
        return Err(WorkshopApiException(
          'Invalid API response format',
          workshopId: workshopId,
        ));
      }

      final details = data['response']['publishedfiledetails'][0];

      // Check if mod exists
      if (details['result'] != 1) {
        return Err(WorkshopModNotFoundException(
          'Workshop mod not found or not accessible',
          workshopId: workshopId,
        ));
      }

      // Parse mod info
      final modInfo = _parseModInfo(details, workshopId, appId);

      _logger.info('Successfully fetched mod info: ${modInfo.title}');

      return Ok(modInfo);
    } on DioException catch (e, stackTrace) {
      return Err(WorkshopApiException(
        'Network error: ${e.message}',
        statusCode: e.response?.statusCode,
        workshopId: workshopId,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      return Err(WorkshopApiException(
        'Failed to get mod info: $e',
        workshopId: workshopId,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<WorkshopModInfo>, SteamServiceException>>
      getMultipleModInfo({
    required List<String> workshopIds,
    required int appId,
  }) async {
    try {
      // Validate all IDs
      for (final id in workshopIds) {
        if (!_isValidWorkshopId(id)) {
          return Err(InvalidWorkshopIdException(
            'Invalid Workshop ID format',
            invalidId: id,
          ));
        }
      }

      // Limit to 100 items per request (Steam API limit)
      if (workshopIds.length > 100) {
        return Err(const WorkshopApiException(
          'Cannot fetch more than 100 items at once',
        ));
      }

      // Wait for rate limit
      await _rateLimiter.acquire();

      _logger.info('Fetching ${workshopIds.length} Workshop mods');

      // Build request data
      final requestData = <String, dynamic>{
        'itemcount': workshopIds.length,
      };

      for (int i = 0; i < workshopIds.length; i++) {
        requestData['publishedfileids[$i]'] = workshopIds[i];
      }

      // Call Steam API
      final response = await _dio.post(
        _fileDetailsEndpoint,
        data: requestData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode != 200) {
        return Err(WorkshopApiException(
          'API request failed',
          statusCode: response.statusCode,
        ));
      }

      // Parse response
      final data = response.data;
      if (data == null ||
          data['response'] == null ||
          data['response']['publishedfiledetails'] == null) {
        return Err(const WorkshopApiException('Invalid API response format'));
      }

      final detailsList = data['response']['publishedfiledetails'] as List;
      final modInfoList = <WorkshopModInfo>[];

      for (final details in detailsList) {
        // Skip failed items
        if (details['result'] != 1) {
          _logger.warning(
              'Skipping mod ${details['publishedfileid']}: result=${details['result']}');
          continue;
        }

        final itemId = details['publishedfileid'].toString();
        
        final modInfo = _parseModInfo(
          details,
          itemId,
          appId,
        );
        modInfoList.add(modInfo);
      }

      _logger.info(
          'Successfully fetched ${modInfoList.length}/${workshopIds.length} mods');

      return Ok(modInfoList);
    } on DioException catch (e, stackTrace) {
      return Err(WorkshopApiException(
        'Network error: ${e.message}',
        statusCode: e.response?.statusCode,
        stackTrace: stackTrace,
      ));
    } catch (e, stackTrace) {
      return Err(WorkshopApiException(
        'Failed to get multiple mod info: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<bool, SteamServiceException>> modExists({
    required String workshopId,
    required int appId,
  }) async {
    final result = await getModInfo(workshopId: workshopId, appId: appId);

    if (result is Ok) {
      return const Ok(true);
    } else if (result.error is WorkshopModNotFoundException) {
      return const Ok(false);
    } else {
      return Err(result.error);
    }
  }

  @override
  Future<Result<List<WorkshopModInfo>, SteamServiceException>> searchMods({
    required String query,
    required int appId,
    int page = 1,
    int pageSize = 20,
  }) async {
    // Note: Steam Workshop API has very limited search capabilities
    // The official API doesn't support text search directly
    // This would require web scraping or using undocumented endpoints
    // For now, return an error indicating not implemented

    return Err(const WorkshopApiException(
      'Search not implemented. Steam Workshop API does not support text search. '
      'Consider using web scraping or Workshop ID direct lookup.',
    ));
  }

  @override
  Future<Result<Map<String, bool>, SteamServiceException>> checkForUpdates({
    required Map<String, int> modsWithTimestamps,
    required int appId,
  }) async {
    try {
      if (modsWithTimestamps.isEmpty) {
        return const Ok({});
      }

      _logger.info('Checking updates for ${modsWithTimestamps.length} mods');

      // Fetch current info for all mods
      final workshopIds = modsWithTimestamps.keys.toList();
      final result = await getMultipleModInfo(
        workshopIds: workshopIds,
        appId: appId,
      );

      if (result is Err) {
        return Err(result.error);
      }

      final currentModInfos = (result as Ok<List<WorkshopModInfo>, SteamServiceException>).value;

      // Compare timestamps
      final updateMap = <String, bool>{};

      for (final modInfo in currentModInfos) {
        final localTimestamp = modsWithTimestamps[modInfo.workshopId];
        final remoteTimestamp = modInfo.timeUpdated;

        if (localTimestamp == null || remoteTimestamp == null) {
          updateMap[modInfo.workshopId] = false;
          continue;
        }

        // Update available if remote timestamp is newer
        updateMap[modInfo.workshopId] = remoteTimestamp > localTimestamp;
      }

      // Mark missing mods as not updated
      for (final workshopId in workshopIds) {
        if (!updateMap.containsKey(workshopId)) {
          updateMap[workshopId] = false;
        }
      }

      final updatedCount = updateMap.values.where((updated) => updated).length;
      _logger.info('Found $updatedCount mods with updates');

      return Ok(updateMap);
    } catch (e, stackTrace) {
      return Err(WorkshopApiException(
        'Failed to check for updates: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Validate Workshop ID format
  bool _isValidWorkshopId(String workshopId) {
    return RegExp(r'^\d+$').hasMatch(workshopId) && workshopId.isNotEmpty;
  }

  /// Parse int from dynamic value (handles String, int, double, null)
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      final parsedDouble = double.tryParse(value);
      return parsedDouble?.toInt();
    }
    return null;
  }

  /// Parse mod info from API response
  WorkshopModInfo _parseModInfo(
    Map<String, dynamic> details,
    String workshopId,
    int appId,
  ) {
    // Parse tags
    final tagsList = details['tags'] as List?;
    final tags = tagsList
        ?.map((t) => t['tag']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();

    return WorkshopModInfo(
      workshopId: workshopId,
      title: details['title']?.toString() ?? 'Unknown',
      workshopUrl:
          'https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId',
      fileSize: _parseInt(details['file_size']),
      timeUpdated: _parseInt(details['time_updated']),
      timeCreated: _parseInt(details['time_created']),
      subscriptions: _parseInt(details['subscriptions']),
      tags: tags,
      appId: appId,
    );
  }
}
