// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_batches_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks all active batches across the application

@ProviderFor(ActiveBatches)
const activeBatchesProvider = ActiveBatchesProvider._();

/// Tracks all active batches across the application
final class ActiveBatchesProvider
    extends $NotifierProvider<ActiveBatches, Map<String, BatchState>> {
  /// Tracks all active batches across the application
  const ActiveBatchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeBatchesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeBatchesHash();

  @$internal
  @override
  ActiveBatches create() => ActiveBatches();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, BatchState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, BatchState>>(value),
    );
  }
}

String _$activeBatchesHash() => r'2b62edf141913c78f3e382b7008747f771b71d36';

/// Tracks all active batches across the application

abstract class _$ActiveBatches extends $Notifier<Map<String, BatchState>> {
  Map<String, BatchState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<Map<String, BatchState>, Map<String, BatchState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, BatchState>, Map<String, BatchState>>,
              Map<String, BatchState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
