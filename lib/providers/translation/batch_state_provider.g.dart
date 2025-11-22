// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider that maintains state for a specific batch by listening to events

@ProviderFor(BatchStateNotifier)
const batchStateProvider = BatchStateNotifierFamily._();

/// Provider that maintains state for a specific batch by listening to events
final class BatchStateNotifierProvider
    extends $NotifierProvider<BatchStateNotifier, BatchState> {
  /// Provider that maintains state for a specific batch by listening to events
  const BatchStateNotifierProvider._({
    required BatchStateNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'batchStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$batchStateNotifierHash();

  @override
  String toString() {
    return r'batchStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BatchStateNotifier create() => BatchStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BatchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BatchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BatchStateNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$batchStateNotifierHash() =>
    r'e00f8abedc9ac903009c600ed8fc800ef32b326a';

/// Provider that maintains state for a specific batch by listening to events

final class BatchStateNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          BatchStateNotifier,
          BatchState,
          BatchState,
          BatchState,
          String
        > {
  const BatchStateNotifierFamily._()
    : super(
        retry: null,
        name: r'batchStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider that maintains state for a specific batch by listening to events

  BatchStateNotifierProvider call(String batchId) =>
      BatchStateNotifierProvider._(argument: batchId, from: this);

  @override
  String toString() => r'batchStateProvider';
}

/// Provider that maintains state for a specific batch by listening to events

abstract class _$BatchStateNotifier extends $Notifier<BatchState> {
  late final _$args = ref.$arg as String;
  String get batchId => _$args;

  BatchState build(String batchId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<BatchState, BatchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BatchState, BatchState>,
              BatchState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
