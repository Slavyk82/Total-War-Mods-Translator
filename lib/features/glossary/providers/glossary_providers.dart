import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/logging_service.dart';

part 'glossary_providers.g.dart';

/// All glossaries (global + project-specific)
@riverpod
Future<List<Glossary>> glossaries(
  Ref ref, {
  String? projectId,
  bool includeGlobal = true,
}) async {
  final logging = ServiceLocator.get<LoggingService>();
  logging.debug('Starting glossaries provider', {
    'projectId': projectId,
    'includeGlobal': includeGlobal,
  });
  try {
    final service = ServiceLocator.get<IGlossaryService>();

    final result = await service.getAllGlossaries(
      projectId: projectId,
      includeGlobal: includeGlobal,
    );

    return result.when(
      ok: (glossaries) {
        logging.debug('Successfully loaded glossaries', {
          'count': glossaries.length,
        });
        return glossaries;
      },
      err: (error) {
        logging.error('Failed to load glossaries', error);
        throw error;
      },
    );
  } catch (e, stackTrace) {
    logging.error('Exception in glossaries provider', e, stackTrace);
    rethrow;
  }
}

/// Selected glossary
@riverpod
class SelectedGlossary extends _$SelectedGlossary {
  @override
  Glossary? build() => null;

  void select(Glossary? glossary) {
    state = glossary;
  }

  void clear() {
    state = null;
  }
}

/// Glossary entries with filtering and pagination
@riverpod
Future<List<GlossaryEntry>> glossaryEntries(
  Ref ref, {
  required String glossaryId,
  String? targetLanguageCode,
}) async {
  print('[glossaryEntriesProvider] Fetching entries for:');
  print('  glossaryId: $glossaryId');
  print('  targetLanguageCode: $targetLanguageCode');
  
  final service = ServiceLocator.get<IGlossaryService>();
  final result = await service.getEntriesByGlossary(
    glossaryId: glossaryId,
    targetLanguageCode: targetLanguageCode,
  );

  return result.when(
    ok: (entries) {
      print('[glossaryEntriesProvider] Fetched ${entries.length} entries');
      return entries;
    },
    err: (error) {
      print('[glossaryEntriesProvider] ERROR: $error');
      throw error;
    },
  );
}

/// Search glossary entries
@riverpod
Future<List<GlossaryEntry>> glossarySearchResults(
  Ref ref, {
  required String query,
  List<String>? glossaryIds,
  String? targetLanguageCode,
}) async {
  if (query.isEmpty) {
    return [];
  }

  final service = ServiceLocator.get<IGlossaryService>();
  final result = await service.searchEntries(
    query: query,
    glossaryIds: glossaryIds,
    targetLanguageCode: targetLanguageCode,
  );

  return result.when(
    ok: (entries) => entries,
    err: (error) => throw error,
  );
}

/// Glossary statistics
@riverpod
Future<GlossaryStatistics> glossaryStatistics(
  Ref ref,
  String glossaryId,
) async {
  final service = ServiceLocator.get<IGlossaryService>();
  final result = await service.getGlossaryStats(glossaryId);

  return result.when(
    ok: (statsMap) => GlossaryStatistics.fromJson(statsMap),
    err: (error) => throw error,
  );
}

/// Entry editor state (for add/edit)
@riverpod
class GlossaryEntryEditor extends _$GlossaryEntryEditor {
  @override
  GlossaryEntry? build() => null;

  void edit(GlossaryEntry? entry) {
    state = entry;
  }

  void clear() {
    state = null;
  }

