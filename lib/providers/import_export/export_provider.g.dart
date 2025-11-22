// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Current export settings

@ProviderFor(ExportSettingsState)
const exportSettingsStateProvider = ExportSettingsStateProvider._();

/// Current export settings
final class ExportSettingsStateProvider
    extends
        $NotifierProvider<ExportSettingsState, export_models.ExportSettings> {
  /// Current export settings
  const ExportSettingsStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportSettingsStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportSettingsStateHash();

  @$internal
  @override
  ExportSettingsState create() => ExportSettingsState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(export_models.ExportSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<export_models.ExportSettings>(value),
    );
  }
}

String _$exportSettingsStateHash() =>
    r'41de9c6aee2037ca669cc2c850e48e395938046a';

/// Current export settings

abstract class _$ExportSettingsState
    extends $Notifier<export_models.ExportSettings> {
  export_models.ExportSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<export_models.ExportSettings, export_models.ExportSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                export_models.ExportSettings,
                export_models.ExportSettings
              >,
              export_models.ExportSettings,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Export preview data

@ProviderFor(ExportPreviewData)
const exportPreviewDataProvider = ExportPreviewDataProvider._();

/// Export preview data
final class ExportPreviewDataProvider
    extends $NotifierProvider<ExportPreviewData, ExportPreview?> {
  /// Export preview data
  const ExportPreviewDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportPreviewDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportPreviewDataHash();

  @$internal
  @override
  ExportPreviewData create() => ExportPreviewData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExportPreview? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExportPreview?>(value),
    );
  }
}

String _$exportPreviewDataHash() => r'0863140c2af8b109798b9082d130fda0d16af0a1';

/// Export preview data

abstract class _$ExportPreviewData extends $Notifier<ExportPreview?> {
  ExportPreview? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ExportPreview?, ExportPreview?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ExportPreview?, ExportPreview?>,
              ExportPreview?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Export progress state

@ProviderFor(ExportProgress)
const exportProgressProvider = ExportProgressProvider._();

/// Export progress state
final class ExportProgressProvider
    extends $NotifierProvider<ExportProgress, ExportProgressState> {
  /// Export progress state
  const ExportProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportProgressHash();

  @$internal
  @override
  ExportProgress create() => ExportProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExportProgressState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExportProgressState>(value),
    );
  }
}

String _$exportProgressHash() => r'1992819092c30a4f87707ac793769fe99cebe5a6';

/// Export progress state

abstract class _$ExportProgress extends $Notifier<ExportProgressState> {
  ExportProgressState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ExportProgressState, ExportProgressState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ExportProgressState, ExportProgressState>,
              ExportProgressState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Export results

@ProviderFor(ExportResultData)
const exportResultDataProvider = ExportResultDataProvider._();

/// Export results
final class ExportResultDataProvider
    extends $NotifierProvider<ExportResultData, ExportResult?> {
  /// Export results
  const ExportResultDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportResultDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportResultDataHash();

  @$internal
  @override
  ExportResultData create() => ExportResultData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExportResult? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExportResult?>(value),
    );
  }
}

String _$exportResultDataHash() => r'e98d418ffbe8430685dd3efb0da2bd2b19d1648e';

/// Export results

abstract class _$ExportResultData extends $Notifier<ExportResult?> {
  ExportResult? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ExportResult?, ExportResult?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ExportResult?, ExportResult?>,
              ExportResult?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
