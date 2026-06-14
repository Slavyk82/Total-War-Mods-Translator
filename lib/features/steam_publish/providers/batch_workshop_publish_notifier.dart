import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../../../services/steam/models/steam_exceptions.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import 'steam_publish_providers.dart';

/// Info for a single item in the batch publish
class BatchPublishItemInfo {
  final String name;
  final WorkshopPublishParams params;
  final String? projectId;
  final String? compilationId;
  final String? languageCode;

  const BatchPublishItemInfo({
    required this.name,
    required this.params,
    this.projectId,
    this.compilationId,
    this.languageCode,
  });
}

/// Result of a single item publish
class BatchPublishItemResult {
  /// Index of the item in the batch — the stable identity of an item.
  /// Display names are not unique (two projects can share a mod title),
  /// so lookups must use this index, never [name].
  final int index;
  final String name;
  final bool success;
  final String? workshopId;
  final String? errorMessage;

  const BatchPublishItemResult({
    required this.index,
    required this.name,
    required this.success,
    this.workshopId,
    this.errorMessage,
  });
}

/// Status of a single item in the batch
enum BatchPublishStatus {
  pending,
  inProgress,
  success,
  failed,
  cancelled,
}

/// State for batch workshop publish
class BatchWorkshopPublishState {
  final bool isPublishing;
  final bool isCancelled;
  final int totalItems;
  final int completedItems;
  final double currentItemProgress;
  final String? currentItemName;

  /// Index (into the staged batch item list) of the item currently being
  /// published. Names are not unique, so per-row "is current" checks must
  /// use this index.
  final int? currentItemIndex;

  /// Per-item status keyed by the item's index in the batch. Display names
  /// can collide (two projects with the same mod title), so name keys would
  /// make same-named items overwrite each other's status.
  final Map<int, BatchPublishStatus> itemStatuses;
  final List<BatchPublishItemResult> results;
  final bool needsSteamGuard;

  const BatchWorkshopPublishState({
    this.isPublishing = false,
    this.isCancelled = false,
    this.totalItems = 0,
    this.completedItems = 0,
    this.currentItemProgress = 0.0,
    this.currentItemName,
    this.currentItemIndex,
    this.itemStatuses = const {},
    this.results = const [],
    this.needsSteamGuard = false,
  });

  BatchWorkshopPublishState copyWith({
    bool? isPublishing,
    bool? isCancelled,
    int? totalItems,
    int? completedItems,
    double? currentItemProgress,
    String? currentItemName,
    int? currentItemIndex,
    Map<int, BatchPublishStatus>? itemStatuses,
    List<BatchPublishItemResult>? results,
    bool? needsSteamGuard,
    bool clearCurrentItem = false,
  }) {
    return BatchWorkshopPublishState(
      isPublishing: isPublishing ?? this.isPublishing,
      isCancelled: isCancelled ?? this.isCancelled,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      currentItemProgress: currentItemProgress ?? this.currentItemProgress,
      currentItemName:
          clearCurrentItem ? null : (currentItemName ?? this.currentItemName),
      currentItemIndex: clearCurrentItem
          ? null
          : (currentItemIndex ?? this.currentItemIndex),
      itemStatuses: itemStatuses ?? this.itemStatuses,
      results: results ?? this.results,
      needsSteamGuard: needsSteamGuard ?? this.needsSteamGuard,
    );
  }

  double get overallProgress {
    if (totalItems == 0) return 0.0;
    final raw = (completedItems + currentItemProgress) / totalItems;
    return raw.clamp(0.0, 1.0);
  }

  int get successCount => results.where((r) => r.success).length;

  int get failedCount => results.where((r) => !r.success).length;

  bool get isComplete => !isPublishing && results.isNotEmpty;
}