  Future<void> save({
    required String glossaryId,
    required String targetLanguageCode,
    required String sourceTerm,
    required String targetTerm,
    bool caseSensitive = false,
    String? notes,
  }) async {
    print('[GlossaryEntryEditor.save] Starting save operation');
    print('  state: ${state != null ? "UPDATE" : "ADD NEW"}');
    print('  glossaryId: $glossaryId');
    print('  targetLanguageCode: $targetLanguageCode');
    print('  sourceTerm: "$sourceTerm"');
    print('  targetTerm: "$targetTerm"');
    print('  notes: ${notes != null ? "\"$notes\"" : "null"}');
    
    final service = ServiceLocator.get<IGlossaryService>();

    if (state != null) {
      // Update existing entry
      print('[GlossaryEntryEditor.save] Updating existing entry: ${state!.id}');
      final updated = state!.copyWith(
        sourceTerm: sourceTerm,
        targetTerm: targetTerm,
        caseSensitive: caseSensitive,
        notes: notes,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      
      final result = await service.updateEntry(updated);
      result.when(
        ok: (entry) => print('[GlossaryEntryEditor.save] Entry updated successfully: ${entry.id}'),
        err: (error) => print('[GlossaryEntryEditor.save] ERROR updating entry: $error'),
      );
      
      if (result.isErr) {
        throw Exception('Failed to update entry: ${result.error}');
      }
    } else {
      // Add new entry
      print('[GlossaryEntryEditor.save] Adding new entry...');
      final result = await service.addEntry(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
        sourceTerm: sourceTerm,
        targetTerm: targetTerm,
        caseSensitive: caseSensitive,
        notes: notes,
      );
      
      result.when(
        ok: (entry) => print('[GlossaryEntryEditor.save] Entry added successfully: ${entry.id}'),
        err: (error) => print('[GlossaryEntryEditor.save] ERROR adding entry: $error'),
      );
      
      if (result.isErr) {
        throw Exception('Failed to add entry: ${result.error}');
      }
    }

    // Clear editor state only if still mounted
    if (ref.mounted) {
      print('[GlossaryEntryEditor.save] Clearing editor state');
      state = null;
    } else {
      print('[GlossaryEntryEditor.save] WARNING: Provider not mounted, skipping state clear');
    }
    
    print('[GlossaryEntryEditor.save] Save operation completed');
  }

  Future<void> delete(String entryId) async {
    final service = ServiceLocator.get<IGlossaryService>();
    await service.deleteEntry(entryId);

    // Clear editor state only if still mounted
    if (ref.mounted) {
      state = null;
    }
  }
}

/// Filter state
@riverpod
class GlossaryFilterState extends _$GlossaryFilterState {
  @override
  GlossaryFilters build() => const GlossaryFilters();

  void setTargetLanguage(String? lang) {
    state = state.copyWith(targetLanguage: lang);
  }

  void setSearchText(String text) {
    state = state.copyWith(searchText: text);
  }

  void reset() {
    state = const GlossaryFilters();
  }
}

/// Pagination state
@riverpod
class GlossaryPageState extends _$GlossaryPageState {
  @override
  int build() => 1;

  void setPage(int page) {
    state = page;
  }

  void nextPage() {
    state = state + 1;
  }

  void previousPage() {
    if (state > 1) {
      state = state - 1;
    }
  }

  void reset() {
    state = 1;
  }
}

/// Import state
@riverpod
class GlossaryImportState extends _$GlossaryImportState {
  @override
  AsyncValue<ImportResult?> build() => const AsyncValue.data(null);

