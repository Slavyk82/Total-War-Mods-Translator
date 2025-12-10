import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Data transfer object for a single translation entry
class TranslationExportData {
  final String id;
  final String key;
  final String sourceText;
  final String translatedText;
  final String status;

  const TranslationExportData({
    required this.id,
    required this.key,
    required this.sourceText,
    required this.translatedText,
    required this.status,
  });

  /// Convert to map for CSV/Excel export
  Map<String, String> toMap({String? languageSuffix}) {
    final translatedKey = languageSuffix != null
        ? 'translated_text_$languageSuffix'
        : 'translated_text';
    return {
      'key': key,
      'source_text': sourceText,
      translatedKey: translatedText,
      'status': status,
      if (languageSuffix != null) 'language': languageSuffix,
    };
  }

  /// Convert to TranslationMemoryEntry for TMX export
  TranslationMemoryEntry toTmxEntry({
    String sourceLanguageId = 'lang_en',
    required String targetLanguageId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return TranslationMemoryEntry(
      id: id.isNotEmpty ? id : const Uuid().v4(),
      sourceText: sourceText,
      translatedText: translatedText,
      sourceLanguageId: sourceLanguageId,
      targetLanguageId: targetLanguageId,
      sourceHash: sha256.convert(utf8.encode(sourceText)).toString(),
      usageCount: 0,
      translationProviderId: null,
      createdAt: now,
      lastUsedAt: now,
      updatedAt: now,
    );
  }
}

/// Collects translation data for export operations
///
/// Responsible for fetching and transforming translation data
/// from repositories into export-ready format.
class ExportDataCollector {
  final ProjectLanguageRepository _projectLanguageRepository;
  final TranslationUnitRepository _translationUnitRepository;
  final TranslationVersionRepository _translationVersionRepository;
  final LoggingService _logger;

  ExportDataCollector({
    required ProjectLanguageRepository projectLanguageRepository,
    required TranslationUnitRepository translationUnitRepository,
    required TranslationVersionRepository translationVersionRepository,
    LoggingService? logger,
  })  : _projectLanguageRepository = projectLanguageRepository,
        _translationUnitRepository = translationUnitRepository,
        _translationVersionRepository = translationVersionRepository,
        _logger = logger ?? LoggingService.instance;

  /// Fetch translations for a specific language from the database
  ///
  /// Returns a list of [TranslationExportData] suitable for export.
  Future<List<TranslationExportData>> fetchTranslationsForLanguage({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      // Get project language entity
      final projectLanguageResult =
          await _projectLanguageRepository.getByProjectAndLanguage(
        projectId,
        languageCode,
      );

      if (projectLanguageResult.isErr) {
        _logger.warning('Project language not found', {
          'projectId': projectId,
          'languageCode': languageCode,
        });
        return [];
      }

      final projectLanguage = projectLanguageResult.unwrap();

      // Get all translation units for the project
      final unitsResult = await _translationUnitRepository.getActive(projectId);

      if (unitsResult.isErr) {
        _logger.error(
            'Failed to fetch translation units', unitsResult.unwrapErr());
        return [];
      }

      final units = unitsResult.unwrap();
      final translations = <TranslationExportData>[];

      // For each unit, get its translation version
      for (final unit in units) {
        final versionResult =
            await _translationVersionRepository.getByUnitAndProjectLanguage(
          unitId: unit.id,
          projectLanguageId: projectLanguage.id,
        );

        if (versionResult.isErr) {
          // No translation for this unit, skip
          continue;
        }

        final version = versionResult.unwrap();

        // If validatedOnly is true, only include translated status (not needsReview)
        if (validatedOnly && !version.isTranslated) {
          continue;
        }

        // Skip if no translated text
        if (version.translatedText == null || version.translatedText!.isEmpty) {
          continue;
        }

        translations.add(TranslationExportData(
          id: version.id,
          key: unit.key,
          sourceText: unit.sourceText,
          translatedText: version.translatedText!,
          status: version.status.toString().split('.').last,
        ));
      }

      return translations;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch translations for language', e, stackTrace);
      return [];
    }
  }

  /// Collect translations for multiple languages
  ///
  /// Returns a map of language code to list of translations.
  Future<Map<String, List<TranslationExportData>>>
      collectTranslationsForLanguages({
    required String projectId,
    required List<String> languageCodes,
    required bool validatedOnly,
    void Function(String languageCode, int index, int total)? onLanguageProgress,
  }) async {
    final result = <String, List<TranslationExportData>>{};

    for (var i = 0; i < languageCodes.length; i++) {
      final languageCode = languageCodes[i];
      onLanguageProgress?.call(languageCode, i, languageCodes.length);

      final translations = await fetchTranslationsForLanguage(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: validatedOnly,
      );

      result[languageCode] = translations;
    }

    return result;
  }

  /// Flatten translations into a single list with language suffix
  ///
  /// Converts multi-language translations into a flat list of maps
  /// suitable for tabular export (CSV/Excel).
  List<Map<String, String>> flattenForTabularExport(
    Map<String, List<TranslationExportData>> translationsByLanguage,
  ) {
    final data = <Map<String, String>>[];

    for (final entry in translationsByLanguage.entries) {
      final languageCode = entry.key;
      final translations = entry.value;

      for (final translation in translations) {
        data.add(translation.toMap(languageSuffix: languageCode));
      }
    }

    return data;
  }

  /// Count total entries across all languages
  int countTotalEntries(
      Map<String, List<TranslationExportData>> translationsByLanguage) {
    return translationsByLanguage.values
        .fold(0, (sum, list) => sum + list.length);
  }
}
