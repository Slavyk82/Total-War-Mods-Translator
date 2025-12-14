import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart';
import 'package:twmt/services/glossary/glossary_import_export_service.dart';
import 'package:twmt/services/glossary/glossary_matching_service.dart';
import 'package:twmt/services/glossary/glossary_statistics_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of glossary service
///
/// Handles core CRUD operations and validation.
/// Delegates to specialized services:
/// - GlossaryImportExportService: Import/export operations
/// - GlossaryDeepLService: DeepL integration
/// - GlossaryMatchingService: Term matching and substitutions
/// - GlossaryStatisticsService: Statistics calculations
class GlossaryServiceImpl implements IGlossaryService {
  final GlossaryRepository _repository;
  final SettingsService _settingsService;
  final Uuid _uuid = const Uuid();

  // Delegate services
  late final GlossaryImportExportService _importExportService;
  late final GlossaryDeepLService _deeplService;
  late final GlossaryMatchingService _matchingService;
  late final GlossaryStatisticsService _statisticsService;

  GlossaryServiceImpl({
    required GlossaryRepository repository,
    required SettingsService settingsService,
  })  : _repository = repository,
        _settingsService = settingsService {
    _importExportService = GlossaryImportExportService(_repository, this);
    _deeplService = GlossaryDeepLService(
      glossaryRepository: _repository,
      settingsService: _settingsService,
    );
    _matchingService = GlossaryMatchingService(_repository);
    _statisticsService = GlossaryStatisticsService(_repository);
  }

  // ============================================================================
  // Glossary CRUD Operations
  // ============================================================================

