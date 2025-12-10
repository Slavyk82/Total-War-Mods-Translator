import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/logging_service.dart';

part 'tm_providers.g.dart';

/// Sort configuration
class TmSort {
  final String column;
  final bool ascending;

  const TmSort({required this.column, required this.ascending});

  /// Convert to SQL ORDER BY clause
  String toOrderBy() {
    final sqlColumn = switch (column) {
      'source' => 'source_text',
      'target' => 'translated_text',
      'usage' => 'usage_count',
      'lastUsed' => 'last_used_at',
      _ => 'usage_count',
    };
    return '$sqlColumn ${ascending ? 'ASC' : 'DESC'}';
  }
}

/// Sort state provider for TM entries (manual provider - not generated)
final tmSortStateProvider = NotifierProvider<TmSortStateNotifier, TmSort>(
  TmSortStateNotifier.new,
);

/// Sort state notifier
class TmSortStateNotifier extends Notifier<TmSort> {
  @override
  TmSort build() => const TmSort(column: 'usage', ascending: false);

  void setSort(String column, bool ascending) {
    state = TmSort(column: column, ascending: ascending);
  }

  void toggleSort(String column) {
    if (state.column == column) {
      state = TmSort(column: column, ascending: !state.ascending);
    } else {
      state = TmSort(column: column, ascending: false);
    }
  }
}

/// TM entries list with filtering and pagination
@riverpod
Future<List<TranslationMemoryEntry>> tmEntries(
  Ref ref, {
  String? targetLang,
  int page = 1,
  int pageSize = 1000,
}) async {
  // Get current sort state
  final sortState = ref.watch(tmSortStateProvider);
  final orderBy = sortState.toOrderBy();

  final logging = ServiceLocator.get<LoggingService>();
  logging.debug('Starting tmEntries provider', {
    'targetLang': targetLang,
    'page': page,
    'pageSize': pageSize,
    'orderBy': orderBy,
  });
  try {
    final service = ServiceLocator.get<ITranslationMemoryService>();
    final offset = (page - 1) * pageSize;

    final result = await service.getEntries(
      targetLanguageCode: targetLang,
      limit: pageSize,
      offset: offset,
      orderBy: orderBy,
    );

    return result.when(
      ok: (entries) {
        logging.debug('Successfully loaded TM entries', {
          'count': entries.length,
        });
        return entries;
      },
      err: (error) {
        logging.error('Failed to load TM entries', error);
        throw error;
      },
    );
  } catch (e, stackTrace) {
    logging.error('Exception in tmEntries provider', e, stackTrace);
    rethrow;
  }
}

/// Total count of TM entries (for pagination)
@riverpod
Future<int> tmEntriesCount(
  Ref ref, {
  String? targetLang,
}) async {
  final service = ServiceLocator.get<ITranslationMemoryService>();

  // Get all entries (we'll optimize this later with a count query)
  final result = await service.getEntries(
    targetLanguageCode: targetLang,
    limit: 100000, // Large limit to get all
    offset: 0,
  );

  return result.when(
    ok: (entries) => entries.length,
    err: (error) => 0,
  );
}

/// TM statistics
@riverpod
Future<TmStatistics> tmStatistics(
  Ref ref, {
  String? targetLang,
}) async {
  final logging = ServiceLocator.get<LoggingService>();
  logging.debug('Starting tmStatistics provider', {
    'targetLang': targetLang,
  });
  try {
    final service = ServiceLocator.get<ITranslationMemoryService>();

    final result = await service.getStatistics(
      targetLanguageCode: targetLang,
    );

    return result.when(
      ok: (stats) {
        logging.debug('Successfully loaded TM statistics', {
          'totalEntries': stats.totalEntries,
        });
        return stats;
      },
      err: (error) {
        logging.error('Failed to load TM statistics', error);
        throw error;
      },
    );
  } catch (e, stackTrace) {
    logging.error('Exception in tmStatistics provider', e, stackTrace);
    rethrow;
  }
}

/// Search TM entries by text
@riverpod
Future<List<TranslationMemoryEntry>> tmSearchResults(
  Ref ref, {
  required String searchText,
  TmSearchScope searchIn = TmSearchScope.both,
  String? targetLang,
  int limit = 50,
}) async {
  if (searchText.isEmpty) {
    return [];
  }

  final service = ServiceLocator.get<ITranslationMemoryService>();

  final result = await service.searchEntries(
    searchText: searchText,
    searchIn: searchIn,
    targetLanguageCode: targetLang,
    limit: limit,
  );

  return result.when(
    ok: (entries) => entries,
    err: (error) => throw error,
  );
}

