import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'batch_workshop_publish_notifier.dart';
import 'steam_publish_providers.dart';

/// Staging notifier for single publish screen.
class _SinglePublishStagingNotifier extends Notifier<PublishableItem?> {
  @override
  PublishableItem? build() => null;

  void set(PublishableItem? item) => state = item;
}

/// Staging notifier for batch publish screen.
class _BatchPublishStagingNotifier extends Notifier<BatchPublishStagingData?> {
  @override
  BatchPublishStagingData? build() => null;

  void set(BatchPublishStagingData? data) => state = data;
}

/// Set before navigating to the publish screen, read in initState.
final singlePublishStagingProvider =
    NotifierProvider<_SinglePublishStagingNotifier, PublishableItem?>(
  _SinglePublishStagingNotifier.new,
);

/// Set before navigating to the batch publish screen, read in initState.
final batchPublishStagingProvider =
    NotifierProvider<_BatchPublishStagingNotifier, BatchPublishStagingData?>(
  _BatchPublishStagingNotifier.new,
);

/// Data needed to start a batch publish.
class BatchPublishStagingData {
  final List<BatchPublishItemInfo> items;
  final String username;
  final String password;
  final String? steamGuardCode;

  const BatchPublishStagingData({
    required this.items,
    required this.username,
    required this.password,
    this.steamGuardCode,
  });
}
