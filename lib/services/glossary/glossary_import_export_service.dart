import 'dart:convert';
import 'dart:io';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/models/tbx_entry.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:xml/xml.dart';

/// Service responsible for import/export operations
///
/// Handles CSV, TBX, and Excel import/export for glossaries.
class GlossaryImportExportService {
  final GlossaryRepository _repository;
  final IGlossaryService _glossaryService;
  final LoggingService _logger = LoggingService.instance;

  GlossaryImportExportService(this._repository, this._glossaryService);

  // ============================================================================
  // CSV Import/Export
  // ============================================================================

  /// Import glossary from CSV file
  ///
  /// CSV format: source_term, target_term, category, notes
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to CSV file
  /// [sourceLanguageCode] - Source language
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
        final category = parts.length > 2 ? parts[2].trim() : null;
        final notes = parts.length > 3 ? parts[3].trim() : null;

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
          category: category,
          notes: notes,
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
  }) async {
    try {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );

      final file = File(filePath);
      final sink = file.openWrite();

      // Write header
      sink.writeln('source_term,target_term,category,notes');

      // Write entries
      for (final entry in entries) {
        final category = entry.category ?? '';
        final notes = entry.notes ?? '';
        sink.writeln('${entry.sourceTerm},${entry.targetTerm},$category,$notes');
      }

      await sink.close();

      return Ok(entries.length);
    } catch (e) {
      return Err(
        GlossaryFileException(filePath, 'Failed to export CSV', e),
      );
    }
  }

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
          category: tbxEntry.category,
          notes: tbxEntry.description,
          caseSensitive: tbxEntry.caseSensitive,
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
      String? description;
      String? category;
      String? partOfSpeech;
      bool caseSensitive = false;

      // Extract descriptions from descripGrp elements
      for (final descripGrp in termEntry.findElements('descripGrp')) {
        final descrip = descripGrp.findElements('descrip').firstOrNull;
        if (descrip != null) {
          final type = descrip.getAttribute('type') ?? '';
          final text = descrip.innerText.trim();

          switch (type) {
            case 'definition':
              description = text;
              break;
            case 'subjectField':
              category = text;
              break;
            case 'note':
              // Check for case-sensitive indicator
              if (text.toLowerCase().contains('case-sensitive')) {
                caseSensitive = true;
              }
              // If we don't have a description yet, use the note
              if (description == null && text.isNotEmpty) {
                description = text;
              }
              break;
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

          // Extract part of speech if available
          for (final termNote in tig.findElements('termNote')) {
            final type = termNote.getAttribute('type') ?? '';
            if (type == 'partOfSpeech') {
              partOfSpeech = termNote.innerText.trim();
            }
          }

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
          description: description,
          category: category,
          partOfSpeech: partOfSpeech,
          caseSensitive: caseSensitive,
        ));
      }
    }

    return entries;
  }

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
  }) async {
    try {
      // Get glossary metadata
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // Get entries to export
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );

      if (entries.isEmpty) {
        _logger.warning('No entries to export', {'glossaryId': glossaryId});
        return Ok(0);
      }

      // Build TBX XML structure
      final builder = XmlBuilder();

      // XML declaration
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');

      // Root martif element
      builder.element('martif', attributes: {
        'type': 'TBX',
        'xml:lang': sourceLanguageCode ?? 'en',
      }, nest: () {
        // Header
        builder.element('martifHeader', nest: () {
          builder.element('fileDesc', nest: () {
            builder.element('sourceDesc', nest: () {
              builder.element('p', nest: () {
                builder.text(glossaryName ?? glossary.name);
              });
            });
          });

          // Add encoding description
          builder.element('encodingDesc', nest: () {
            builder.element('p', attributes: {
              'type': 'DCSName',
            }, nest: () {
              builder.text('TBX-Basic');
            });
          });
        });

        // Body with term entries
        builder.element('text', nest: () {
          builder.element('body', nest: () {
            for (final entry in entries) {
              _buildTbxTermEntry(builder, entry, sourceLanguageCode ?? 'en');
            }
          });
        });
      });

      // Write to file
      final document = builder.buildDocument();
      final xmlString = document.toXmlString(
        pretty: true,
        indent: '  ',
      );

      final file = File(filePath);
      await file.writeAsString(
        xmlString,
        encoding: utf8,
      );

      _logger.info('Exported ${entries.length} glossary entries to TBX', {
        'filePath': filePath,
        'glossaryId': glossaryId,
      });

      return Ok(entries.length);
    } catch (e, stackTrace) {
      _logger.error('Failed to export TBX', e, stackTrace);
      return Err(
        GlossaryFileException(
          filePath,
          'Failed to export TBX: ${e.toString()}',
          e,
        ),
      );
    }
  }

  /// Build a single term entry in TBX format
  void _buildTbxTermEntry(XmlBuilder builder, GlossaryEntry entry, String sourceLanguageCode) {
    builder.element('termEntry', attributes: {
      'id': entry.id,
    }, nest: () {
      // Source language term
      builder.element('langSet', attributes: {
        'xml:lang': sourceLanguageCode,
      }, nest: () {
        builder.element('tig', nest: () {
          builder.element('term', nest: () {
            builder.text(entry.sourceTerm);
          });
        });
      });

      // Target language term
      builder.element('langSet', attributes: {
        'xml:lang': entry.targetLanguageCode,
      }, nest: () {
        builder.element('tig', nest: () {
          builder.element('term', nest: () {
            builder.text(entry.targetTerm);
          });
        });
      });

      // Description/Note
      if (entry.notes != null && entry.notes!.isNotEmpty) {
        builder.element('descripGrp', nest: () {
          builder.element('descrip', attributes: {
            'type': 'definition',
          }, nest: () {
            builder.text(entry.notes!);
          });
        });
      }

      // Category (subject field)
      if (entry.category != null && entry.category!.isNotEmpty) {
        builder.element('descripGrp', nest: () {
          builder.element('descrip', attributes: {
            'type': 'subjectField',
          }, nest: () {
            builder.text(entry.category!);
          });
        });
      }

      // Case sensitivity note
      if (entry.caseSensitive) {
        builder.element('descripGrp', nest: () {
          builder.element('descrip', attributes: {
            'type': 'note',
          }, nest: () {
            builder.text('Case-sensitive matching');
          });
        });
      }
    });
  }

  // ============================================================================
  // Excel Import/Export
  // ============================================================================

  /// Import glossary from Excel file
  ///
  /// Excel columns: source_term, target_term, category, notes
  ///
  /// [glossaryId] - Target glossary ID
  /// [filePath] - Path to Excel file
  /// [sourceLanguageCode] - Source language
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
        final category = row['category']?.trim();
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
          category: category,
          notes: notes,
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
  }) async {
    try {
      // Check glossary exists
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // Get entries to export
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );

      if (entries.isEmpty) {
        _logger.warning('No entries to export', {'glossaryId': glossaryId});
        return Ok(0);
      }

      // Convert entries to map format for FileImportExportService
      final data = entries.map((entry) {
        return {
          'source_term': entry.sourceTerm,
          'target_term': entry.targetTerm,
          'category': entry.category ?? '',
          'notes': entry.notes ?? '',
        };
      }).toList();

      // Use FileImportExportService to export Excel data
      final fileService = FileImportExportService();
      final exportResult = await fileService.exportToExcel(
        data: data,
        filePath: filePath,
        sheetName: glossary.name,
        headers: ['source_term', 'target_term', 'category', 'notes'],
      );

      if (exportResult.isErr) {
        return Err(
          GlossaryFileException(
            filePath,
            'Failed to export Excel: ${exportResult.unwrapErr()}',
          ),
        );
      }

      _logger.info('Exported ${entries.length} glossary entries to Excel', {
        'filePath': filePath,
        'glossaryId': glossaryId,
      });

      return Ok(entries.length);
    } catch (e, stackTrace) {
      _logger.error('Failed to export Excel', e, stackTrace);
      return Err(
        GlossaryFileException(
          filePath,
          'Failed to export Excel: ${e.toString()}',
          e,
        ),
      );
    }
  }
}