/// Notifier for batch workshop publish
class BatchWorkshopPublishNotifier
    extends Notifier<BatchWorkshopPublishState> {
  bool _silentlyCleaned = false;

  // Cached for Steam Guard retry
  List<BatchPublishItemInfo>? _cachedItems;
  String? _cachedUsername;
  String? _cachedPassword;

  @override
  BatchWorkshopPublishState build() => const BatchWorkshopPublishState();

  /// Start batch publish using a single steamcmd process
  Future<void> publishBatch({
    required List<BatchPublishItemInfo> items,
    required String username,
    required String password,
    String? steamGuardCode,
  }) async {
    if (state.isPublishing) return;
    _silentlyCleaned = false;

    final logging = ref.read(loggingServiceProvider);
    logging.info('Starting batch workshop publish', {
      'itemCount': items.length,
    });

    // Cache for potential Steam Guard retry
    _cachedItems = items;
    _cachedUsername = username;
    _cachedPassword = password;

    // Initialize statuses, keyed by batch index (names are not unique).
    final statuses = <int, BatchPublishStatus>{
      for (var i = 0; i < items.length; i++) i: BatchPublishStatus.pending,
    };

    state = state.copyWith(
      isPublishing: true,
      isCancelled: false,
      needsSteamGuard: false,
      totalItems: items.length,
      completedItems: 0,
      itemStatuses: statuses,
      results: const [],
    );

    final service = ref.read(workshopPublishServiceProvider);
    final results = <BatchPublishItemResult>[];
    // Workshop ID DB writes are started synchronously from onItemComplete but
    // must finish before we invalidate the list, otherwise the refreshed list
    // can show just-published items as unpublished (race).
    final pendingSaves = <Future<void>>[];
    // Item index -> failure detail for Workshop ID writes that did not
    // persist (the upload succeeded but the DB write failed). Filled by the
    // pendingSaves futures; surfaced on the item's result after the batch.
    final saveFailures = <int, String>{};

    try {
      await service.publishBatch(
        items: items
            .map((item) => (name: item.name, params: item.params))
            .toList(),
        username: username,
        password: password,
        steamGuardCode: steamGuardCode,
        onItemStart: (index, name) {
          if (_silentlyCleaned) return;
          final updatedStatuses =
              Map<int, BatchPublishStatus>.from(state.itemStatuses);
          updatedStatuses[index] = BatchPublishStatus.inProgress;
          state = state.copyWith(
            currentItemName: name,
            currentItemIndex: index,
            currentItemProgress: 0.0,
            itemStatuses: updatedStatuses,
          );
        },
        onItemProgress: (index, progress) {
          if (_silentlyCleaned) return;
          state = state.copyWith(currentItemProgress: progress);
        },
        onItemComplete: (index, result) {
          if (_silentlyCleaned) return;
          final item = items[index];
          final updatedStatuses =
              Map<int, BatchPublishStatus>.from(state.itemStatuses);

          result.when(
            ok: (publishResult) {
              updatedStatuses[index] = BatchPublishStatus.success;
              results.add(BatchPublishItemResult(
                index: index,
                name: item.name,
                success: true,
                workshopId: publishResult.workshopId,
              ));
              pendingSaves.add(
                _saveWorkshopId(item, publishResult.workshopId)
                    .then((failure) {
                  if (failure != null) saveFailures[index] = failure;
                }),
              );
              logging.info('Item published successfully', {
                'name': item.name,
                'workshopId': publishResult.workshopId,
              });
            },
            err: (error) {
              updatedStatuses[index] = BatchPublishStatus.failed;
              results.add(BatchPublishItemResult(
                index: index,
                name: item.name,
                success: false,
                errorMessage: error.message,
              ));
              logging.error(
                  'Item publish failed: ${item.name} - ${error.message}');
            },
          );

          state = state.copyWith(
            completedItems: results.length,
            itemStatuses: updatedStatuses,
            results: List.from(results),
          );
        },
      );
    } on SteamGuardRequiredException {
      state = state.copyWith(
        isPublishing: false,
        needsSteamGuard: true,
      );
      return;
    } catch (e, stack) {
      logging.error('Batch publish exception', e, stack);
    }

    // Batch complete — skip if widget was disposed during publish
    if (_silentlyCleaned) return;

    // Mark remaining uncompleted items as cancelled if batch was cancelled
    if (state.isCancelled) {
      final updatedStatuses =
          Map<int, BatchPublishStatus>.from(state.itemStatuses);
      for (var i = 0; i < items.length; i++) {
        if (updatedStatuses[i] == BatchPublishStatus.pending ||
            updatedStatuses[i] == BatchPublishStatus.inProgress) {
          updatedStatuses[i] = BatchPublishStatus.cancelled;
        }
      }
      state = state.copyWith(itemStatuses: updatedStatuses);
    }

    state = state.copyWith(
      isPublishing: false,
      clearCurrentItem: true,
    );

    // Ensure all Workshop ID DB writes have committed before refreshing the
    // list, so just-published items are not shown as unpublished.
    if (pendingSaves.isNotEmpty) {
      await Future.wait(pendingSaves);
    }

    // Surface Workshop ID writes that failed AFTER a successful upload: the
    // refreshed list will still show those items as unpublished/outdated,
    // and republishing without the saved id would create a duplicate
    // Workshop item. Keep the item's success status (the upload itself
    // worked) but attach a message distinguishing 'published but id not
    // saved'. Guard the state write: the widget may have been disposed
    // while awaiting the saves.
    if (saveFailures.isNotEmpty && !_silentlyCleaned) {
      final amendedResults = state.results.map((r) {
        final failure = saveFailures[r.index];
        if (failure == null || !r.success) return r;
        return BatchPublishItemResult(
          index: r.index,
          name: r.name,
          success: true,
          workshopId: r.workshopId,
          errorMessage:
              'Published as Workshop item #${r.workshopId}, but the Workshop '
              'ID could not be saved locally ($failure). The item may still '
              'show as unpublished — set the Workshop ID manually before '
              'publishing again.',
        );
      }).toList();
      state = state.copyWith(results: amendedResults);
    }

    // Refresh exports list
    ref.invalidate(publishableItemsProvider);

    logging.info('Batch publish complete', {
      'totalItems': items.length,
      'successCount': state.successCount,
      'failedCount': state.failedCount,
      'workshopIdSaveFailures': saveFailures.length,
    });
  }

  /// Save workshop ID to project or compilation DB record.
  ///
  /// Returns null when the id was persisted, otherwise an English
  /// description of the failure. The repositories return Result and never
  /// throw, so failures must be read off the Result — the catch blocks only
  /// cover unexpected throws (e.g. ref.read after disposal). The Workshop
  /// upload itself already succeeded by the time this runs, so callers
  /// surface failures as 'published but id not saved', never as a failed
  /// upload.
  Future<String?> _saveWorkshopId(
    BatchPublishItemInfo item,
    String workshopId,
  ) async {
    final logging = ref.read(loggingServiceProvider);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (item.projectId != null) {
      try {
        final pubRepo = ref.read(projectPublicationRepositoryProvider);
        final setResult = await pubRepo.setPublication(
          item.projectId!,
          item.languageCode ?? 'fr',
          workshopId,
          now,
        );
        if (setResult.isErr) {
          final detail = setResult.error.message;
          logging.warning(
              'Failed to save Workshop ID for ${item.name}: $detail');
          return detail;
        }
      } catch (e) {
        logging.warning('Failed to save Workshop ID for ${item.name}: $e');
        return e.toString();
      }
    } else if (item.compilationId != null) {
      try {
        final compilationRepo = ref.read(compilationRepositoryProvider);
        final updateResult = await compilationRepo.updateAfterPublish(
          item.compilationId!,
          workshopId,
          now,
        );
        if (updateResult.isErr) {
          final detail = updateResult.error.message;
          logging.warning(
              'Failed to save Workshop ID for compilation ${item.name}: '
              '$detail');
          return detail;
        }
      } catch (e) {
        logging.warning(
            'Failed to save Workshop ID for compilation ${item.name}: $e');
        return e.toString();
      }
    }
    return null;
  }

  /// Retry batch with Steam Guard code
  Future<void> retryWithSteamGuard(String code) async {
    if (_cachedItems == null ||
        _cachedUsername == null ||
        _cachedPassword == null) {
      state = state.copyWith(
        isPublishing: false,
        needsSteamGuard: false,
      );
      return;
    }

    state = state.copyWith(needsSteamGuard: false);

    await publishBatch(
      items: _cachedItems!,
      username: _cachedUsername!,
      password: _cachedPassword!,
      steamGuardCode: code,
    );
  }

  /// Cancel the batch publish
  void cancel() {
    if (state.isPublishing && !state.isCancelled) {
      state = state.copyWith(isCancelled: true);
      final service = ref.read(workshopPublishServiceProvider);
      service.cancel();
    }
  }

  /// Reset state (only call when the widget is still mounted)
  void reset() {
    _cachedItems = null;
    _cachedUsername = null;
    _cachedPassword = null;
    state = const BatchWorkshopPublishState();
  }

  /// Clean up without setting state — safe to call from widget dispose()
  void silentCleanup() {
    _silentlyCleaned = true;
    _cachedItems = null;
    _cachedUsername = null;
    _cachedPassword = null;
    final service = ref.read(workshopPublishServiceProvider);
    service.cancel();
  }
}

/// Provider for batch workshop publish
final batchWorkshopPublishProvider = NotifierProvider<
    BatchWorkshopPublishNotifier, BatchWorkshopPublishState>(
  BatchWorkshopPublishNotifier.new,
);
