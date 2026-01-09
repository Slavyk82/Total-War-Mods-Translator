import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_export_service.dart';
import 'package:twmt/services/glossary/glossary_import_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

/// Facade service for import/export operations
///
/// Provides a unified API for glossary import/export operations by delegating
/// to specialized services:
/// - [GlossaryImportService] for CSV, TBX, and Excel imports
/// - [GlossaryExportService] for CSV, TBX, and Excel exports
///
/// This class maintains backward compatibility while adhering to
/// Single Responsibility Principle through delegation.
class GlossaryImportExportService {
  final GlossaryImportService _importService;
  final GlossaryExportService _exportService;

  GlossaryImportExportService(
    GlossaryRepository repository,
    IGlossaryService glossaryService,
  )   : _importService = GlossaryImportService(repository, glossaryService),
        _exportService = GlossaryExportService(repository);

  // ============================================================================
  // CSV Import/Export
  // ============================================================================

  /// Import glossary from CSV file
  ///
  /// CSV format: source_term, target_term, notes (optional)
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
  }) =>
      _importService.importFromCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        skipDuplicates: skipDuplicates,
      );

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
  }) =>
      _exportService.exportToCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

  // ============================================================================
  // TBX Import/Export
  // ============================================================================

  /// Import glossary from TBX (TermBase eXchange) file
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to TBX file
  /// [skipDuplicates] - If true, skip existing terms
  ///
  /// Returns number of entries imported
  Future<Result<int, GlossaryException>> importFromTbx({
    required String glossaryId,
    required String filePath,
    bool skipDuplicates = true,
  }) =>
      _importService.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
        skipDuplicates: skipDuplicates,
      );

  /// Export glossary to TBX format
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  /// [sourceLanguageCode] - Filter by source language
  /// [targetLanguageCode] - Filter by target language
  /// [glossaryName] - Optional name for the glossary in TBX header
  ///
  /// Returns number of entries exported
  Future<Result<int, GlossaryException>> exportToTbx({
    required String glossaryId,
    required String filePath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
    String? glossaryName,
  }) =>
      _exportService.exportToTbx(
        glossaryId: glossaryId,
        filePath: filePath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        glossaryName: glossaryName,
      );

  // ============================================================================
  // Excel Import/Export
  // ============================================================================

  /// Import glossary from Excel file
  ///
  /// Excel columns: source_term, target_term, notes (optional)
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
  }) =>
      _importService.importFromExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        sheetName: sheetName,
        skipDuplicates: skipDuplicates,
      );

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
  }) =>
      _exportService.exportToExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );
}
