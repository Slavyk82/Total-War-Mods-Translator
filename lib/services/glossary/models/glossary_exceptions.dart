/// Base exception for all glossary-related errors
abstract class GlossaryException implements Exception {
  final String message;
  final dynamic cause;

  const GlossaryException(this.message, [this.cause]);

  @override
  String toString() => 'GlossaryException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Glossary not found by ID
class GlossaryNotFoundException extends GlossaryException {
  final String glossaryId;

  const GlossaryNotFoundException(this.glossaryId)
      : super('Glossary not found: $glossaryId');

  @override
  String toString() => 'GlossaryNotFoundException: Glossary not found: $glossaryId';
}

/// Glossary entry not found by ID
class GlossaryEntryNotFoundException extends GlossaryException {
  final String entryId;

  const GlossaryEntryNotFoundException(this.entryId)
      : super('Glossary entry not found: $entryId');

  @override
  String toString() => 'GlossaryEntryNotFoundException: Entry not found: $entryId';
}

/// Glossary with the same name already exists
class GlossaryAlreadyExistsException extends GlossaryException {
  final String name;

  const GlossaryAlreadyExistsException(this.name)
      : super('Glossary already exists: $name');

  @override
  String toString() => 'GlossaryAlreadyExistsException: Glossary already exists: $name';
}

/// Duplicate glossary entry (same term in same glossary)
class DuplicateGlossaryEntryException extends GlossaryException {
  final String sourceTerm;
  final String glossaryId;

  const DuplicateGlossaryEntryException(this.sourceTerm, this.glossaryId)
      : super('Duplicate entry for term "$sourceTerm" in glossary $glossaryId');

  @override
  String toString() => 'DuplicateGlossaryEntryException: Duplicate entry for term "$sourceTerm"';
}

/// Invalid glossary data (validation failed)
class InvalidGlossaryDataException extends GlossaryException {
  final List<String> validationErrors;

  InvalidGlossaryDataException(this.validationErrors)
      : super('Invalid glossary data: ${validationErrors.join(", ")}');

  @override
  String toString() => 'InvalidGlossaryDataException: ${validationErrors.join(", ")}';
}

/// File import/export error
class GlossaryFileException extends GlossaryException {
  final String filePath;

  const GlossaryFileException(this.filePath, String message, [dynamic cause])
      : super(message, cause);

  @override
  String toString() => 'GlossaryFileException: $message (file: $filePath)';
}

/// DeepL glossary API error
class DeepLGlossaryException extends GlossaryException {
  final int? statusCode;

  const DeepLGlossaryException(super.message, [this.statusCode, super.cause]);

  @override
  String toString() =>
      'DeepLGlossaryException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// Database error during glossary operations
class GlossaryDatabaseException extends GlossaryException {
  const GlossaryDatabaseException(super.message, [super.cause]);

  @override
  String toString() => 'GlossaryDatabaseException: $message';
}

/// Glossary operation is not supported
class GlossaryOperationNotSupportedException extends GlossaryException {
  final String operation;

  const GlossaryOperationNotSupportedException(this.operation)
      : super('Operation not supported: $operation');

  @override
  String toString() => 'GlossaryOperationNotSupportedException: $operation';
}

/// Language pair not supported for glossary
class UnsupportedLanguagePairException extends GlossaryException {
  final String sourceLanguage;
  final String targetLanguage;

  const UnsupportedLanguagePairException(
    this.sourceLanguage,
    this.targetLanguage,
  ) : super('Unsupported language pair: $sourceLanguage -> $targetLanguage');

  @override
  String toString() =>
      'UnsupportedLanguagePairException: $sourceLanguage -> $targetLanguage';
}

/// Glossary sync with DeepL failed
class GlossarySyncException extends GlossaryException {
  const GlossarySyncException(super.message, [super.cause]);

  @override
  String toString() => 'GlossarySyncException: $message';
}
