import 'dart:async';

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
  StreamSubscription<double>? _progressSub;
  StreamSubscription<String>? _outputSub;

  // Cached for Steam Guard retry
  List<BatchPublishItemInfo>? _cachedItems;
  String? _cachedUsername;
  String? _cachedPassword;
  int _currentItemIndex = 0;

  @override
  BatchWorkshopPublishState build() => const BatchWorkshopPublishState();

  /// Start batch publish
  Future<void> publishBatch({
    required List<BatchPublishItemInfo> items,
    required String username,
    required String password,
    String? steamGuardCode,
    int startFromIndex = 0,
  }) async {
    if (state.isPublishing) return;

    final logging = ServiceLocator.get<LoggingService>();
    logging.info('Starting batch workshop publish', {
      'itemCount': items.length,
      'startFromIndex': startFromIndex,
    });

    // Cache for potential Steam Guard retry
    _cachedItems = items;
    _cachedUsername = username;
    _cachedPassword = password;

    // Initialize statuses (keep existing for items already completed)
    final statuses = Map<String, BatchPublishStatus>.from(state.itemStatuses);
    for (var i = startFromIndex; i < items.length; i++) {
      statuses[items[i].name] = BatchPublishStatus.pending;
    }

    state = state.copyWith(
      isPublishing: true,
      isCancelled: false,
      needsSteamGuard: false,
      totalItems: items.length,
      completedItems: startFromIndex,
      itemStatuses: statuses,
      results: startFromIndex > 0 ? state.results : const [],
    );

    final service = ServiceLocator.get<IWorkshopPublishService>();
    final results = List<BatchPublishItemResult>.from(state.results);

    for (var i = startFromIndex; i < items.length; i++) {
      _currentItemIndex = i;

      // Check for cancellation
      if (state.isCancelled) {
        logging.info('Batch publish cancelled', {
          'completedItems': i,
          'totalItems': items.length,
        });

        final updatedStatuses =
            Map<String, BatchPublishStatus>.from(state.itemStatuses);
        for (var j = i; j < items.length; j++) {
          updatedStatuses[items[j].name] = BatchPublishStatus.cancelled;
        }

        state = state.copyWith(
          isPublishing: false,
          itemStatuses: updatedStatuses,
          clearCurrentItem: true,
        );
        return;
      }

      // Delay between items to avoid Steam rate-limiting
      // ("Timeout uploading manifest" error / exit code 9)
      if (i > startFromIndex) {
        state = state.copyWith(
          currentItemName: 'Waiting before next upload...',
        );
        await Future<void>.delayed(const Duration(seconds: 15));
        if (state.isCancelled) continue;
      }

      final item = items[i];

      // Update state for current item
      final updatedStatuses =
          Map<String, BatchPublishStatus>.from(state.itemStatuses);
      updatedStatuses[item.name] = BatchPublishStatus.inProgress;

      state = state.copyWith(
        currentItemName: item.name,
        currentItemProgress: 0.0,
        itemStatuses: updatedStatuses,
      );

      // Listen to progress
      _progressSub?.cancel();
      _progressSub = service.progressStream.listen((progress) {
        state = state.copyWith(currentItemProgress: progress);
      });

      // Listen to output (we don't show terminal output in batch mode)
      _outputSub?.cancel();
      _outputSub = service.outputStream.listen((_) {});

      try {
        final result = await service.publish(
          params: item.params,
          username: username,
          password: password,
          steamGuardCode: steamGuardCode,
        );

        _progressSub?.cancel();
        _outputSub?.cancel();

        // Only use steam guard code for the first item
        steamGuardCode = null;

        var shouldBreak = false;
        result.when(
          ok: (publishResult) async {
            updatedStatuses[item.name] = BatchPublishStatus.success;
            results.add(BatchPublishItemResult(
              name: item.name,
              success: true,
              workshopId: publishResult.workshopId,
            ));

            // Save workshop ID to project or compilation
            if (item.projectId != null) {
              try {
                final projectRepo = ServiceLocator.get<ProjectRepository>();
                final projectResult =
                    await projectRepo.getById(item.projectId!);
                if (projectResult.isOk) {
                  final updated = projectResult.value.copyWith(
                    publishedSteamId: publishResult.workshopId,
                    publishedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  );
                  await projectRepo.update(updated);
                }
              } catch (e) {
                logging.warning(
                    'Failed to save Workshop ID for ${item.name}: $e');
              }
            } else if (item.compilationId != null) {
              try {
                final compilationRepo =
                    ServiceLocator.get<CompilationRepository>();
                await compilationRepo.updateAfterPublish(
                  item.compilationId!,
                  publishResult.workshopId,
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
                );
              } catch (e) {
                logging.warning(
                    'Failed to save Workshop ID for compilation ${item.name}: $e');
              }
            }

            logging.info('Item published successfully', {
              'name': item.name,
              'workshopId': publishResult.workshopId,
            });

          },
          err: (error) {
            if (error is SteamGuardRequiredException) {
              // Signal that Steam Guard is needed, pause batch
              state = state.copyWith(
                isPublishing: false,
                needsSteamGuard: true,
                itemStatuses: updatedStatuses,
              );
              shouldBreak = true;
              return;
            }

            updatedStatuses[item.name] = BatchPublishStatus.failed;
            results.add(BatchPublishItemResult(
              name: item.name,
              success: false,
              errorMessage: error.message,
            ));
            logging.error('Item publish failed: ${item.name} - ${error.message}');
          },
        );

        if (shouldBreak) return;

        // If item failed because it was deleted from Steam, retry as new
        if (result.isErr && result.error is WorkshopItemNotFoundException) {
          logging.info(
            'Item ${item.name} not found on Steam — retrying as new item',
          );

          _progressSub?.cancel();
          _progressSub = service.progressStream.listen((progress) {
            state = state.copyWith(currentItemProgress: progress);
          });
          _outputSub?.cancel();
          _outputSub = service.outputStream.listen((_) {});

          // Remove the failed result we just added
          results.removeLast();
          updatedStatuses[item.name] = BatchPublishStatus.inProgress;
          state = state.copyWith(
            currentItemProgress: 0.0,
            itemStatuses: updatedStatuses,
          );

          final retryResult = await service.publish(
            params: item.params.copyWith(publishedFileId: '0'),
            username: username,
            password: password,
          );

          _progressSub?.cancel();
          _outputSub?.cancel();

          retryResult.when(
            ok: (publishResult) async {
              updatedStatuses[item.name] = BatchPublishStatus.success;
              results.add(BatchPublishItemResult(
                name: item.name,
                success: true,
                workshopId: publishResult.workshopId,
              ));

              if (item.projectId != null) {
                try {
                  final projectRepo =
                      ServiceLocator.get<ProjectRepository>();
                  final projectResult =
                      await projectRepo.getById(item.projectId!);
                  if (projectResult.isOk) {
                    final updated = projectResult.value.copyWith(
                      publishedSteamId: publishResult.workshopId,
                      publishedAt:
                          DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    );
                    await projectRepo.update(updated);
                  }
                } catch (e) {
                  logging.warning(
                      'Failed to save Workshop ID for ${item.name}: $e');
                }
              } else if (item.compilationId != null) {
                try {
                  final compilationRepo =
                      ServiceLocator.get<CompilationRepository>();
                  await compilationRepo.updateAfterPublish(
                    item.compilationId!,
                    publishResult.workshopId,
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  );
                } catch (e) {
                  logging.warning(
                      'Failed to save Workshop ID for compilation ${item.name}: $e');
                }
              }

              logging.info('Item re-published as new successfully', {
                'name': item.name,
                'workshopId': publishResult.workshopId,
              });

            },
            err: (retryError) {
              updatedStatuses[item.name] = BatchPublishStatus.failed;
              results.add(BatchPublishItemResult(
                name: item.name,
                success: false,
                errorMessage: retryError.message,
              ));
              logging.error(
                  'Item retry as new failed: ${item.name} - ${retryError.message}');
            },
          );
        }
      } catch (e, stack) {
        _progressSub?.cancel();
        _outputSub?.cancel();

        updatedStatuses[item.name] = BatchPublishStatus.failed;
        results.add(BatchPublishItemResult(
          name: item.name,
          success: false,
          errorMessage: e.toString(),
        ));
        logging.error('Item publish exception: ${item.name}', e, stack);
      }

      // Update completed count
      state = state.copyWith(
        completedItems: i + 1,
        itemStatuses: updatedStatuses,
        results: List.from(results),
      );
    }

    // Batch complete
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

  /// Retry batch from current item with Steam Guard code
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
      startFromIndex: _currentItemIndex,
    );
  }

  /// Cancel the batch publish
  void cancel() {
    if (state.isPublishing && !state.isCancelled) {
      state = state.copyWith(isCancelled: true);
    }
    _progressSub?.cancel();
    _outputSub?.cancel();
  }

  /// Reset state (only call when the widget is still mounted)
  void reset() {
    _progressSub?.cancel();
    _outputSub?.cancel();
    _cachedItems = null;
    _cachedUsername = null;
    _cachedPassword = null;
    _currentItemIndex = 0;
    state = const BatchWorkshopPublishState();
  }

  /// Clean up without setting state — safe to call from widget dispose()
  void silentCleanup() {
    _progressSub?.cancel();
    _progressSub = null;
    _outputSub?.cancel();
    _outputSub = null;
    _cachedItems = null;
    _cachedUsername = null;
    _cachedPassword = null;
    _currentItemIndex = 0;
    final service = ServiceLocator.get<IWorkshopPublishService>();
    service.cancel();
  }
}

/// Provider for batch workshop publish
final batchWorkshopPublishProvider = NotifierProvider<
    BatchWorkshopPublishNotifier, BatchWorkshopPublishState>(
  BatchWorkshopPublishNotifier.new,
);
