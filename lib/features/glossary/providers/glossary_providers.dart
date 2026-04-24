import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart' hide settingsServiceProvider;

part 'glossary_providers.g.dart';

/// All glossaries for the application, optionally filtered by game.
///
/// If [gameCode] is provided only glossaries scoped to that game are returned,
/// otherwise every glossary is returned.
@riverpod
Future<List<Glossary>> glossaries(Ref ref, {String? gameCode}) async {
  final logging = ref.watch(loggingServiceProvider);
  logging.debug('Starting glossaries provider', {
    'gameCode': gameCode,
  });
  try {
    final service = ref.watch(glossaryServiceProvider);

    final result = await service.getAllGlossaries(gameCode: gameCode);

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

/// Distinct languages used by any project of the given [gameCode].
///
/// Used to populate the per-game language switcher in the glossary screen.
@riverpod
Future<List<Language>> glossaryAvailableLanguages(
  Ref ref,
  String gameCode,
) async {
  final repo = ref.watch(projectLanguageRepositoryProvider);
  final result = await repo.distinctLanguagesForGameCode(gameCode);
  return result.when(
    ok: (languages) => languages,
    err: (error) => throw error,
  );
}

/// Persisted per-game selected glossary language id.
///
/// The selection is stored in settings under a per-game key so switching games
/// restores the previous language choice.
@riverpod
class SelectedGlossaryLanguage extends _$SelectedGlossaryLanguage {
  static String _key(String gameCode) =>
      'glossary_selected_language_$gameCode';

  @override
  Future<String?> build(String gameCode) async {
    final settings = ref.read(settingsServiceProvider);
    final saved = await settings.getString(_key(gameCode));
    return saved.isEmpty ? null : saved;
  }

  /// Persist the selected language id for [gameCode] (or clear when null).
  Future<void> setLanguageId(String gameCode, String? languageId) async {
    final settings = ref.read(settingsServiceProvider);
    if (languageId == null) {
      await settings.setString(_key(gameCode), '');
    } else {
      await settings.setString(_key(gameCode), languageId);
    }
    state = AsyncData(languageId);
  }
}

/// Glossary currently in use, resolved from the selected game and the
/// per-game selected language.
///
/// Returns `null` when either no game is selected, no language has been
/// chosen yet, or no glossary exists for that (game, language) pair.
@riverpod
Future<Glossary?> currentGlossary(Ref ref) async {
  final game = await ref.watch(selectedGameProvider.future);
  if (game == null) return null;

  final languageId =
      await ref.watch(selectedGlossaryLanguageProvider(game.code).future);
  if (languageId == null) return null;

  final service = ref.watch(glossaryServiceProvider);
  final result = await service.getGlossaryByGameAndLanguage(
    gameCode: game.code,
    targetLanguageId: languageId,
  );
  return result.when(
    ok: (glossary) => glossary,
    err: (error) => throw error,
  );
}

/// Glossary entries with filtering and pagination
@riverpod
Future<List<GlossaryEntry>> glossaryEntries(
  Ref ref, {
  required String glossaryId,
  String? targetLanguageCode,
}) async {
  final logging = ref.watch(loggingServiceProvider);
  logging.debug('[glossaryEntriesProvider] Fetching entries', {
    'glossaryId': glossaryId,
    'targetLanguageCode': targetLanguageCode,
  });

  final service = ref.watch(glossaryServiceProvider);
  final result = await service.getEntriesByGlossary(
    glossaryId: glossaryId,
    targetLanguageCode: targetLanguageCode,
  );

  return result.when(
    ok: (entries) {
      logging.debug('[glossaryEntriesProvider] Fetched entries', {
        'count': entries.length,
      });
      return entries;
    },
    err: (error) {
      logging.error('[glossaryEntriesProvider] ERROR', error);
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

  final service = ref.watch(glossaryServiceProvider);
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
  final service = ref.watch(glossaryServiceProvider);
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
    final logging = ref.read(loggingServiceProvider);
    logging.debug('[GlossaryEntryEditor.save] Starting save operation', {
      'mode': state != null ? 'UPDATE' : 'ADD NEW',
      'glossaryId': glossaryId,
      'targetLanguageCode': targetLanguageCode,
      'sourceTerm': sourceTerm,
      'targetTerm': targetTerm,
      'notes': notes,
    });

    final service = ref.read(glossaryServiceProvider);

    if (state != null) {
      // Update existing entry
      logging.debug('[GlossaryEntryEditor.save] Updating existing entry', {
        'entryId': state!.id,
      });
      final updated = state!.copyWith(
        sourceTerm: sourceTerm,
        targetTerm: targetTerm,
        caseSensitive: caseSensitive,
        notes: notes,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await service.updateEntry(updated);
      result.when(
        ok: (entry) => logging.debug('[GlossaryEntryEditor.save] Entry updated successfully', {'entryId': entry.id}),
        err: (error) => logging.error('[GlossaryEntryEditor.save] ERROR updating entry', error),
      );

      if (result.isErr) {
        throw Exception('Failed to update entry: ${result.error}');
      }
    } else {
      // Add new entry
      logging.debug('[GlossaryEntryEditor.save] Adding new entry...');
      final result = await service.addEntry(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
        sourceTerm: sourceTerm,
        targetTerm: targetTerm,
        caseSensitive: caseSensitive,
        notes: notes,
      );

      result.when(
        ok: (entry) => logging.debug('[GlossaryEntryEditor.save] Entry added successfully', {'entryId': entry.id}),
        err: (error) => logging.error('[GlossaryEntryEditor.save] ERROR adding entry', error),
      );

      if (result.isErr) {
        throw Exception('Failed to add entry: ${result.error}');
      }

      // Emit activity event for a successful single add.
      unawaited(ref.read(activityLoggerProvider).log(
            ActivityEventType.glossaryEnriched,
            payload: const {'count': 1},
          ));
      if (ref.mounted) {
        ref.invalidate(activityFeedProvider);
      }
    }

    // Clear editor state only if still mounted
    if (ref.mounted) {
      logging.debug('[GlossaryEntryEditor.save] Clearing editor state');
      state = null;
    } else {
      logging.warning('[GlossaryEntryEditor.save] Provider not mounted, skipping state clear');
    }

    logging.debug('[GlossaryEntryEditor.save] Save operation completed');
  }

  Future<void> delete(String entryId) async {
    final service = ref.read(glossaryServiceProvider);
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
      final service = ref.read(glossaryServiceProvider);
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

      // Emit activity event for a successful bulk CSV import.
      if (count > 0) {
        unawaited(ref.read(activityLoggerProvider).log(
              ActivityEventType.glossaryEnriched,
              payload: {'count': count},
            ));
        if (ref.mounted) {
          ref.invalidate(activityFeedProvider);
        }
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
      final service = ref.read(glossaryServiceProvider);
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

      // Emit activity event for a successful bulk TBX import.
      if (count > 0) {
        unawaited(ref.read(activityLoggerProvider).log(
              ActivityEventType.glossaryEnriched,
              payload: {'count': count},
            ));
        if (ref.mounted) {
          ref.invalidate(activityFeedProvider);
        }
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
      final service = ref.read(glossaryServiceProvider);
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

      // Emit activity event for a successful bulk Excel import.
      if (count > 0) {
        unawaited(ref.read(activityLoggerProvider).log(
              ActivityEventType.glossaryEnriched,
              payload: {'count': count},
            ));
        if (ref.mounted) {
          ref.invalidate(activityFeedProvider);
        }
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
      final service = ref.read(glossaryServiceProvider);
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
      final service = ref.read(glossaryServiceProvider);
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
      final service = ref.read(glossaryServiceProvider);
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
