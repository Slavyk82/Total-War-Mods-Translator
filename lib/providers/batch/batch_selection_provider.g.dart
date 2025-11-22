// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_selection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for managing selected translation units

@ProviderFor(BatchSelection)
const batchSelectionProvider = BatchSelectionProvider._();

/// Provider for managing selected translation units
final class BatchSelectionProvider
    extends $NotifierProvider<BatchSelection, BatchSelectionState> {
  /// Provider for managing selected translation units
  const BatchSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchSelectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchSelectionHash();

  @$internal
  @override
  BatchSelection create() => BatchSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BatchSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BatchSelectionState>(value),
    );
  }
}

String _$batchSelectionHash() => r'0d32c60a5eb542577c6abd4ecefb6a03932d0ca5';

/// Provider for managing selected translation units

abstract class _$BatchSelection extends $Notifier<BatchSelectionState> {
  BatchSelectionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<BatchSelectionState, BatchSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BatchSelectionState, BatchSelectionState>,
              BatchSelectionState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
