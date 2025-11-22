import 'package:twmt/models/common/service_exception.dart';

/// Base exception for RPFM service errors
class RpfmServiceException extends ServiceException {
  const RpfmServiceException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}

/// Exception when RPFM-CLI is not found
class RpfmNotFoundException extends RpfmServiceException {
  final String? searchedPaths;

  const RpfmNotFoundException(
    super.message, {
    this.searchedPaths,
    super.code = 'RPFM_NOT_FOUND',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmNotFoundException: $message\n'
        'Searched paths: $searchedPaths';
  }
}

/// Exception when RPFM version is incompatible
class RpfmVersionException extends RpfmServiceException {
  final String? currentVersion;
  final String? requiredVersion;

  const RpfmVersionException(
    super.message, {
    this.currentVersion,
    this.requiredVersion,
    super.code = 'RPFM_VERSION_INCOMPATIBLE',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmVersionException: $message\n'
        'Current: $currentVersion, Required: $requiredVersion';
  }
}

/// Exception when RPFM download fails
class RpfmDownloadException extends RpfmServiceException {
  final String? downloadUrl;

  const RpfmDownloadException(
    super.message, {
    this.downloadUrl,
    super.code = 'RPFM_DOWNLOAD_FAILED',
    super.details,
    super.stackTrace,
  });
}

/// Exception when RPFM extraction fails
class RpfmExtractionException extends RpfmServiceException {
  final String? packFilePath;

  const RpfmExtractionException(
    super.message, {
    this.packFilePath,
    super.code = 'RPFM_EXTRACTION_FAILED',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmExtractionException: $message\n'
        'Pack file: $packFilePath';
  }
}

/// Exception when RPFM packing fails
class RpfmPackingException extends RpfmServiceException {
  final String? outputPath;

  const RpfmPackingException(
    super.message, {
    this.outputPath,
    super.code = 'RPFM_PACKING_FAILED',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmPackingException: $message\n'
        'Output path: $outputPath';
  }
}

/// Exception when pack file is invalid or corrupted
class RpfmInvalidPackException extends RpfmServiceException {
  final String packFilePath;

  const RpfmInvalidPackException(
    super.message, {
    required this.packFilePath,
    super.code = 'RPFM_INVALID_PACK',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmInvalidPackException: $message\n'
        'Pack file: $packFilePath';
  }
}

/// Exception when RPFM process timeout
class RpfmTimeoutException extends RpfmServiceException {
  final int timeoutSeconds;

  const RpfmTimeoutException(
    super.message, {
    required this.timeoutSeconds,
    super.code = 'RPFM_TIMEOUT',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'RpfmTimeoutException: $message\n'
        'Timeout: ${timeoutSeconds}s';
  }
}

/// Exception when RPFM process is cancelled
class RpfmCancelledException extends RpfmServiceException {
  const RpfmCancelledException(
    super.message, {
    super.code = 'RPFM_CANCELLED',
    super.details,
    super.stackTrace,
  });
}
