import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

/// Interface for glossary management service
///
/// Provides operations for managing glossaries and glossary entries,
/// including creation, editing, deletion, import/export, and term matching.
abstract class IGlossaryService {
  // ============================================================================
  // Glossary CRUD Operations
  // ============================================================================

  /// Create a new glossary
  ///
  /// [name] - Unique glossary name
  /// [description] - Optional description
  /// [isGlobal] - If true, glossary is universal (all games, all projects)
  ///              If false, glossary is game-specific (all projects of one game)
  /// [gameInstallationId] - Required when isGlobal is false (game-specific)
  /// [targetLanguageId] - Target language ID for glossary terms
  ///
  /// Returns the created glossary or error
  Future<Result<Glossary, GlossaryException>> createGlossary({
    required String name,
    String? description,
    required bool isGlobal,
    String? gameInstallationId,
    required String targetLanguageId,
  });

  /// Get glossary by ID
  Future<Result<Glossary, GlossaryException>> getGlossaryById(String id);

  /// Get all glossaries (universal and game-specific)
  ///
  /// [gameInstallationId] - If specified, returns universal + game-specific glossaries
  /// [includeUniversal] - Include universal glossaries in result
  Future<Result<List<Glossary>, GlossaryException>> getAllGlossaries({
    String? gameInstallationId,
    bool includeUniversal = true,
  });

  /// Update glossary metadata (name, description)
  Future<Result<Glossary, GlossaryException>> updateGlossary(Glossary glossary);

  /// Delete glossary by ID
  ///
  /// Cascades to delete all entries in the glossary
  Future<Result<void, GlossaryException>> deleteGlossary(String id);

  // ============================================================================
  // Glossary Entry CRUD Operations
  // ============================================================================

  /// Add entry to glossary
  ///
  /// [glossaryId] - Target glossary ID
  /// [targetLanguageCode] - Target language (e.g., 'fr')
  /// [sourceTerm] - Source term/phrase
  /// [targetTerm] - Target translation
  /// [caseSensitive] - If true, matching is case-sensitive
  /// [notes] - Optional notes providing context for the LLM (e.g., gender hints)
  Future<Result<GlossaryEntry, GlossaryException>> addEntry({
    required String glossaryId,
    required String targetLanguageCode,
    required String sourceTerm,
    required String targetTerm,
    bool caseSensitive = false,
    String? notes,
  });

  /// Get entry by ID
  Future<Result<GlossaryEntry, GlossaryException>> getEntryById(String id);

  /// Get all entries in a glossary
  ///
  /// [glossaryId] - Glossary ID
  /// [sourceLanguageCode] - Filter by source language
  /// [targetLanguageCode] - Filter by target language
  Future<Result<List<GlossaryEntry>, GlossaryException>> getEntriesByGlossary({
    required String glossaryId,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  });

  /// Update glossary entry
  Future<Result<GlossaryEntry, GlossaryException>> updateEntry(
    GlossaryEntry entry,
  );

  /// Delete glossary entry by ID
  Future<Result<void, GlossaryException>> deleteEntry(String id);

  /// Delete multiple entries by IDs
  Future<Result<void, GlossaryException>> deleteEntries(List<String> ids);

  // ============================================================================
  // Term Matching & Detection
  // ============================================================================

  /// Find matching glossary terms in source text
  ///
  /// Detects all glossary terms present in the source text.
  ///
  /// [sourceText] - Text to search for terms
  /// [sourceLanguageCode] - Source language
  /// [targetLanguageCode] - Target language
  /// [glossaryIds] - List of glossary IDs to search (empty = all applicable)
  /// [gameInstallationId] - If specified, includes game-specific glossaries
  ///
  /// Returns list of matching entries
  Future<Result<List<GlossaryEntry>, GlossaryException>> findMatchingTerms({
    required String sourceText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  });

  /// Apply glossary substitutions to target text
  ///
  /// Automatically replaces source terms with target terms in the translation.
  ///
  /// [sourceText] - Original source text
  /// [targetText] - Translated text to apply substitutions to
  /// [sourceLanguageCode] - Source language
  /// [targetLanguageCode] - Target language
  /// [glossaryIds] - List of glossary IDs to use
  /// [gameInstallationId] - If specified, includes game-specific glossaries
  ///
  /// Returns modified target text with substitutions
  Future<Result<String, GlossaryException>> applySubstitutions({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  });

  // ============================================================================
  // Validation
  // ============================================================================

