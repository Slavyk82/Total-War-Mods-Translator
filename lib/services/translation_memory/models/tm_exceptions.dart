import 'package:twmt/models/common/service_exception.dart';

/// Base exception for Translation Memory services
class TmServiceException extends ServiceException {
  const TmServiceException(
    super.message, {
    super.error,
    super.stackTrace,
  });
}

/// Exception thrown when TM entry is not found
class TmEntryNotFoundException extends TmServiceException {
  final String? entryId;
  final String? sourceHash;

  const TmEntryNotFoundException(
    super.message, {
    this.entryId,
    this.sourceHash,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final idInfo = entryId != null ? ' (ID: $entryId)' : '';
    final hashInfo = sourceHash != null ? ' (Hash: $sourceHash)' : '';
    return 'TmEntryNotFoundException: $message$idInfo$hashInfo';
  }
}

/// Exception thrown when TM lookup fails
class TmLookupException extends TmServiceException {
  final String sourceText;
  final String targetLanguageCode;

  const TmLookupException(
    super.message,
    this.sourceText,
    this.targetLanguageCode, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'TmLookupException: $message '
        '(target: $targetLanguageCode, '
        'text: "${sourceText.length > 50 ? "${sourceText.substring(0, 50)}..." : sourceText}")';
  }
}

/// Exception thrown when adding to TM fails
class TmAddException extends TmServiceException {
  final String? sourceText;
  final String? targetText;

  const TmAddException(
    super.message, {
    this.sourceText,
    this.targetText,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'TmAddException: $message';
  }
}

/// Exception thrown when TM import fails
class TmImportException extends TmServiceException {
  final String? filePath;
  final int? processedEntries;
  final int? failedEntries;

  const TmImportException(
    super.message, {
    this.filePath,
    this.processedEntries,
    this.failedEntries,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final fileInfo = filePath != null ? ' (File: $filePath)' : '';
    final stats = processedEntries != null && failedEntries != null
        ? ' - Processed: $processedEntries, Failed: $failedEntries'
        : '';
    return 'TmImportException: $message$fileInfo$stats';
  }
}

/// Exception thrown when TM export fails
class TmExportException extends TmServiceException {
  final String? outputPath;
  final int? entriesCount;

  const TmExportException(
    super.message, {
    this.outputPath,
    this.entriesCount,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final pathInfo = outputPath != null ? ' (Path: $outputPath)' : '';
    final countInfo = entriesCount != null ? ', Entries: $entriesCount' : '';
    return 'TmExportException: $message$pathInfo$countInfo';
  }
}

/// Exception thrown when similarity calculation fails
class SimilarityCalculationException extends TmServiceException {
  final String? sourceText1;
  final String? sourceText2;
  final String? algorithm;

  const SimilarityCalculationException(
    super.message, {
    this.sourceText1,
    this.sourceText2,
    this.algorithm,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final algoInfo = algorithm != null ? ' (Algorithm: $algorithm)' : '';
    return 'SimilarityCalculationException: $message$algoInfo';
  }
}

/// Exception thrown when text normalization fails
class NormalizationException extends TmServiceException {
  final String? originalText;

  const NormalizationException(
    super.message, {
    this.originalText,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final textPreview = originalText != null && originalText!.length > 50
        ? '${originalText!.substring(0, 50)}...'
        : originalText;
    final textInfo = textPreview != null ? ' (Text: "$textPreview")' : '';
    return 'NormalizationException: $message$textInfo';
  }
}

/// Exception thrown when TM cache operations fail
class TmCacheException extends TmServiceException {
  final String? cacheKey;
  final String? operation;

  const TmCacheException(
    super.message, {
    this.cacheKey,
    this.operation,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final keyInfo = cacheKey != null ? ' (Key: $cacheKey)' : '';
    final opInfo = operation != null ? ', Operation: $operation' : '';
    return 'TmCacheException: $message$keyInfo$opInfo';
  }
}
