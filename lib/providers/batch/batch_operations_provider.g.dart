// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_operations_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for managing batch operation state

@ProviderFor(BatchOperation)
const batchOperationProvider = BatchOperationProvider._();

/// Provider for managing batch operation state
final class BatchOperationProvider
    extends $NotifierProvider<BatchOperation, BatchOperationState> {
  /// Provider for managing batch operation state
  const BatchOperationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchOperationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchOperationHash();

  @$internal
  @override
  BatchOperation create() => BatchOperation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BatchOperationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BatchOperationState>(value),
    );
  }
}

String _$batchOperationHash() => r'091fea960f9688d588dce326b2c8ebb1ba8a8861';

/// Provider for managing batch operation state

abstract class _$BatchOperation extends $Notifier<BatchOperationState> {
  BatchOperationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<BatchOperationState, BatchOperationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BatchOperationState, BatchOperationState>,
              BatchOperationState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for batch translate dialog state

@ProviderFor(BatchTranslateConfig)
const batchTranslateConfigProvider = BatchTranslateConfigProvider._();

/// Provider for batch translate dialog state
final class BatchTranslateConfigProvider
    extends $NotifierProvider<BatchTranslateConfig, BatchTranslateState> {
  /// Provider for batch translate dialog state
  const BatchTranslateConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchTranslateConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchTranslateConfigHash();

  @$internal
  @override
  BatchTranslateConfig create() => BatchTranslateConfig();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BatchTranslateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BatchTranslateState>(value),
    );
  }
}

String _$batchTranslateConfigHash() =>
    r'8fb614740bc5265f26b453339396188ce7ccc7d1';

/// Provider for batch translate dialog state

abstract class _$BatchTranslateConfig extends $Notifier<BatchTranslateState> {
  BatchTranslateState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<BatchTranslateState, BatchTranslateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BatchTranslateState, BatchTranslateState>,
              BatchTranslateState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for batch validation results

@ProviderFor(BatchValidationResults)
const batchValidationResultsProvider = BatchValidationResultsProvider._();

/// Provider for batch validation results
final class BatchValidationResultsProvider
    extends $NotifierProvider<BatchValidationResults, BatchValidationState> {
  /// Provider for batch validation results
  const BatchValidationResultsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchValidationResultsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchValidationResultsHash();

  @$internal
  @override
  BatchValidationResults create() => BatchValidationResults();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BatchValidationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BatchValidationState>(value),
    );
  }
}

String _$batchValidationResultsHash() =>
    r'fda3c65b8d93d34ee882f2a4dbda098d212e480a';

/// Provider for batch validation results

abstract class _$BatchValidationResults
    extends $Notifier<BatchValidationState> {
  BatchValidationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<BatchValidationState, BatchValidationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BatchValidationState, BatchValidationState>,
              BatchValidationState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
