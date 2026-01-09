import 'dart:convert';
import 'dart:io';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/models/tbx_entry.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:xml/xml.dart';

/// Service responsible for glossary import operations
///
/// Handles CSV, TBX, and Excel import for glossaries.
/// Separated from export operations following Single Responsibility Principle.
class GlossaryImportService {
  final GlossaryRepository _repository;
  final IGlossaryService _glossaryService;
  final LoggingService _logger = LoggingService.instance;

  GlossaryImportService(this._repository, this._glossaryService);

  // ============================================================================
  // CSV Import
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
  }) async {
    try {
      // Check glossary exists
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // Check file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          GlossaryFileException(filePath, 'File not found'),
        );
      }

      // Read CSV file
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        return Ok(0);
      }

      int importedCount = 0;
      final errors = <String>[];

      // Skip header row
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 2) {
          errors.add('Line $i: Invalid format (need at least 2 columns)');
          continue;
        }

        final sourceTerm = parts[0].trim();
        final targetTerm = parts[1].trim();
        // Optional 3rd column for notes (LLM context)
        final notes = parts.length > 2 ? parts[2].trim() : null;

        if (sourceTerm.isEmpty || targetTerm.isEmpty) {
          errors.add('Line $i: Empty term');
          continue;
        }

        // Check for duplicate
        if (skipDuplicates) {
          final duplicate = await _repository.findDuplicateEntry(
            glossaryId: glossaryId,
            targetLanguageCode: targetLanguageCode,
            sourceTerm: sourceTerm,
          );
          if (duplicate != null) {
            continue; // Skip duplicate
          }
        }

        // Add entry using the glossary service
        final result = await _glossaryService.addEntry(
          glossaryId: glossaryId,
          targetLanguageCode: targetLanguageCode,
          sourceTerm: sourceTerm,
          targetTerm: targetTerm,
          notes: notes?.isNotEmpty == true ? notes : null,
        );

        if (result.isOk) {
          importedCount++;
        } else {
          errors.add('Line $i: ${result.error.message}');
        }
      }

      if (errors.isNotEmpty && importedCount == 0) {
        return Err(
          GlossaryFileException(
            filePath,
            'Import failed: ${errors.join("; ")}',
          ),
        );
      }

      return Ok(importedCount);
    } catch (e) {
      return Err(
        GlossaryFileException(filePath, 'Failed to import CSV', e),
      );
    }
  }

  // ============================================================================
  // TBX Import
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
  }) async {
    try {
      // Check glossary exists
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // Check file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          GlossaryFileException(filePath, 'TBX file not found'),
        );
      }

      // Read and parse XML
      final xmlString = await file.readAsString(encoding: utf8);
      XmlDocument document;

      try {
        document = XmlDocument.parse(xmlString);
      } catch (e) {
        return Err(
          GlossaryFileException(
            filePath,
            'Invalid XML format: ${e.toString()}',
            e,
          ),
        );
      }

      // Validate TBX structure
      final martif = document.findElements('martif').firstOrNull;
      if (martif == null) {
        return Err(
          GlossaryFileException(
            filePath,
            'Invalid TBX file: missing martif root element',
          ),
        );
      }

      // Get default language from header
      final defaultLang = martif.getAttribute('xml:lang') ?? 'en';

      // Parse term entries
      final text = martif.findElements('text').firstOrNull;
      final body = text?.findElements('body').firstOrNull;

      if (body == null) {
        return Err(
          GlossaryFileException(
            filePath,
            'Invalid TBX file: missing body element',
          ),
        );
      }

      // Parse entries
      final tbxEntries = _parseTbxEntries(body, defaultLang);

      // Import entries into glossary
      int importedCount = 0;
      final errors = <String>[];

      for (final tbxEntry in tbxEntries) {
        // Check for duplicate
        if (skipDuplicates) {
          final duplicate = await _repository.findDuplicateEntry(
            glossaryId: glossaryId,
            targetLanguageCode: tbxEntry.targetLanguage,
            sourceTerm: tbxEntry.sourceTerm,
          );
          if (duplicate != null) {
            continue; // Skip duplicate
          }
        }

        // Add entry using the glossary service
        final result = await _glossaryService.addEntry(
          glossaryId: glossaryId,
          targetLanguageCode: tbxEntry.targetLanguage,
          sourceTerm: tbxEntry.sourceTerm,
          targetTerm: tbxEntry.targetTerm,
          caseSensitive: tbxEntry.caseSensitive,
          notes: tbxEntry.notes,
        );

        if (result.isOk) {
          importedCount++;
        } else {
          errors.add('Entry ${tbxEntry.id}: ${result.error.message}');
        }
      }

      if (errors.isNotEmpty && importedCount == 0) {
        return Err(
          GlossaryFileException(
            filePath,
            'Import failed: ${errors.join("; ")}',
          ),
        );
      }

      _logger.info('Imported $importedCount glossary entries from TBX', {
        'filePath': filePath,
        'glossaryId': glossaryId,
        'totalEntries': tbxEntries.length,
        'skipped': tbxEntries.length - importedCount,
      });

      return Ok(importedCount);
    } catch (e, stackTrace) {
      _logger.error('Failed to import TBX', e, stackTrace);
      return Err(
        GlossaryFileException(
          filePath,
          'Failed to import TBX: ${e.toString()}',
          e,
        ),
      );
    }
  }

  /// Parse TBX term entries from the body element
  List<TbxEntry> _parseTbxEntries(XmlElement body, String defaultLang) {
    final entries = <TbxEntry>[];

    for (final termEntry in body.findElements('termEntry')) {
      final id = termEntry.getAttribute('id') ?? '';
      String? sourceTerm;
      String? targetTerm;
      String? targetLanguage;
      bool caseSensitive = false;
      String? notes;

      // Extract descriptions from descripGrp elements
      for (final descripGrp in termEntry.findElements('descripGrp')) {
        final descrip = descripGrp.findElements('descrip').firstOrNull;
        if (descrip != null) {
          final type = descrip.getAttribute('type') ?? '';
          final text = descrip.innerText.trim();

          if (type == 'note') {
            // Check for case-sensitive indicator
            if (text.toLowerCase().contains('case-sensitive')) {
              caseSensitive = true;
            } else if (text.isNotEmpty) {
              // Store as notes for LLM context (not case-sensitive indicator)
              notes = text;
            }
          } else if (type == 'context' && text.isNotEmpty) {
            // Also accept 'context' type as notes
            notes = text;
          }
        }
      }

      // Extract terms from langSet elements
      final langSets = termEntry.findElements('langSet').toList();
      for (int i = 0; i < langSets.length; i++) {
        final langSet = langSets[i];
        final lang = langSet.getAttribute('xml:lang') ?? defaultLang;
        final tig = langSet.findElements('tig').firstOrNull;

        if (tig != null) {
          final term = tig.findElements('term').firstOrNull?.innerText.trim();

          // Determine if source or target based on order
          // First langSet is source, second is target
          if (i == 0 && term != null && term.isNotEmpty) {
            sourceTerm = term;
          } else if (i == 1 && term != null && term.isNotEmpty) {
            targetTerm = term;
            targetLanguage = lang;
          }
        }
      }

      // Create entry if we have both source and target
      if (sourceTerm != null &&
          targetTerm != null &&
          targetLanguage != null) {
        entries.add(TbxEntry(
          id: id.isEmpty ? 'tbx_${entries.length + 1}' : id,
          targetLanguage: targetLanguage,
          sourceTerm: sourceTerm,
          targetTerm: targetTerm,
          caseSensitive: caseSensitive,
          notes: notes,
        ));
      }
    }

    return entries;
  }

  // ============================================================================
  // Excel Import
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
  }) async {
    try {
      // Check glossary exists
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // Check file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          GlossaryFileException(filePath, 'Excel file not found'),
        );
      }

      // Use FileImportExportService to import Excel data
      final fileService = FileImportExportService();
      final importResult = await fileService.importFromExcel(
        filePath: filePath,
        sheetName: sheetName,
        hasHeader: true,
      );

      if (importResult.isErr) {
        return Err(
          GlossaryFileException(
            filePath,
            'Failed to import Excel: ${importResult.unwrapErr()}',
          ),
        );
      }

      final rows = importResult.unwrap();
      if (rows.isEmpty) {
        return Ok(0);
      }

      int importedCount = 0;
      final errors = <String>[];

      // Process each row
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final sourceTerm = row['source_term']?.trim() ?? '';
        final targetTerm = row['target_term']?.trim() ?? '';
        final notes = row['notes']?.trim();

        if (sourceTerm.isEmpty || targetTerm.isEmpty) {
          errors.add('Row ${i + 1}: Empty term');
          continue;
        }

        // Check for duplicate
        if (skipDuplicates) {
          final duplicate = await _repository.findDuplicateEntry(
            glossaryId: glossaryId,
            targetLanguageCode: targetLanguageCode,
            sourceTerm: sourceTerm,
          );
          if (duplicate != null) {
            continue; // Skip duplicate
          }
        }

        // Add entry using the glossary service
        final result = await _glossaryService.addEntry(
          glossaryId: glossaryId,
          targetLanguageCode: targetLanguageCode,
          sourceTerm: sourceTerm,
          targetTerm: targetTerm,
          notes: notes?.isNotEmpty == true ? notes : null,
        );

        if (result.isOk) {
          importedCount++;
        } else {
          errors.add('Row ${i + 1}: ${result.error.message}');
        }
      }

      if (errors.isNotEmpty && importedCount == 0) {
        return Err(
          GlossaryFileException(
            filePath,
            'Import failed: ${errors.join("; ")}',
          ),
        );
      }

      _logger.info('Imported $importedCount glossary entries from Excel', {
        'filePath': filePath,
        'glossaryId': glossaryId,
        'totalRows': rows.length,
        'skipped': rows.length - importedCount,
      });

      return Ok(importedCount);
    } catch (e, stackTrace) {
      _logger.error('Failed to import Excel', e, stackTrace);
      return Err(
        GlossaryFileException(
          filePath,
          'Failed to import Excel: ${e.toString()}',
          e,
        ),
      );
    }
  }
}
