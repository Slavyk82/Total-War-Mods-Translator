import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';

/// Service for TMX (Translation Memory eXchange) import and export operations.
///
/// TMX is the industry standard XML-based format for translation memory exchange.
/// This service implements TMX 1.4b standard for compatibility with other CAT tools.
class TmxService {
  final TranslationMemoryRepository _repository;
  final TextNormalizer _normalizer;
  final LoggingService _logger;

  static const String _creationTool = 'TWMT';
  static const String _creationToolVersion = '1.0';
  static const String _tmxVersion = '1.4';
  static const String _datatype = 'plaintext';
  static const String _segtype = 'sentence';
  static const String _adminLang = 'en';

  TmxService({
    required TranslationMemoryRepository repository,
    required TextNormalizer normalizer,
    LoggingService? logger,
  })  : _repository = repository,
        _normalizer = normalizer,
        _logger = logger ?? LoggingService.instance;

  /// Export translation memory entries to TMX format.
  ///
  /// Creates a TMX 1.4b compliant XML file with all specified entries.
  /// Custom properties are used to store TWMT-specific metadata:
  /// - x-usage-count: Number of times the entry was used
  /// - x-game-context: Game/mod context information
  ///
  /// [filePath]: Output path for the TMX file
  /// [entries]: List of translation memory entries to export
  /// [sourceLanguage]: Source language code (ISO 639-1)
  /// [targetLanguage]: Target language code (ISO 639-1)
  ///
  /// Returns Ok(void) on success, Err(TmExportException) on failure
  Future<Result<void, TmExportException>> exportToTmx({
    required String filePath,
    required List<TranslationMemoryEntry> entries,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    try {
      _logger.info('Starting TMX export', {
        'filePath': filePath,
        'entriesCount': entries.length,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
      });

      final builder = XmlBuilder();

      // XML declaration
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');

      // TMX root element
      builder.element('tmx', attributes: {
        'version': _tmxVersion,
      }, nest: () {
        // Header
        builder.element('header', attributes: {
          'creationtool': _creationTool,
          'creationtoolversion': _creationToolVersion,
          'datatype': _datatype,
          'segtype': _segtype,
          'adminlang': _adminLang,
          'srclang': sourceLanguage,
          'o-tmf': _creationTool,
        });

        // Body with translation units
        builder.element('body', nest: () {
          for (final entry in entries) {
            _buildTranslationUnit(builder, entry, sourceLanguage, targetLanguage);
          }
        });
      });

      // Build the XML document
      final document = builder.buildDocument();
      final xmlString = document.toXmlString(
        pretty: true,
        indent: '  ',
      );

      // Write to file
      final file = File(filePath);
      await file.writeAsString(
        xmlString,
        encoding: utf8,
      );

      _logger.info('TMX export completed successfully', {
        'filePath': filePath,
        'entriesExported': entries.length,
      });

      return Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to export TMX', e, stackTrace);
      return Err(TmExportException(
        'Failed to export TMX: ${e.toString()}',
        outputPath: filePath,
        entriesCount: entries.length,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Build a translation unit (TU) element for the TMX document.
  void _buildTranslationUnit(
    XmlBuilder builder,
    TranslationMemoryEntry entry,
    String sourceLanguage,
    String targetLanguage,
  ) {
    builder.element('tu', nest: () {
      // Add custom properties
      builder.element('prop', attributes: {
        'type': 'x-usage-count',
      }, nest: () {
        builder.text(entry.usageCount.toString());
      });

      if (entry.translationProviderId != null &&
          entry.translationProviderId!.isNotEmpty) {
        builder.element('prop', attributes: {
          'type': 'x-provider-id',
        }, nest: () {
          builder.text(entry.translationProviderId!);
        });
      }

      // Source variant
      builder.element('tuv', attributes: {
        'xml:lang': sourceLanguage,
      }, nest: () {
        builder.element('seg', nest: () {
          builder.text(entry.sourceText);
        });
      });

      // Target variant
      builder.element('tuv', attributes: {
        'xml:lang': targetLanguage,
      }, nest: () {
        builder.element('seg', nest: () {
          builder.text(entry.translatedText);
        });
      });
    });
  }

  /// Import translation memory entries from a TMX file.
  ///
  /// Parses a TMX 1.4b compliant XML file and extracts translation units.
  /// Custom TWMT properties are preserved if present.
  ///
  /// [filePath]: Path to the TMX file to import
  ///
  /// Returns `Ok(List<TmxEntry>)` with parsed entries on success,
  /// `Err(TmImportException)` on failure
  Future<Result<List<TmxEntry>, TmImportException>> importFromTmx({
    required String filePath,
  }) async {
    try {
      _logger.info('Starting TMX import', {'filePath': filePath});

      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(TmImportException(
          'TMX file not found: $filePath',
          filePath: filePath,
        ));
      }

      // Read and parse XML
      final xmlString = await file.readAsString(encoding: utf8);
      final document = XmlDocument.parse(xmlString);

      // Validate TMX structure
      final tmx = document.findElements('tmx').firstOrNull;
      if (tmx == null) {
        return Err(TmImportException(
          'Invalid TMX file: missing tmx element',
          filePath: filePath,
        ));
      }

      // Get header for metadata
      final header = tmx.findElements('header').firstOrNull;
      final sourceLanguage = header?.getAttribute('srclang') ?? 'en';

      _logger.debug('TMX header parsed', {
        'sourceLanguage': sourceLanguage,
        'creationTool': header?.getAttribute('creationtool'),
      });

      // Parse translation units from body
      final body = tmx.findElements('body').firstOrNull;
      if (body == null) {
        return Err(TmImportException(
          'Invalid TMX file: missing body element',
          filePath: filePath,
        ));
      }

      final entries = <TmxEntry>[];
      int skippedCount = 0;

      for (final tu in body.findElements('tu')) {
        final entryResult = _parseTranslationUnit(tu, sourceLanguage);
        if (entryResult != null) {
          entries.add(entryResult);
        } else {
          skippedCount++;
        }
      }

      _logger.info('TMX import completed', {
        'filePath': filePath,
        'entriesImported': entries.length,
        'entriesSkipped': skippedCount,
      });

      return Ok(entries);
    } catch (e, stackTrace) {
      _logger.error('Failed to import TMX', e, stackTrace);
      return Err(TmImportException(
        'Failed to import TMX: ${e.toString()}',
        filePath: filePath,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Parse a translation unit (TU) element into a TmxEntry.
  ///
  /// Returns null if the TU is invalid or incomplete.
  TmxEntry? _parseTranslationUnit(XmlElement tu, String defaultSourceLang) {
    try {
      String? sourceText;
      String? targetText;
      String? sourceLanguage = defaultSourceLang;
      String? targetLanguage;
      final properties = <String, String>{};

      // Extract properties
      for (final prop in tu.findElements('prop')) {
        final type = prop.getAttribute('type') ?? '';
        final value = prop.innerText;
        if (type.isNotEmpty) {
          properties[type] = value;
        }
      }

      // Extract source and target text variants
      for (final tuv in tu.findElements('tuv')) {
        final lang = tuv.getAttribute('xml:lang') ?? '';
        final seg = tuv.findElements('seg').firstOrNull;

        if (seg != null && lang.isNotEmpty) {
          final text = seg.innerText;

          if (lang == defaultSourceLang) {
            sourceText = text;
            sourceLanguage = lang;
          } else {
            targetText = text;
            targetLanguage = lang;
          }
        }
      }

      // Validate that we have both source and target
      if (sourceText == null ||
          targetText == null ||
          sourceLanguage == null ||
          targetLanguage == null) {
        _logger.warning('Skipping incomplete translation unit', {
          'hasSource': sourceText != null,
          'hasTarget': targetText != null,
        });
        return null;
      }

      // Parse custom properties
      final usageCount = int.tryParse(
        properties['x-usage-count'] ?? '0',
      ) ?? 0;
      final providerId = properties['x-provider-id'];

      return TmxEntry(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        sourceText: sourceText,
        targetText: targetText,
        usageCount: usageCount,
        translationProviderId: providerId,
      );
    } catch (e) {
      _logger.warning('Failed to parse translation unit', e);
      return null;
    }
  }

  /// Persist imported TMX entries to the database.
  ///
  /// [entries]: List of TMX entries to persist
  /// [overwriteExisting]: If true, updates existing entries with same source hash
  /// [onProgress]: Optional callback to report progress (processed, total)
  ///
  /// Returns Ok(int) with number of entries persisted,
  /// Err(TmImportException) on failure
  Future<Result<int, TmImportException>> persistTmxEntries({
    required List<TmxEntry> entries,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      _logger.info('Persisting TMX entries', {
        'totalEntries': entries.length,
        'overwriteExisting': overwriteExisting,
      });

      int persistedCount = 0;
      int skippedCount = 0;
      final total = entries.length;

      for (int i = 0; i < total; i++) {
        final entry = entries[i];

        // Calculate source hash using SHA256 for collision resistance
        final normalized = _normalizer.normalize(entry.sourceText);
        final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

        // Check if entry already exists
        final existingResult = await _repository.findByHash(
          sourceHash,
          entry.targetLanguage,
        );

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        if (existingResult.isOk && !overwriteExisting) {
          // Entry exists and we're not overwriting - skip
          skippedCount++;
          _logger.debug('Skipping existing entry', {
            'sourceText': entry.sourceText.substring(
              0,
              entry.sourceText.length < 50 ? entry.sourceText.length : 50,
            ),
          });
        } else {
          // Create new entry with UUID for unique identification
          final tmEntry = TranslationMemoryEntry(
            id: const Uuid().v4(),
            sourceText: entry.sourceText,
            translatedText: entry.targetText,
            sourceLanguageId: entry.sourceLanguage,
            targetLanguageId: entry.targetLanguage,
            sourceHash: sourceHash,
            usageCount: entry.usageCount,
            translationProviderId: entry.translationProviderId,
            createdAt: now,
            lastUsedAt: now,
            updatedAt: now,
          );

          final insertResult = await _repository.insert(tmEntry);

          if (insertResult.isOk) {
            persistedCount++;
          } else {
            _logger.warning('Failed to persist TMX entry', {
              'error': insertResult.error.toString(),
            });
          }
        }

        // Report progress
        onProgress?.call(i + 1, total);
      }

      _logger.info('TMX entries persisted', {
        'persisted': persistedCount,
        'skipped': skippedCount,
      });

      return Ok(persistedCount);
    } catch (e, stackTrace) {
      _logger.error('Failed to persist TMX entries', e, stackTrace);
      return Err(TmImportException(
        'Failed to persist TMX entries: ${e.toString()}',
        processedEntries: 0,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }
}

/// Represents a translation memory entry parsed from TMX.
///
/// This is a lightweight model used during TMX import before
/// converting to the full TranslationMemoryEntry model.
class TmxEntry {
  final String sourceLanguage;
  final String targetLanguage;
  final String sourceText;
  final String targetText;
  final int usageCount;
  final String? translationProviderId;

  const TmxEntry({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.targetText,
    this.usageCount = 0,
    this.translationProviderId,
  });

  @override
  String toString() => 'TmxEntry($sourceLanguage -> $targetLanguage: '
      '"${sourceText.substring(0, sourceText.length < 30 ? sourceText.length : 30)}...")';
}