  Future<void> importCsv({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    bool skipDuplicates = true,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.importFromCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        skipDuplicates: skipDuplicates,
      );

      final count = result.when(
        ok: (imported) => imported,
        err: (error) => throw error,
      );

      state = AsyncValue.data(ImportResult(
        total: count,
        imported: count,
        skipped: 0,
        failed: 0,
      ));

      // Refresh glossaries and entries only if provider is still mounted
      if (ref.mounted) {
        ref.invalidate(glossariesProvider);
        ref.invalidate(glossaryEntriesProvider);
        ref.invalidate(glossaryStatisticsProvider);
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> importTbx({
    required String glossaryId,
    required String filePath,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

      final count = result.when(
        ok: (imported) => imported,
        err: (error) => throw error,
      );

      state = AsyncValue.data(ImportResult(
        total: count,
        imported: count,
        skipped: 0,
        failed: 0,
      ));

      // Refresh glossaries and entries only if provider is still mounted
      if (ref.mounted) {
        ref.invalidate(glossariesProvider);
        ref.invalidate(glossaryEntriesProvider);
        ref.invalidate(glossaryStatisticsProvider);
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> importExcel({
    required String glossaryId,
    required String filePath,
    required String targetLanguageCode,
    String? sheetName,
    bool skipDuplicates = true,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.importFromExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
        sheetName: sheetName,
        skipDuplicates: skipDuplicates,
      );

      final count = result.when(
        ok: (imported) => imported,
        err: (error) => throw error,
      );

      state = AsyncValue.data(ImportResult(
        total: count,
        imported: count,
        skipped: 0,
        failed: 0,
      ));

      // Refresh glossaries and entries only if provider is still mounted
      if (ref.mounted) {
        ref.invalidate(glossariesProvider);
        ref.invalidate(glossaryEntriesProvider);
        ref.invalidate(glossaryStatisticsProvider);
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Export state
@riverpod
class GlossaryExportState extends _$GlossaryExportState {
  @override
  AsyncValue<ExportResult?> build() => const AsyncValue.data(null);

  Future<void> exportCsv({
    required String glossaryId,
    required String filePath,
    String? targetLanguageCode,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.exportToCsv(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
      );

      final count = result.when(
        ok: (exported) => exported,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(ExportResult(
          entriesExported: count,
          filePath: filePath,
        ));
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> exportTbx({
    required String glossaryId,
    required String filePath,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.exportToTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

      final count = result.when(
        ok: (exported) => exported,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(ExportResult(
          entriesExported: count,
          filePath: filePath,
        ));
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> exportExcel({
    required String glossaryId,
    required String filePath,
    String? targetLanguageCode,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.exportToExcel(
        glossaryId: glossaryId,
        filePath: filePath,
        targetLanguageCode: targetLanguageCode,
      );

      final count = result.when(
        ok: (exported) => exported,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(ExportResult(
          entriesExported: count,
          filePath: filePath,
        ));
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

// Supporting classes

/// Filter configuration
class GlossaryFilters {
  final String? targetLanguage;
  final String searchText;

  const GlossaryFilters({
    this.targetLanguage,
    this.searchText = '',
  });

  GlossaryFilters copyWith({
    String? targetLanguage,
    String? searchText,
  }) {
    return GlossaryFilters(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      searchText: searchText ?? this.searchText,
    );
  }
}

/// Glossary statistics model
class GlossaryStatistics {
  final int totalEntries;
  final Map<String, int> entriesByLanguagePair;
  final int usedInTranslations;
  final int unusedEntries;
  final double usageRate;
  final double consistencyScore;
  final int duplicatesDetected;
  final int missingTranslations;
  final int forbiddenTerms;
  final int caseSensitiveTerms;

  const GlossaryStatistics({
    required this.totalEntries,
    required this.entriesByLanguagePair,
    required this.usedInTranslations,
    required this.unusedEntries,
    required this.usageRate,
    required this.consistencyScore,
    required this.duplicatesDetected,
    required this.missingTranslations,
    required this.forbiddenTerms,
    required this.caseSensitiveTerms,
  });

  factory GlossaryStatistics.fromJson(Map<String, dynamic> json) {
    return GlossaryStatistics(
      totalEntries: json['totalEntries'] as int? ?? 0,
      entriesByLanguagePair:
          (json['entriesByLanguagePair'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v as int)) ??
              {},
      usedInTranslations: json['usedInTranslations'] as int? ?? 0,
      unusedEntries: json['unusedEntries'] as int? ?? 0,
      usageRate: (json['usageRate'] as num?)?.toDouble() ?? 0.0,
      consistencyScore: (json['consistencyScore'] as num?)?.toDouble() ?? 1.0,
      duplicatesDetected: json['duplicatesDetected'] as int? ?? 0,
      missingTranslations: json['missingTranslations'] as int? ?? 0,
      forbiddenTerms: json['forbiddenTerms'] as int? ?? 0,
      caseSensitiveTerms: json['caseSensitiveTerms'] as int? ?? 0,
    );
  }
}

/// Import result
class ImportResult {
  final int total;
  final int imported;
  final int skipped;
  final int failed;

  const ImportResult({
    required this.total,
    required this.imported,
    required this.skipped,
    required this.failed,
  });

  String get summary =>
      'Total: $total | Imported: $imported | Skipped: $skipped | Failed: $failed';
}

/// Export result
class ExportResult {
  final int entriesExported;
  final String filePath;

  const ExportResult({
    required this.entriesExported,
    required this.filePath,
  });

  String get summary => 'Exported $entriesExported entries to $filePath';
}
