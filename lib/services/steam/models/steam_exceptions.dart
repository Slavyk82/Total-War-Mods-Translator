/// Exceptions for Steam services
///
/// Provides specialized exception types for Steam-related operations
library;

/// Base exception for all Steam service errors
class SteamServiceException implements Exception {
  final String message;
  final String code;
  final StackTrace? stackTrace;

  const SteamServiceException(
    this.message, {
    required this.code,
    this.stackTrace,
  });

  @override
  String toString() => 'SteamServiceException($code): $message';
}

/// SteamCMD not found or not installed
class SteamCmdNotFoundException extends SteamServiceException {
  final String? searchedPaths;

  const SteamCmdNotFoundException(
    super.message, {
    this.searchedPaths,
  }) : super(code: 'STEAMCMD_NOT_FOUND');

  @override
  String toString() {
    if (searchedPaths != null) {
      return 'SteamCmdNotFoundException: $message\nSearched: $searchedPaths';
    }
    return 'SteamCmdNotFoundException: $message';
  }
}

/// SteamCMD download failed
class SteamCmdDownloadException extends SteamServiceException {
  const SteamCmdDownloadException(
    super.message, {
    super.stackTrace,
  }) : super(code: 'STEAMCMD_DOWNLOAD_FAILED');
}

/// SteamCMD initialization failed
class SteamCmdInitializationException extends SteamServiceException {
  const SteamCmdInitializationException(
    super.message, {
    super.stackTrace,
  }) : super(code: 'STEAMCMD_INIT_FAILED');
}

/// Workshop mod download failed
class WorkshopDownloadException extends SteamServiceException {
  final String? workshopId;

  const WorkshopDownloadException(
    super.message, {
    this.workshopId,
    super.stackTrace,
  }) : super(code: 'WORKSHOP_DOWNLOAD_FAILED');

  @override
  String toString() {
    if (workshopId != null) {
      return 'WorkshopDownloadException(ID: $workshopId): $message';
    }
    return 'WorkshopDownloadException: $message';
  }
}

/// Workshop API request failed
class WorkshopApiException extends SteamServiceException {
  final int? statusCode;
  final String? workshopId;

  const WorkshopApiException(
    super.message, {
    this.statusCode,
    this.workshopId,
    super.stackTrace,
  }) : super(code: 'WORKSHOP_API_FAILED');

  @override
  String toString() {
    final parts = ['WorkshopApiException'];
    if (workshopId != null) parts.add('ID: $workshopId');
    if (statusCode != null) parts.add('Status: $statusCode');
    return '${parts.join(' ')}: $message';
  }
}

/// Workshop mod not found
class WorkshopModNotFoundException extends SteamServiceException {
  final String workshopId;

  const WorkshopModNotFoundException(
    super.message, {
    required this.workshopId,
  }) : super(code: 'WORKSHOP_MOD_NOT_FOUND');

  @override
  String toString() => 'WorkshopModNotFoundException(ID: $workshopId): $message';
}

/// Invalid Workshop ID
class InvalidWorkshopIdException extends SteamServiceException {
  final String invalidId;

  const InvalidWorkshopIdException(
    super.message, {
    required this.invalidId,
  }) : super(code: 'INVALID_WORKSHOP_ID');

  @override
  String toString() => 'InvalidWorkshopIdException($invalidId): $message';
}

/// SteamCMD timeout
class SteamCmdTimeoutException extends SteamServiceException {
  final int timeoutSeconds;

  const SteamCmdTimeoutException(
    super.message, {
    required this.timeoutSeconds,
  }) : super(code: 'STEAMCMD_TIMEOUT');

  @override
  String toString() =>
      'SteamCmdTimeoutException(${timeoutSeconds}s): $message';
}

/// Steam authentication failed
class SteamAuthenticationException extends SteamServiceException {
  const SteamAuthenticationException(
    super.message, {
    super.stackTrace,
  }) : super(code: 'STEAM_AUTH_FAILED');
}

/// Workshop publish/update failed
class WorkshopPublishException extends SteamServiceException {
  final String? workshopId;

  const WorkshopPublishException(
    super.message, {
    this.workshopId,
    super.stackTrace,
  }) : super(code: 'WORKSHOP_PUBLISH_FAILED');

  @override
  String toString() {
    if (workshopId != null) {
      return 'WorkshopPublishException(ID: $workshopId): $message';
    }
    return 'WorkshopPublishException: $message';
  }
}

/// Steam Guard code required for authentication
class SteamGuardRequiredException extends SteamServiceException {
  const SteamGuardRequiredException(
    super.message,
  ) : super(code: 'STEAM_GUARD_REQUIRED');
}

/// Workshop item no longer exists on Steam (was deleted)
class WorkshopItemNotFoundException extends SteamServiceException {
  final String workshopId;

  const WorkshopItemNotFoundException(
    super.message, {
    required this.workshopId,
  }) : super(code: 'WORKSHOP_ITEM_NOT_FOUND');

  @override
  String toString() =>
      'WorkshopItemNotFoundException(ID: $workshopId): $message';
}

/// VDF file generation failed
class VdfGenerationException extends SteamServiceException {
  const VdfGenerationException(
    super.message, {
    super.stackTrace,
  }) : super(code: 'VDF_GENERATION_FAILED');
}