  @override
  Future<Result<Glossary, GlossaryException>> createGlossary({
    required String name,
    String? description,
    required bool isGlobal,
    String? gameInstallationId,
    required String targetLanguageId,
  }) async {
    try {
      LoggingService.instance.debug('Creating glossary', {
        'name': name,
        'isGlobal': isGlobal,
        'gameInstallationId': gameInstallationId,
        'targetLanguageId': targetLanguageId,
      });

      // Validate input
      if (name.trim().isEmpty) {
        LoggingService.instance.debug('Validation failed: name is empty');
        return Err(
          InvalidGlossaryDataException(['Name cannot be empty']),
        );
      }

      if (!isGlobal && gameInstallationId == null) {
        LoggingService.instance.debug('Validation failed: game-specific requires gameInstallationId');
        return Err(
          InvalidGlossaryDataException(
            ['Game-specific glossary requires gameInstallationId'],
          ),
        );
      }

      // Check for duplicate name
      LoggingService.instance.debug('Checking for duplicate name', {'name': name});
      final existing = await _repository.getByName(name);
      if (existing != null) {
        LoggingService.instance.debug('Duplicate name found', {'id': existing.id});
        return Err(GlossaryAlreadyExistsException(name));
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final glossary = Glossary(
        id: _uuid.v4(),
        name: name.trim(),
        description: description?.trim(),
        isGlobal: isGlobal,
        gameInstallationId: gameInstallationId,
        targetLanguageId: targetLanguageId,
        entryCount: 0,
        createdAt: now,
        updatedAt: now,
      );

      LoggingService.instance.debug('Inserting glossary', {'glossary': glossary.toJson()});
      await _repository.insertGlossary(glossary);
      LoggingService.instance.info('Glossary created successfully', {'id': glossary.id});

      return Ok(glossary);
    } catch (e, stackTrace) {
      LoggingService.instance.error('Error creating glossary', e, stackTrace);
      return Err(
        GlossaryDatabaseException('Failed to create glossary', e),
      );
    }
  }

  @override
  Future<Result<Glossary, GlossaryException>> getGlossaryById(
    String id,
  ) async {
    try {
      final glossary = await _repository.getGlossaryById(id);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(id));
      }
      return Ok(glossary);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get glossary', e),
      );
    }
  }

  @override
  Future<Result<List<Glossary>, GlossaryException>> getAllGlossaries({
    String? gameInstallationId,
    bool includeUniversal = true,
  }) async {
    try {
      final glossaries = await _repository.getAllGlossaries(
        gameInstallationId: gameInstallationId,
        includeUniversal: includeUniversal,
      );
      return Ok(glossaries);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get glossaries', e),
      );
    }
  }

  @override
  Future<Result<Glossary, GlossaryException>> updateGlossary(
    Glossary glossary,
  ) async {
    try {
      // Check if exists
      final existing = await _repository.getGlossaryById(glossary.id);
      if (existing == null) {
        return Err(GlossaryNotFoundException(glossary.id));
      }

      // Check for name conflict (if name changed)
      if (existing.name != glossary.name) {
        final nameConflict = await _repository.getByName(glossary.name);
        if (nameConflict != null && nameConflict.id != glossary.id) {
          return Err(GlossaryAlreadyExistsException(glossary.name));
        }
      }

      final updated = glossary.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await _repository.updateGlossary(updated);

      return Ok(updated);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to update glossary', e),
      );
    }
  }

  @override
  Future<Result<void, GlossaryException>> deleteGlossary(String id) async {
    try {
      // Check if exists
      final glossary = await _repository.getGlossaryById(id);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(id));
      }

      // Delete glossary (cascade deletes entries)
      await _repository.deleteGlossary(id);

      return Ok(null);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to delete glossary', e),
      );
    }
  }

  // ============================================================================
  // Glossary Entry CRUD Operations
  // ============================================================================

  @override
  Future<Result<GlossaryEntry, GlossaryException>> addEntry({
    required String glossaryId,
    required String targetLanguageCode,
    required String sourceTerm,
    required String targetTerm,
    bool caseSensitive = false,
    String? notes,
  }) async {
    try {
      LoggingService.instance.debug('Adding glossary entry', {
        'glossaryId': glossaryId,
        'targetLanguageCode': targetLanguageCode,
        'sourceTerm': sourceTerm,
        'targetTerm': targetTerm,
        'caseSensitive': caseSensitive,
        'notes': notes,
      });

      // Validate glossary exists
      LoggingService.instance.debug('Checking if glossary exists', {'glossaryId': glossaryId});
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        LoggingService.instance.warning('Glossary not found', {'glossaryId': glossaryId});
        return Err(GlossaryNotFoundException(glossaryId));
      }
      LoggingService.instance.debug('Glossary found', {'name': glossary.name});

      // Validate input
      if (sourceTerm.trim().isEmpty || targetTerm.trim().isEmpty) {
        LoggingService.instance.debug('Empty terms detected');
        return Err(
          InvalidGlossaryDataException(['Terms cannot be empty']),
        );
      }

      // Check for duplicate term
      LoggingService.instance.debug('Checking for duplicate entry');
      final duplicate = await _repository.findDuplicateEntry(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
        sourceTerm: sourceTerm.trim(),
      );

      if (duplicate != null) {
        LoggingService.instance.debug('Duplicate entry found', {'id': duplicate.id});
        return Err(
          DuplicateGlossaryEntryException(sourceTerm.trim(), glossaryId),
        );
      }
      LoggingService.instance.debug('No duplicate found, proceeding');

      final now = DateTime.now().millisecondsSinceEpoch;
      final trimmedNotes = notes?.trim();
      final entry = GlossaryEntry(
        id: _uuid.v4(),
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
        sourceTerm: sourceTerm.trim(),
        targetTerm: targetTerm.trim(),
        caseSensitive: caseSensitive,
        notes: trimmedNotes?.isNotEmpty == true ? trimmedNotes : null,
        createdAt: now,
        updatedAt: now,
      );

      LoggingService.instance.debug('Created entry object', {'entry': entry.toJson()});
      LoggingService.instance.debug('Calling repository.insertEntry');
      await _repository.insertEntry(entry);
      LoggingService.instance.debug('Entry inserted successfully');

      // Update glossary entry count
      LoggingService.instance.debug('Updating glossary entry count');
      await _updateGlossaryEntryCount(glossaryId);
      LoggingService.instance.debug('Entry count updated');

      LoggingService.instance.info('Entry added successfully', {'id': entry.id});
      return Ok(entry);
    } catch (e, stackTrace) {
      LoggingService.instance.error('Error adding entry', e, stackTrace);
      return Err(
        GlossaryDatabaseException('Failed to add entry', e),
      );
    }
  }

  @override
  Future<Result<GlossaryEntry, GlossaryException>> getEntryById(
    String id,
  ) async {
    try {
      final entry = await _repository.getEntryById(id);
      if (entry == null) {
        return Err(GlossaryEntryNotFoundException(id));
      }
      return Ok(entry);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get entry', e),
      );
    }
  }

  @override
  Future<Result<List<GlossaryEntry>, GlossaryException>> getEntriesByGlossary({
    required String glossaryId,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) async {
    try {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );
      return Ok(entries);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get entries', e),
      );
    }
  }

  @override
  Future<Result<GlossaryEntry, GlossaryException>> updateEntry(
    GlossaryEntry entry,
  ) async {
    try {
      // Check if exists
      final existing = await _repository.getEntryById(entry.id);
      if (existing == null) {
        return Err(GlossaryEntryNotFoundException(entry.id));
      }

      final updated = entry.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await _repository.updateEntry(updated);

      return Ok(updated);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to update entry', e),
      );
    }
  }

  @override
  Future<Result<void, GlossaryException>> deleteEntry(String id) async {
    try {
      final entry = await _repository.getEntryById(id);
      if (entry == null) {
        return Err(GlossaryEntryNotFoundException(id));
      }

      await _repository.deleteEntry(id);

      // Update glossary entry count
      await _updateGlossaryEntryCount(entry.glossaryId);

      return Ok(null);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to delete entry', e),
      );
    }
  }

  @override
  Future<Result<void, GlossaryException>> deleteEntries(
    List<String> ids,
  ) async {
    try {
      if (ids.isEmpty) return Ok(null);

      // Get glossary IDs to update counts later
      final glossaryIds = <String>{};
      for (final id in ids) {
        final entry = await _repository.getEntryById(id);
        if (entry != null) {
          glossaryIds.add(entry.glossaryId);
          // Delete entry
          await _repository.deleteEntry(id);
        }
      }

      // Update entry counts
      for (final glossaryId in glossaryIds) {
        await _updateGlossaryEntryCount(glossaryId);
      }

      return Ok(null);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to delete entries', e),
      );
    }
  }

  // ============================================================================
  // Term Matching & Detection (Delegated to GlossaryMatchingService)
  // ============================================================================

  @override
  Future<Result<List<GlossaryEntry>, GlossaryException>> findMatchingTerms({
    required String sourceText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) =>
      _matchingService.findMatchingTerms(
        sourceText: sourceText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        glossaryIds: glossaryIds,
        gameInstallationId: gameInstallationId,
      );

  @override
  Future<Result<String, GlossaryException>> applySubstitutions({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) =>
      _matchingService.applySubstitutions(
        sourceText: sourceText,
        targetText: targetText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        glossaryIds: glossaryIds,
        gameInstallationId: gameInstallationId,
      );

  // ============================================================================
  // Validation
  // ============================================================================

  @override
  Future<Result<List<String>, GlossaryException>> validateGlossary(
    String glossaryId,
  ) async {
    try {
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      final errors = <String>[];
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
      );

      // Check for empty terms
      for (final entry in entries) {
        if (entry.sourceTerm.trim().isEmpty) {
          errors.add('Entry ${entry.id}: Empty source term');
        }
        if (entry.targetTerm.trim().isEmpty) {
          errors.add('Entry ${entry.id}: Empty target term');
        }
      }

      // Check for duplicates
      final seen = <String, List<GlossaryEntry>>{};
      for (final entry in entries) {
        final key =
            '${entry.targetLanguageCode}:${entry.sourceTerm.toLowerCase()}';
        seen.putIfAbsent(key, () => []).add(entry);
      }

      for (final MapEntry(value: duplicates) in seen.entries) {
        if (duplicates.length > 1) {
          final terms = duplicates.map((e) => e.sourceTerm).join(', ');
          errors.add('Duplicate term: $terms');
        }
      }

      // Check for conflicting translations
      final termTranslations = <String, Set<String>>{};
      for (final entry in entries) {
        final key =
            '${entry.targetLanguageCode}:${entry.sourceTerm.toLowerCase()}';
        termTranslations.putIfAbsent(key, () => {}).add(entry.targetTerm);
      }

      for (final MapEntry(key: key, value: translations)
          in termTranslations.entries) {
        if (translations.length > 1) {
          errors.add(
              'Conflicting translations for $key: ${translations.join(", ")}');
        }
      }

      return Ok(errors);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to validate glossary', e),
      );
    }
  }

  @override
  Future<Result<List<String>, GlossaryException>> checkConsistency({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) async {
    try {
      final matchResult = await findMatchingTerms(
        sourceText: sourceText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        glossaryIds: glossaryIds,
        gameInstallationId: gameInstallationId,
      );

      if (matchResult.isErr) {
        return Err(matchResult.error);
      }

      final matchedEntries = matchResult.value;
      final inconsistencies = <String>[];

      for (final entry in matchedEntries) {
        // Check if target term appears in target text
        final targetTermLower = entry.targetTerm.toLowerCase();
        final targetTextLower = targetText.toLowerCase();

        if (!targetTextLower.contains(targetTermLower)) {
          inconsistencies.add(
            'Term "${entry.sourceTerm}" should be translated as "${entry.targetTerm}" but not found in target',
          );
        }
      }

      return Ok(inconsistencies);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to check consistency', e),
      );
    }
  }

  // ============================================================================
  // Import/Export (Delegated to GlossaryImportExportService)
  // ============================================================================

  @override
  Future<Result<int, GlossaryException>> importFromCsv({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    bool skipDuplicates = true,
  }) =>
      _importExportService.importFromCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        skipDuplicates: skipDuplicates,
      );

  @override
  Future<Result<int, GlossaryException>> exportToCsv({
    required String glossaryId,
    required String filePath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) =>
      _importExportService.exportToCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

  @override
  Future<Result<int, GlossaryException>> importFromTbx({
    required String glossaryId,
    required String filePath,
  }) =>
      _importExportService.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

  @override
  Future<Result<int, GlossaryException>> exportToTbx({
    required String glossaryId,
    required String filePath,
  }) =>
      _importExportService.exportToTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

  @override
  Future<Result<int, GlossaryException>> importFromExcel({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    String? sheetName,
    bool skipDuplicates = true,
  }) =>
      _importExportService.importFromExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        sheetName: sheetName,
        skipDuplicates: skipDuplicates,
      );

  @override
  Future<Result<int, GlossaryException>> exportToExcel({
    required String glossaryId,
    required String filePath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) =>
      _importExportService.exportToExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

  // ============================================================================
  // DeepL Integration (Delegated to GlossaryDeepLService)
  // ============================================================================

  @override
  Future<Result<String, GlossaryException>> createDeepLGlossary({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) =>
      _deeplService.createDeepLGlossary(
        glossaryId: glossaryId,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

  @override
  Future<Result<void, GlossaryException>> deleteDeepLGlossary(
    String deeplGlossaryId,
  ) =>
      _deeplService.deleteDeepLGlossary(deeplGlossaryId);

  @override
  Future<Result<List<Map<String, dynamic>>, GlossaryException>>
      listDeepLGlossaries() => _deeplService.listDeepLGlossaries();

  // ============================================================================
  // Search & Statistics (Delegated to GlossaryStatisticsService)
  // ============================================================================

  @override
  Future<Result<List<GlossaryEntry>, GlossaryException>> searchEntries({
    required String query,
    List<String>? glossaryIds,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) async {
    try {
      final results = await _repository.searchEntries(
        query: query,
        glossaryIds: glossaryIds,
        targetLanguageCode: targetLanguageCode,
      );
      return Ok(results);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to search entries', e),
      );
    }
  }

  @override
  Future<Result<Map<String, dynamic>, GlossaryException>> getGlossaryStats(
    String glossaryId,
  ) =>
      _statisticsService.getGlossaryStats(glossaryId);

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /// Update glossary entry count
  /// 
  /// Note: entry_count is now calculated dynamically via SQL COUNT,
  /// so this method is a no-op. Kept for backward compatibility.
  Future<void> _updateGlossaryEntryCount(String glossaryId) async {
    // No-op: entry_count is calculated dynamically in repository queries
  }
}
