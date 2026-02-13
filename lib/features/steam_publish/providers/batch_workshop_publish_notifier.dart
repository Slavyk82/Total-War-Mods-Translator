import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/compilation_repository.dart';
import '../../../repositories/project_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';
import '../../../services/steam/i_workshop_publish_service.dart';
import '../../../services/steam/models/steam_exceptions.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import 'steam_publish_providers.dart';

/// Info for a single item in the batch publish
class BatchPublishItemInfo {
  final String name;
  final WorkshopPublishParams params;
  final String? projectId;
  final String? compilationId;

  const BatchPublishItemInfo({
    required this.name,
    required this.params,
    this.projectId,
    this.compilationId,
  });
}

/// Result of a single item publish
class BatchPublishItemResult {
  final String name;
  final bool success;
  final String? workshopId;
  final String? errorMessage;

  const BatchPublishItemResult({
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
  final Map<String, BatchPublishStatus> itemStatuses;
  final List<BatchPublishItemResult> results;
  final bool needsSteamGuard;

  const BatchWorkshopPublishState({
    this.isPublishing = false,
    this.isCancelled = false,
    this.totalItems = 0,
    this.completedItems = 0,
    this.currentItemProgress = 0.0,
    this.currentItemName,
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
    Map<String, BatchPublishStatus>? itemStatuses,
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

    final logging = ServiceLocator.get<LoggingService>();
    logging.info('Starting batch workshop publish', {
      'itemCount': items.length,
    });

    // Cache for potential Steam Guard retry
    _cachedItems = items;
    _cachedUsername = username;
    _cachedPassword = password;

    // Initialize statuses
    final statuses = <String, BatchPublishStatus>{};
    for (final item in items) {
      statuses[item.name] = BatchPublishStatus.pending;
    }

    state = state.copyWith(
      isPublishing: true,
      isCancelled: false,
      needsSteamGuard: false,
      totalItems: items.length,
      completedItems: 0,
      itemStatuses: statuses,
      results: const [],
    );

    final service = ServiceLocator.get<IWorkshopPublishService>();
    final results = <BatchPublishItemResult>[];
    final failedAsNotFound = <int>[];

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
              Map<String, BatchPublishStatus>.from(state.itemStatuses);
          updatedStatuses[name] = BatchPublishStatus.inProgress;
          state = state.copyWith(
            currentItemName: name,
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
              Map<String, BatchPublishStatus>.from(state.itemStatuses);

          result.when(
            ok: (publishResult) {
              updatedStatuses[item.name] = BatchPublishStatus.success;
              results.add(BatchPublishItemResult(
                name: item.name,
                success: true,
                workshopId: publishResult.workshopId,
              ));
              _saveWorkshopId(item, publishResult.workshopId);
              logging.info('Item published successfully', {
                'name': item.name,
                'workshopId': publishResult.workshopId,
              });
            },
            err: (error) {
              if (error is WorkshopItemNotFoundException) {
                failedAsNotFound.add(index);
              }
              updatedStatuses[item.name] = BatchPublishStatus.failed;
              results.add(BatchPublishItemResult(
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

    // --- Retry items that failed because their workshop ID was deleted ---
    if (failedAsNotFound.isNotEmpty && !_silentlyCleaned) {
      logging.info('Retrying ${failedAsNotFound.length} items as new');

      final retryItems = failedAsNotFound.map((idx) {
        final item = items[idx];
        return (
          name: item.name,
          params: item.params.copyWith(publishedFileId: '0'),
        );
      }).toList();

      // Remove the failed results for these items so we can replace them
      final retryNames = failedAsNotFound.map((i) => items[i].name).toSet();
      results.removeWhere((r) => retryNames.contains(r.name));

      // Reset statuses for retry items
      final retryStatuses =
          Map<String, BatchPublishStatus>.from(state.itemStatuses);
      for (final name in retryNames) {
        retryStatuses[name] = BatchPublishStatus.pending;
      }
      state = state.copyWith(
        completedItems: results.length,
        itemStatuses: retryStatuses,
        results: List.from(results),
      );

      try {
        await service.publishBatch(
          items: retryItems,
          username: username,
          password: password,
          // No steamGuardCode needed — credentials cached from first batch
          onItemStart: (index, name) {
            if (_silentlyCleaned) return;
            final updatedStatuses =
                Map<String, BatchPublishStatus>.from(state.itemStatuses);
            updatedStatuses[name] = BatchPublishStatus.inProgress;
            state = state.copyWith(
              currentItemName: name,
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
            final originalIdx = failedAsNotFound[index];
            final item = items[originalIdx];
            final updatedStatuses =
                Map<String, BatchPublishStatus>.from(state.itemStatuses);

            result.when(
              ok: (publishResult) {
                updatedStatuses[item.name] = BatchPublishStatus.success;
                results.add(BatchPublishItemResult(
                  name: item.name,
                  success: true,
                  workshopId: publishResult.workshopId,
                ));
                _saveWorkshopId(item, publishResult.workshopId);
                logging.info('Item re-published as new successfully', {
                  'name': item.name,
                  'workshopId': publishResult.workshopId,
                });
              },
              err: (error) {
                updatedStatuses[item.name] = BatchPublishStatus.failed;
                results.add(BatchPublishItemResult(
                  name: item.name,
                  success: false,
                  errorMessage: error.message,
                ));
                logging.error(
                    'Item retry as new failed: ${item.name} - ${error.message}');
              },
            );

            state = state.copyWith(
              completedItems: results.length,
              itemStatuses: updatedStatuses,
              results: List.from(results),
            );
          },
        );
      } catch (e, stack) {
        logging.error('Batch retry exception', e, stack);
      }
    }

    // Batch complete — skip if widget was disposed during publish
    if (_silentlyCleaned) return;

    // Mark remaining uncompleted items as cancelled if batch was cancelled
    if (state.isCancelled) {
      final updatedStatuses =
          Map<String, BatchPublishStatus>.from(state.itemStatuses);
      for (final item in items) {
        if (updatedStatuses[item.name] == BatchPublishStatus.pending ||
            updatedStatuses[item.name] == BatchPublishStatus.inProgress) {
          updatedStatuses[item.name] = BatchPublishStatus.cancelled;
        }
      }
      state = state.copyWith(itemStatuses: updatedStatuses);
    }

    state = state.copyWith(
      isPublishing: false,
      clearCurrentItem: true,
    );

    // Refresh exports list
    ref.invalidate(publishableItemsProvider);

    logging.info('Batch publish complete', {
      'totalItems': items.length,
      'successCount': state.successCount,
      'failedCount': state.failedCount,
    });
  }

  /// Save workshop ID to project or compilation DB record
  Future<void> _saveWorkshopId(
    BatchPublishItemInfo item,
    String workshopId,
  ) async {
    final logging = ServiceLocator.get<LoggingService>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (item.projectId != null) {
      try {
        final projectRepo = ServiceLocator.get<ProjectRepository>();
        final projectResult = await projectRepo.getById(item.projectId!);
        if (projectResult.isOk) {
          final updated = projectResult.value.copyWith(
            publishedSteamId: workshopId,
            publishedAt: now,
          );
          await projectRepo.update(updated);
        }
      } catch (e) {
        logging.warning('Failed to save Workshop ID for ${item.name}: $e');
      }
    } else if (item.compilationId != null) {
      try {
        final compilationRepo =
            ServiceLocator.get<CompilationRepository>();
        await compilationRepo.updateAfterPublish(
          item.compilationId!,
          workshopId,
          now,
        );
      } catch (e) {
        logging.warning(
            'Failed to save Workshop ID for compilation ${item.name}: $e');
      }
    }
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
      final service = ServiceLocator.get<IWorkshopPublishService>();
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
    final service = ServiceLocator.get<IWorkshopPublishService>();
    service.cancel();
  }
}

/// Provider for batch workshop publish
final batchWorkshopPublishProvider = NotifierProvider<
    BatchWorkshopPublishNotifier, BatchWorkshopPublishState>(
  BatchWorkshopPublishNotifier.new,
);
