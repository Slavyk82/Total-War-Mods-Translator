// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glossary_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// All glossaries (global + project-specific)

@ProviderFor(glossaries)
const glossariesProvider = GlossariesFamily._();

/// All glossaries (global + project-specific)

final class GlossariesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Glossary>>,
          List<Glossary>,
          FutureOr<List<Glossary>>
        >
    with $FutureModifier<List<Glossary>>, $FutureProvider<List<Glossary>> {
  /// All glossaries (global + project-specific)
  const GlossariesProvider._({
    required GlossariesFamily super.from,
    required ({String? projectId, bool includeGlobal}) super.argument,
  }) : super(
         retry: null,
         name: r'glossariesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$glossariesHash();

  @override
  String toString() {
    return r'glossariesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<Glossary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Glossary>> create(Ref ref) {
    final argument = this.argument as ({String? projectId, bool includeGlobal});
    return glossaries(
      ref,
      projectId: argument.projectId,
      includeGlobal: argument.includeGlobal,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GlossariesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$glossariesHash() => r'7bc333dd8db66a7823a7507cffbeedbce1c8988f';

/// All glossaries (global + project-specific)

final class GlossariesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<Glossary>>,
          ({String? projectId, bool includeGlobal})
        > {
  const GlossariesFamily._()
    : super(
        retry: null,
        name: r'glossariesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// All glossaries (global + project-specific)

  GlossariesProvider call({String? projectId, bool includeGlobal = true}) =>
      GlossariesProvider._(
        argument: (projectId: projectId, includeGlobal: includeGlobal),
        from: this,
      );

  @override
  String toString() => r'glossariesProvider';
}

/// Selected glossary

@ProviderFor(SelectedGlossary)
const selectedGlossaryProvider = SelectedGlossaryProvider._();

/// Selected glossary
final class SelectedGlossaryProvider
    extends $NotifierProvider<SelectedGlossary, Glossary?> {
  /// Selected glossary
  const SelectedGlossaryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGlossaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGlossaryHash();

  @$internal
  @override
  SelectedGlossary create() => SelectedGlossary();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Glossary? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Glossary?>(value),
    );
  }
}

String _$selectedGlossaryHash() => r'6795b01fa53f371512a1102bdbdd2e6667068cb2';

/// Selected glossary

abstract class _$SelectedGlossary extends $Notifier<Glossary?> {
  Glossary? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Glossary?, Glossary?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Glossary?, Glossary?>,
              Glossary?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Glossary entries with filtering and pagination

@ProviderFor(glossaryEntries)
const glossaryEntriesProvider = GlossaryEntriesFamily._();

/// Glossary entries with filtering and pagination

final class GlossaryEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GlossaryEntry>>,
          List<GlossaryEntry>,
          FutureOr<List<GlossaryEntry>>
        >
    with
        $FutureModifier<List<GlossaryEntry>>,
        $FutureProvider<List<GlossaryEntry>> {
  /// Glossary entries with filtering and pagination
  const GlossaryEntriesProvider._({
    required GlossaryEntriesFamily super.from,
    required ({String glossaryId, String? targetLanguageCode}) super.argument,
  }) : super(
         retry: null,
         name: r'glossaryEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$glossaryEntriesHash();

  @override
  String toString() {
    return r'glossaryEntriesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<GlossaryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GlossaryEntry>> create(Ref ref) {
    final argument =
        this.argument as ({String glossaryId, String? targetLanguageCode});
    return glossaryEntries(
      ref,
      glossaryId: argument.glossaryId,
      targetLanguageCode: argument.targetLanguageCode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GlossaryEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$glossaryEntriesHash() => r'3c7ef77ff87bccfd5451b23edc12be9031f88201';

/// Glossary entries with filtering and pagination

final class GlossaryEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<GlossaryEntry>>,
          ({String glossaryId, String? targetLanguageCode})
        > {
  const GlossaryEntriesFamily._()
    : super(
        retry: null,
        name: r'glossaryEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Glossary entries with filtering and pagination

  GlossaryEntriesProvider call({
    required String glossaryId,
    String? targetLanguageCode,
  }) => GlossaryEntriesProvider._(
    argument: (glossaryId: glossaryId, targetLanguageCode: targetLanguageCode),
    from: this,
  );

  @override
  String toString() => r'glossaryEntriesProvider';
}

/// Search glossary entries

@ProviderFor(glossarySearchResults)
const glossarySearchResultsProvider = GlossarySearchResultsFamily._();

/// Search glossary entries

final class GlossarySearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GlossaryEntry>>,
          List<GlossaryEntry>,
          FutureOr<List<GlossaryEntry>>
        >
    with
        $FutureModifier<List<GlossaryEntry>>,
        $FutureProvider<List<GlossaryEntry>> {
  /// Search glossary entries
  const GlossarySearchResultsProvider._({
    required GlossarySearchResultsFamily super.from,
    required ({
      String query,
      List<String>? glossaryIds,
      String? targetLanguageCode,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'glossarySearchResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$glossarySearchResultsHash();

  @override
  String toString() {
    return r'glossarySearchResultsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<GlossaryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GlossaryEntry>> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String query,
              List<String>? glossaryIds,
              String? targetLanguageCode,
            });
    return glossarySearchResults(
      ref,
      query: argument.query,
      glossaryIds: argument.glossaryIds,
      targetLanguageCode: argument.targetLanguageCode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GlossarySearchResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$glossarySearchResultsHash() =>
    r'b2dca7bb1b2572f795375599c23548082520be40';

/// Search glossary entries

final class GlossarySearchResultsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<GlossaryEntry>>,
          ({
            String query,
            List<String>? glossaryIds,
            String? targetLanguageCode,
          })
        > {
  const GlossarySearchResultsFamily._()
    : super(
        retry: null,
        name: r'glossarySearchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Search glossary entries

  GlossarySearchResultsProvider call({
    required String query,
    List<String>? glossaryIds,
    String? targetLanguageCode,
  }) => GlossarySearchResultsProvider._(
    argument: (
      query: query,
      glossaryIds: glossaryIds,
      targetLanguageCode: targetLanguageCode,
    ),
    from: this,
  );

  @override
  String toString() => r'glossarySearchResultsProvider';
}

/// Glossary statistics

@ProviderFor(glossaryStatistics)
const glossaryStatisticsProvider = GlossaryStatisticsFamily._();

/// Glossary statistics

final class GlossaryStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<GlossaryStatistics>,
          GlossaryStatistics,
          FutureOr<GlossaryStatistics>
        >
    with
        $FutureModifier<GlossaryStatistics>,
        $FutureProvider<GlossaryStatistics> {
  /// Glossary statistics
  const GlossaryStatisticsProvider._({
    required GlossaryStatisticsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'glossaryStatisticsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$glossaryStatisticsHash();

  @override
  String toString() {
    return r'glossaryStatisticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GlossaryStatistics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GlossaryStatistics> create(Ref ref) {
    final argument = this.argument as String;
    return glossaryStatistics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GlossaryStatisticsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$glossaryStatisticsHash() =>
    r'2867021befda77d14072ff1fd6142eadd5dab748';

/// Glossary statistics

final class GlossaryStatisticsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<GlossaryStatistics>, String> {
  const GlossaryStatisticsFamily._()
    : super(
        retry: null,
        name: r'glossaryStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Glossary statistics

  GlossaryStatisticsProvider call(String glossaryId) =>
      GlossaryStatisticsProvider._(argument: glossaryId, from: this);

  @override
  String toString() => r'glossaryStatisticsProvider';
}

/// Entry editor state (for add/edit)

@ProviderFor(GlossaryEntryEditor)
const glossaryEntryEditorProvider = GlossaryEntryEditorProvider._();

/// Entry editor state (for add/edit)
final class GlossaryEntryEditorProvider
    extends $NotifierProvider<GlossaryEntryEditor, GlossaryEntry?> {
  /// Entry editor state (for add/edit)
  const GlossaryEntryEditorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'glossaryEntryEditorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$glossaryEntryEditorHash();

  @$internal
  @override
  GlossaryEntryEditor create() => GlossaryEntryEditor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GlossaryEntry? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GlossaryEntry?>(value),
    );
  }
}

String _$glossaryEntryEditorHash() =>
    r'8a8c76b74c9856d133304be47583e1199d603ae7';

/// Entry editor state (for add/edit)

abstract class _$GlossaryEntryEditor extends $Notifier<GlossaryEntry?> {
  GlossaryEntry? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<GlossaryEntry?, GlossaryEntry?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GlossaryEntry?, GlossaryEntry?>,
              GlossaryEntry?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Filter state

@ProviderFor(GlossaryFilterState)
const glossaryFilterStateProvider = GlossaryFilterStateProvider._();

/// Filter state
final class GlossaryFilterStateProvider
    extends $NotifierProvider<GlossaryFilterState, GlossaryFilters> {
  /// Filter state
  const GlossaryFilterStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'glossaryFilterStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$glossaryFilterStateHash();

  @$internal
  @override
  GlossaryFilterState create() => GlossaryFilterState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GlossaryFilters value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GlossaryFilters>(value),
    );
  }
}

String _$glossaryFilterStateHash() =>
    r'2c6dab06f92779d995a5e2db28bf14a5e1d70c12';

/// Filter state

abstract class _$GlossaryFilterState extends $Notifier<GlossaryFilters> {
  GlossaryFilters build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<GlossaryFilters, GlossaryFilters>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GlossaryFilters, GlossaryFilters>,
              GlossaryFilters,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Pagination state

@ProviderFor(GlossaryPageState)
const glossaryPageStateProvider = GlossaryPageStateProvider._();

/// Pagination state
final class GlossaryPageStateProvider
    extends $NotifierProvider<GlossaryPageState, int> {
  /// Pagination state
  const GlossaryPageStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'glossaryPageStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$glossaryPageStateHash();

  @$internal
  @override
  GlossaryPageState create() => GlossaryPageState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$glossaryPageStateHash() => r'4889811f94c13b6be58379966d5ee21ef928048e';

/// Pagination state

abstract class _$GlossaryPageState extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Import state

@ProviderFor(GlossaryImportState)
const glossaryImportStateProvider = GlossaryImportStateProvider._();

/// Import state
final class GlossaryImportStateProvider
    extends $NotifierProvider<GlossaryImportState, AsyncValue<ImportResult?>> {
  /// Import state
  const GlossaryImportStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'glossaryImportStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$glossaryImportStateHash();

  @$internal
  @override
  GlossaryImportState create() => GlossaryImportState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ImportResult?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ImportResult?>>(value),
    );
  }
}

String _$glossaryImportStateHash() =>
    r'c9562c6438a0abf4e354564030473e14ae729f77';

/// Import state

abstract class _$GlossaryImportState
    extends $Notifier<AsyncValue<ImportResult?>> {
  AsyncValue<ImportResult?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<ImportResult?>, AsyncValue<ImportResult?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ImportResult?>, AsyncValue<ImportResult?>>,
              AsyncValue<ImportResult?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Export state

@ProviderFor(GlossaryExportState)
const glossaryExportStateProvider = GlossaryExportStateProvider._();

/// Export state
final class GlossaryExportStateProvider
    extends $NotifierProvider<GlossaryExportState, AsyncValue<ExportResult?>> {
  /// Export state
  const GlossaryExportStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'glossaryExportStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$glossaryExportStateHash();

  @$internal
  @override
  GlossaryExportState create() => GlossaryExportState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ExportResult?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ExportResult?>>(value),
    );
  }
}

String _$glossaryExportStateHash() =>
    r'c2a7d2877d5fdd364829aef00ab37557fb314070';

/// Export state

abstract class _$GlossaryExportState
    extends $Notifier<AsyncValue<ExportResult?>> {
  AsyncValue<ExportResult?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<ExportResult?>, AsyncValue<ExportResult?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ExportResult?>, AsyncValue<ExportResult?>>,
              AsyncValue<ExportResult?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
