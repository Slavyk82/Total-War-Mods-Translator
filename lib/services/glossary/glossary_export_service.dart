import 'dart:convert';
import 'dart:io';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:xml/xml.dart';

/// Service responsible for glossary export operations
///
/// Handles CSV, TBX, and Excel export for glossaries.
/// Separated from import operations following Single Responsibility Principle.
class GlossaryExportService {
  final GlossaryRepository _repository;
  final LoggingService _logger = LoggingService.instance;

  GlossaryExportService(this._repository);

  // ============================================================================
  // CSV Export
  // ============================================================================

  /// Export glossary to CSV file
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  /// [sourceLanguageCode] - Filter by source language (unused, kept for API compatibility)
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
      sink.writeln('source_term,target_term,notes');

      // Write entries
      for (final entry in entries) {
        // Escape commas in notes by wrapping in quotes
        final notes = entry.notes ?? '';
        final escapedNotes = notes.contains(',') ? '"$notes"' : notes;
        sink.writeln('${entry.sourceTerm},${entry.targetTerm},$escapedNotes');
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
  // TBX Export
  // ============================================================================

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
  void _buildTbxTermEntry(
    XmlBuilder builder,
    GlossaryEntry entry,
    String sourceLanguageCode,
  ) {
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

      // Notes for LLM context
      if (entry.hasNotes) {
        builder.element('descripGrp', nest: () {
          builder.element('descrip', attributes: {
            'type': 'context',
          }, nest: () {
            builder.text(entry.notes!);
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
  // Excel Export
  // ============================================================================

  /// Export glossary to Excel file
  ///
  /// [glossaryId] - Glossary to export
  /// [filePath] - Output file path
  /// [sourceLanguageCode] - Filter by source language (unused, kept for API compatibility)
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
          'notes': entry.notes ?? '',
        };
      }).toList();

      // Use FileImportExportService to export Excel data
      final fileService = FileImportExportService();
      final exportResult = await fileService.exportToExcel(
        data: data,
        filePath: filePath,
        sheetName: glossary.name,
        headers: ['source_term', 'target_term', 'notes'],
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
