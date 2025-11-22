import 'package:twmt/models/common/service_exception.dart';

/// Base exception for file service operations
class FileServiceException extends ServiceException {
  const FileServiceException(
    super.message, {
    super.error,
    super.stackTrace,
  });
}

/// Exception thrown when a file is not found
class FileNotFoundException extends FileServiceException {
  /// Path to the file that was not found
  final String filePath;

  const FileNotFoundException(
    super.message,
    this.filePath, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileNotFoundException: $message (path: $filePath)';
}

/// Exception thrown when file access is denied
class FileAccessDeniedException extends FileServiceException {
  /// Path to the file with access issues
  final String filePath;

  /// Type of access denied (read, write, delete, etc.)
  final String accessType;

  const FileAccessDeniedException(
    super.message,
    this.filePath,
    this.accessType, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileAccessDeniedException: $message (path: $filePath, access: $accessType)';
}

/// Exception thrown when file encoding is invalid or unsupported
class FileEncodingException extends FileServiceException {
  /// Path to the file with encoding issues
  final String filePath;

  /// Expected encoding
  final String? expectedEncoding;

  /// Detected encoding
  final String? detectedEncoding;

  const FileEncodingException(
    super.message,
    this.filePath, {
    this.expectedEncoding,
    this.detectedEncoding,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileEncodingException: $message (path: $filePath, '
      'expected: $expectedEncoding, detected: $detectedEncoding)';
}

/// Exception thrown when file format is invalid
class FileFormatException extends FileServiceException {
  /// Path to the file with format issues
  final String filePath;

  /// Expected format
  final String? expectedFormat;

  /// Line number where error occurred
  final int? lineNumber;

  const FileFormatException(
    super.message,
    this.filePath, {
    this.expectedFormat,
    this.lineNumber,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileFormatException: $message (path: $filePath, '
      'format: $expectedFormat, line: $lineNumber)';
}

/// Exception thrown when file parsing fails
class FileParsingException extends FileServiceException {
  /// Path to the file being parsed
  final String filePath;

  /// Line number where parsing failed
  final int? lineNumber;

  /// Raw line content that failed to parse
  final String? rawLine;

  const FileParsingException(
    super.message,
    this.filePath, {
    this.lineNumber,
    this.rawLine,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileParsingException: $message (path: $filePath, '
      'line: $lineNumber, content: $rawLine)';
}

/// Exception thrown when file writing fails
class FileWriteException extends FileServiceException {
  /// Path to the file being written
  final String filePath;

  /// Bytes written before failure (if applicable)
  final int? bytesWritten;

  const FileWriteException(
    super.message,
    this.filePath, {
    this.bytesWritten,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileWriteException: $message (path: $filePath, '
      'bytesWritten: $bytesWritten)';
}

/// Exception thrown when file validation fails
class FileValidationException extends FileServiceException {
  /// Path to the invalid file
  final String filePath;

  /// List of validation errors
  final List<String> validationErrors;

  const FileValidationException(
    super.message,
    this.filePath,
    this.validationErrors, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileValidationException: $message (path: $filePath, '
      'errors: ${validationErrors.length})';
}

/// Exception thrown when import operation fails
class ImportException extends FileServiceException {
  /// Source file path
  final String sourcePath;

  /// Format being imported (CSV, JSON, Excel, etc.)
  final String format;

  /// Number of entries successfully imported before failure
  final int? entriesImported;

  const ImportException(
    super.message,
    this.sourcePath,
    this.format, {
    this.entriesImported,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'ImportException: $message (source: $sourcePath, '
      'format: $format, imported: $entriesImported)';
}

/// Exception thrown when export operation fails
class ExportException extends FileServiceException {
  /// Destination file path
  final String destinationPath;

  /// Format being exported (CSV, JSON, Excel, .loc, etc.)
  final String format;

  /// Number of entries successfully exported before failure
  final int? entriesExported;

  const ExportException(
    super.message,
    this.destinationPath,
    this.format, {
    this.entriesExported,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'ExportException: $message (destination: $destinationPath, '
      'format: $format, exported: $entriesExported)';
}

/// Exception thrown when file watching fails
class FileWatchException extends FileServiceException {
  /// Path to the directory or file being watched
  final String watchPath;

  const FileWatchException(
    super.message,
    this.watchPath, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() =>
      'FileWatchException: $message (watchPath: $watchPath)';
}
