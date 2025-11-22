// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Current import settings

@ProviderFor(ImportSettingsState)
const importSettingsStateProvider = ImportSettingsStateProvider._();

/// Current import settings
final class ImportSettingsStateProvider
    extends
        $NotifierProvider<ImportSettingsState, import_models.ImportSettings> {
  /// Current import settings
  const ImportSettingsStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importSettingsStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importSettingsStateHash();

  @$internal
  @override
  ImportSettingsState create() => ImportSettingsState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(import_models.ImportSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<import_models.ImportSettings>(value),
    );
  }
}

String _$importSettingsStateHash() =>
    r'54a2712125976bdf641e716a823acf8f726438cd';

/// Current import settings

abstract class _$ImportSettingsState
    extends $Notifier<import_models.ImportSettings> {
  import_models.ImportSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<import_models.ImportSettings, import_models.ImportSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                import_models.ImportSettings,
                import_models.ImportSettings
              >,
              import_models.ImportSettings,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import preview data

@ProviderFor(ImportPreviewData)
const importPreviewDataProvider = ImportPreviewDataProvider._();

/// Import preview data
final class ImportPreviewDataProvider
    extends $NotifierProvider<ImportPreviewData, ImportPreview?> {
  /// Import preview data
  const ImportPreviewDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importPreviewDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importPreviewDataHash();

  @$internal
  @override
  ImportPreviewData create() => ImportPreviewData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportPreview? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportPreview?>(value),
    );
  }
}

String _$importPreviewDataHash() => r'f4c9f2e43b5e8ceb3ff3004830412d0d28bd8198';

/// Import preview data

abstract class _$ImportPreviewData extends $Notifier<ImportPreview?> {
  ImportPreview? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ImportPreview?, ImportPreview?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportPreview?, ImportPreview?>,
              ImportPreview?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import conflicts

@ProviderFor(ImportConflictsData)
const importConflictsDataProvider = ImportConflictsDataProvider._();

/// Import conflicts
final class ImportConflictsDataProvider
    extends $NotifierProvider<ImportConflictsData, List<ImportConflict>> {
  /// Import conflicts
  const ImportConflictsDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importConflictsDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importConflictsDataHash();

  @$internal
  @override
  ImportConflictsData create() => ImportConflictsData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ImportConflict> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ImportConflict>>(value),
    );
  }
}

String _$importConflictsDataHash() =>
    r'f85d36b66c50eda8b3bab85d0dfc0ce605d6ea90';

/// Import conflicts

abstract class _$ImportConflictsData extends $Notifier<List<ImportConflict>> {
  List<ImportConflict> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<ImportConflict>, List<ImportConflict>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<ImportConflict>, List<ImportConflict>>,
              List<ImportConflict>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Conflict resolutions

@ProviderFor(ConflictResolutionsData)
const conflictResolutionsDataProvider = ConflictResolutionsDataProvider._();

/// Conflict resolutions
final class ConflictResolutionsDataProvider
    extends $NotifierProvider<ConflictResolutionsData, ConflictResolutions> {
  /// Conflict resolutions
  const ConflictResolutionsDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conflictResolutionsDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conflictResolutionsDataHash();

  @$internal
  @override
  ConflictResolutionsData create() => ConflictResolutionsData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConflictResolutions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConflictResolutions>(value),
    );
  }
}

String _$conflictResolutionsDataHash() =>
    r'b265a6a3ce2977e15749fa65322da206c2c5dc08';

/// Conflict resolutions

abstract class _$ConflictResolutionsData
    extends $Notifier<ConflictResolutions> {
  ConflictResolutions build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ConflictResolutions, ConflictResolutions>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConflictResolutions, ConflictResolutions>,
              ConflictResolutions,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import progress state

@ProviderFor(ImportProgress)
const importProgressProvider = ImportProgressProvider._();

/// Import progress state
final class ImportProgressProvider
    extends $NotifierProvider<ImportProgress, ImportProgressState> {
  /// Import progress state
  const ImportProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importProgressHash();

  @$internal
  @override
  ImportProgress create() => ImportProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportProgressState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportProgressState>(value),
    );
  }
}

String _$importProgressHash() => r'be6df490c70f4caeee12805e2d7825494f1335cd';

/// Import progress state

abstract class _$ImportProgress extends $Notifier<ImportProgressState> {
  ImportProgressState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ImportProgressState, ImportProgressState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportProgressState, ImportProgressState>,
              ImportProgressState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import results

@ProviderFor(ImportResultData)
const importResultDataProvider = ImportResultDataProvider._();

/// Import results
final class ImportResultDataProvider
    extends $NotifierProvider<ImportResultData, ImportResult?> {
  /// Import results
  const ImportResultDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importResultDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importResultDataHash();

  @$internal
  @override
  ImportResultData create() => ImportResultData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportResult? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportResult?>(value),
    );
  }
}

String _$importResultDataHash() => r'bbc79d9595a035a9a6696b1649c68c8b20925c79';

/// Import results

abstract class _$ImportResultData extends $Notifier<ImportResult?> {
  ImportResult? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ImportResult?, ImportResult?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportResult?, ImportResult?>,
              ImportResult?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import validation result

@ProviderFor(importValidation)
const importValidationProvider = ImportValidationFamily._();

/// Import validation result

final class ImportValidationProvider
    extends
        $FunctionalProvider<
          AsyncValue<ImportValidationResult>,
          ImportValidationResult,
          FutureOr<ImportValidationResult>
        >
    with
        $FutureModifier<ImportValidationResult>,
        $FutureProvider<ImportValidationResult> {
  /// Import validation result
  const ImportValidationProvider._({
    required ImportValidationFamily super.from,
    required ({ImportPreview preview, import_models.ImportSettings settings})
    super.argument,
  }) : super(
         retry: null,
         name: r'importValidationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$importValidationHash();

  @override
  String toString() {
    return r'importValidationProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<ImportValidationResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ImportValidationResult> create(Ref ref) {
    final argument =
        this.argument
            as ({ImportPreview preview, import_models.ImportSettings settings});
    return importValidation(
      ref,
      preview: argument.preview,
      settings: argument.settings,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ImportValidationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$importValidationHash() => r'51a88a90fa45b3d9578771b30b9f3a355629b354';

/// Import validation result

final class ImportValidationFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<ImportValidationResult>,
          ({ImportPreview preview, import_models.ImportSettings settings})
        > {
  const ImportValidationFamily._()
    : super(
        retry: null,
        name: r'importValidationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Import validation result

  ImportValidationProvider call({
    required ImportPreview preview,
    required import_models.ImportSettings settings,
  }) => ImportValidationProvider._(
    argument: (preview: preview, settings: settings),
    from: this,
  );

  @override
  String toString() => r'importValidationProvider';
}
