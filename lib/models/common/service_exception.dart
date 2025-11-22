/// Base exception for all service-level errors in TWMT.
///
/// All custom exceptions should extend this class to maintain
/// a consistent error hierarchy throughout the application.
class ServiceException implements Exception {
  final String message;
  final String? code;
  final Object? details;
  final Object? error;
  final StackTrace? stackTrace;

  const ServiceException(
    this.message, {
    this.code,
    this.details,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (code != null) {
      buffer.write(' (code: $code)');
    }
    if (details != null) {
      buffer.write('\nDetails: $details');
    }
    if (error != null) {
      buffer.write('\nCaused by: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Exception for database-related errors
class TWMTDatabaseException extends ServiceException {
  const TWMTDatabaseException(
    super.message, {
    super.error,
    super.stackTrace,
  });
}

/// Exception for validation errors
class ValidationException extends ServiceException {
  final Map<String, List<String>> fieldErrors;

  const ValidationException(
    super.message, {
    this.fieldErrors = const {},
    super.error,
    super.stackTrace,
  });

  /// Check if a specific field has errors
  bool hasFieldError(String field) => fieldErrors.containsKey(field);

  /// Get errors for a specific field
  List<String> getFieldErrors(String field) => fieldErrors[field] ?? [];

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (fieldErrors.isNotEmpty) {
      buffer.write('\nField errors:');
      fieldErrors.forEach((field, errors) {
        buffer.write('\n  $field: ${errors.join(", ")}');
      });
    }
    return buffer.toString();
  }
}

/// Exception for network-related errors
class NetworkException extends ServiceException {
  final int? statusCode;
  final String? url;

  const NetworkException(
    super.message, {
    this.statusCode,
    this.url,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (statusCode != null) {
      buffer.write('\nStatus code: $statusCode');
    }
    if (url != null) {
      buffer.write('\nURL: $url');
    }
    return buffer.toString();
  }
}

/// Exception for LLM service errors (Anthropic, OpenAI, DeepL)
class LlmServiceException extends ServiceException {
  final String? provider;
  final String? model;
  final int? tokensUsed;

  const LlmServiceException(
    super.message, {
    this.provider,
    this.model,
    this.tokensUsed,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (provider != null) {
      buffer.write('\nProvider: $provider');
    }
    if (model != null) {
      buffer.write('\nModel: $model');
    }
    if (tokensUsed != null) {
      buffer.write('\nTokens used: $tokensUsed');
    }
    return buffer.toString();
  }
}

/// Exception for RPFM-related errors
class RpfmException extends ServiceException {
  final String? command;
  final int? exitCode;

  const RpfmException(
    super.message, {
    this.command,
    this.exitCode,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (command != null) {
      buffer.write('\nCommand: $command');
    }
    if (exitCode != null) {
      buffer.write('\nExit code: $exitCode');
    }
    return buffer.toString();
  }
}

/// Exception for Steam-related errors (SteamCMD, Workshop API)
class SteamException extends ServiceException {
  final String? workshopId;
  final String? gameCode;

  const SteamException(
    super.message, {
    this.workshopId,
    this.gameCode,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (workshopId != null) {
      buffer.write('\nWorkshop ID: $workshopId');
    }
    if (gameCode != null) {
      buffer.write('\nGame: $gameCode');
    }
    return buffer.toString();
  }
}

/// Exception for translation-related errors
class TranslationException extends ServiceException {
  final String? unitId;
  final String? languageCode;
  final String? batchId;

  const TranslationException(
    super.message, {
    this.unitId,
    this.languageCode,
    this.batchId,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (unitId != null) {
      buffer.write('\nUnit ID: $unitId');
    }
    if (languageCode != null) {
      buffer.write('\nLanguage: $languageCode');
    }
    if (batchId != null) {
      buffer.write('\nBatch ID: $batchId');
    }
    return buffer.toString();
  }
}

/// Exception for file system errors
class FileSystemException extends ServiceException {
  final String? filePath;

  const FileSystemException(
    super.message, {
    this.filePath,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (filePath != null) {
      buffer.write('\nFile path: $filePath');
    }
    return buffer.toString();
  }
}

/// Exception for concurrency/locking errors
class ConcurrencyException extends ServiceException {
  final String? resourceId;
  final String? lockHolderContext;

  const ConcurrencyException(
    super.message, {
    this.resourceId,
    this.lockHolderContext,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (resourceId != null) {
      buffer.write('\nResource ID: $resourceId');
    }
    if (lockHolderContext != null) {
      buffer.write('\nLocked by: $lockHolderContext');
    }
    return buffer.toString();
  }
}

/// Exception for translation memory errors
class TranslationMemoryException extends ServiceException {
  final String? sourceHash;
  final String? targetLanguageCode;

  const TranslationMemoryException(
    super.message, {
    this.sourceHash,
    this.targetLanguageCode,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (sourceHash != null) {
      buffer.write('\nSource hash: $sourceHash');
    }
    if (targetLanguageCode != null) {
      buffer.write('\nTarget language: $targetLanguageCode');
    }
    return buffer.toString();
  }
}

/// Exception for configuration errors
class ConfigurationException extends ServiceException {
  final String? configKey;

  const ConfigurationException(
    super.message, {
    this.configKey,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (configKey != null) {
      buffer.write('\nConfig key: $configKey');
    }
    return buffer.toString();
  }
}