  /// Validate glossary consistency
  ///
  /// Checks for:
  /// - Duplicate terms
  /// - Conflicting translations for same term
  /// - Empty terms
  /// - Invalid characters
  ///
  /// [glossaryId] - Glossary to validate
  ///
  /// Returns list of validation errors/warnings
  Future<Result<List<String>, GlossaryException>> validateGlossary(
    String glossaryId,
  );

  /// Check if target text is consistent with glossary
  ///
  /// Verifies that glossary terms in source are correctly translated in target.
  ///
  /// [sourceText] - Source text
  /// [targetText] - Target text
  /// [sourceLanguageCode] - Source language
  /// [targetLanguageCode] - Target language
  /// [glossaryIds] - Glossaries to check against
  /// [gameInstallationId] - Game context
  ///
  /// Returns list of inconsistencies found
  Future<Result<List<String>, GlossaryException>> checkConsistency({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  });

  // ============================================================================
  // Import/Export
  // ============================================================================

  /// Import glossary from CSV file
  ///
  /// CSV format: source_term, target_term
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to CSV file
  /// [targetLanguageCode] - Target language
  /// [skipDuplicates] - If true, skip existing terms
  ///
  /// Returns number of entries imported
  Future<Result<int, GlossaryException>> importFromCsv({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    bool skipDuplicates = true,
  });

  /// Export glossary to CSV file
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  /// [sourceLanguageCode] - Filter by source language
  /// [targetLanguageCode] - Filter by target language
  ///
  /// Returns number of entries exported
  Future<Result<int, GlossaryException>> exportToCsv({
    required String glossaryId,
    required String filePath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  });

  /// Import glossary from TBX (TermBase eXchange) file
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to TBX file
  ///
  /// Returns number of entries imported
  Future<Result<int, GlossaryException>> importFromTbx({
    required String glossaryId,
    required String filePath,
  });

  /// Export glossary to TBX format
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  ///
  /// Returns number of entries exported
  Future<Result<int, GlossaryException>> exportToTbx({
    required String glossaryId,
    required String filePath,
  });

  /// Import glossary from Excel file
  ///
  /// Excel columns: source_term, target_term
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to Excel file
  /// [targetLanguageCode] - Target language
  /// [sheetName] - Excel sheet name (default: first sheet)
  /// [skipDuplicates] - If true, skip existing terms
  ///
  /// Returns number of entries imported
  Future<Result<int, GlossaryException>> importFromExcel({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    String? sheetName,
    bool skipDuplicates = true,
  });

  /// Export glossary to Excel file
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  /// [sourceLanguageCode] - Filter by source language
  /// [targetLanguageCode] - Filter by target language
  ///
  /// Returns number of entries exported
  Future<Result<int, GlossaryException>> exportToExcel({
    required String glossaryId,
    required String filePath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  });

  // ============================================================================
  // DeepL Integration
  // ============================================================================

  /// Create DeepL glossary from TWMT glossary
  ///
  /// Uploads glossary to DeepL API for use in translations.
  ///
  /// [glossaryId] - TWMT glossary ID
  /// [sourceLanguageCode] - Source language
  /// [targetLanguageCode] - Target language
  ///
  /// Returns DeepL glossary ID
  Future<Result<String, GlossaryException>> createDeepLGlossary({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  });

  /// Delete DeepL glossary
  ///
  /// [deeplGlossaryId] - DeepL glossary ID to delete
  Future<Result<void, GlossaryException>> deleteDeepLGlossary(
    String deeplGlossaryId,
  );

  /// List all DeepL glossaries for the account
  Future<Result<List<Map<String, dynamic>>, GlossaryException>>
      listDeepLGlossaries();

  // ============================================================================
  // Search & Statistics
  // ============================================================================

  /// Search glossary entries by term
  ///
  /// [query] - Search query
  /// [glossaryIds] - Filter by glossary IDs
  /// [sourceLanguageCode] - Filter by source language
  /// [targetLanguageCode] - Filter by target language
  ///
  /// Returns matching entries
  Future<Result<List<GlossaryEntry>, GlossaryException>> searchEntries({
    required String query,
    List<String>? glossaryIds,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  });

  /// Get glossary statistics
  ///
  /// Returns:
  /// - Total entries
  /// - Entries by language pair
  /// - Most used terms
  ///
  /// [glossaryId] - Glossary ID
  Future<Result<Map<String, dynamic>, GlossaryException>> getGlossaryStats(
    String glossaryId,
  );
}