/// Selected TM entry (for edit/details)
@riverpod
class SelectedTmEntry extends _$SelectedTmEntry {
  @override
  TranslationMemoryEntry? build() => null;

  void select(TranslationMemoryEntry? entry) {
    state = entry;
  }

  void clear() {
    state = null;
  }
}

/// Current filter state
@riverpod
class TmFilterState extends _$TmFilterState {
  @override
  TmFilters build() => const TmFilters();

  void setTargetLanguage(String? lang) {
    state = state.copyWith(targetLanguage: lang);
  }

  void setSearchText(String text) {
    state = state.copyWith(searchText: text);
  }

  void reset() {
    state = const TmFilters();
  }
}

/// Current page number
@riverpod
class TmPageState extends _$TmPageState {
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
class TmImportState extends _$TmImportState {
  @override
  AsyncValue<TmImportResult?> build() => const AsyncValue.data(null);

  Future<void> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<ITranslationMemoryService>();

      final result = await service.importFromTmx(
        filePath: filePath,
        overwriteExisting: overwriteExisting,
        onProgress: onProgress,
      );

      final importedCount = result.when(
        ok: (count) => count,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(TmImportResult(
          totalEntries: importedCount,
          importedEntries: importedCount,
          skippedEntries: 0,
          failedEntries: 0,
        ));

        // Refresh TM entries after import
        ref.invalidate(tmEntriesProvider);
        ref.invalidate(tmStatisticsProvider);
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
class TmExportState extends _$TmExportState {
  @override
  AsyncValue<TmExportResult?> build() => const AsyncValue.data(null);

  Future<void> exportToTmx({
    required String outputPath,
    String? targetLanguageCode,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<ITranslationMemoryService>();

      final result = await service.exportToTmx(
        outputPath: outputPath,
        targetLanguageCode: targetLanguageCode,
      );

      final exportedCount = result.when(
        ok: (count) => count,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(TmExportResult(
          entriesExported: exportedCount,
          filePath: outputPath,
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

/// Cleanup state
@riverpod
class TmCleanupState extends _$TmCleanupState {
  @override
  AsyncValue<int?> build() => const AsyncValue.data(null);

  Future<void> cleanup({
    int unusedDays = 365,
  }) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<ITranslationMemoryService>();

      final result = await service.cleanupUnusedEntries(
        unusedDays: unusedDays,
      );

      final deletedCount = result.when(
        ok: (count) => count,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(deletedCount);

        // Refresh TM entries after cleanup
        ref.invalidate(tmEntriesProvider);
        ref.invalidate(tmStatisticsProvider);
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

/// TM filter configuration
class TmFilters {
  final String? targetLanguage;
  final String searchText;

  const TmFilters({
    this.targetLanguage,
    this.searchText = '',
  });

  TmFilters copyWith({
    String? targetLanguage,
    String? searchText,
  }) {
    return TmFilters(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      searchText: searchText ?? this.searchText,
    );
  }
}

/// Import result
class TmImportResult {
  final int totalEntries;
  final int importedEntries;
  final int skippedEntries;
  final int failedEntries;

  const TmImportResult({
    required this.totalEntries,
    required this.importedEntries,
    required this.skippedEntries,
    required this.failedEntries,
  });

  String get summary =>
      'Total: $totalEntries | Imported: $importedEntries | Skipped: $skippedEntries | Failed: $failedEntries';
}

/// Export result
class TmExportResult {
  final int entriesExported;
  final String filePath;

  const TmExportResult({
    required this.entriesExported,
    required this.filePath,
  });

  String get summary => 'Exported $entriesExported entries to $filePath';
}

/// Delete TM entry state
@riverpod
class TmDeleteState extends _$TmDeleteState {
  @override
  AsyncValue<bool?> build() => const AsyncValue.data(null);

  Future<bool> deleteEntry(String entryId) async {
    state = const AsyncValue.loading();

    try {
      final service = ServiceLocator.get<ITranslationMemoryService>();

      final result = await service.deleteEntry(entryId: entryId);

      final success = result.when(
        ok: (_) => true,
        err: (error) => throw error,
      );

      if (ref.mounted) {
        state = AsyncValue.data(success);

        // Refresh TM entries after deletion
        if (success) {
          ref.invalidate(tmEntriesProvider);
          ref.invalidate(tmStatisticsProvider);
        }
      }

      return success;
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
      return false;
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}
