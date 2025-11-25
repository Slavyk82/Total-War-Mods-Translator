// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tm_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// TM entries list with filtering and pagination

@ProviderFor(tmEntries)
const tmEntriesProvider = TmEntriesFamily._();

/// TM entries list with filtering and pagination

final class TmEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationMemoryEntry>>,
          List<TranslationMemoryEntry>,
          FutureOr<List<TranslationMemoryEntry>>
        >
    with
        $FutureModifier<List<TranslationMemoryEntry>>,
        $FutureProvider<List<TranslationMemoryEntry>> {
  /// TM entries list with filtering and pagination
  const TmEntriesProvider._({
    required TmEntriesFamily super.from,
    required ({
      String? targetLang,
      String? gameContext,
      double? minQuality,
      int page,
      int pageSize,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'tmEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tmEntriesHash();

  @override
  String toString() {
    return r'tmEntriesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranslationMemoryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranslationMemoryEntry>> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String? targetLang,
              String? gameContext,
              double? minQuality,
              int page,
              int pageSize,
            });
    return tmEntries(
      ref,
      targetLang: argument.targetLang,
      gameContext: argument.gameContext,
      minQuality: argument.minQuality,
      page: argument.page,
      pageSize: argument.pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TmEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tmEntriesHash() => r'dcb6e7e72a1ff30fe18502a3130f1debc30692f1';

/// TM entries list with filtering and pagination

final class TmEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranslationMemoryEntry>>,
          ({
            String? targetLang,
            String? gameContext,
            double? minQuality,
            int page,
            int pageSize,
          })
        > {
  const TmEntriesFamily._()
    : super(
        retry: null,
        name: r'tmEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TM entries list with filtering and pagination

  TmEntriesProvider call({
    String? targetLang,
    String? gameContext,
    double? minQuality,
    int page = 1,
    int pageSize = 20,
  }) => TmEntriesProvider._(
    argument: (
      targetLang: targetLang,
      gameContext: gameContext,
      minQuality: minQuality,
      page: page,
      pageSize: pageSize,
    ),
    from: this,
  );

  @override
  String toString() => r'tmEntriesProvider';
}

/// Total count of TM entries (for pagination)

@ProviderFor(tmEntriesCount)
const tmEntriesCountProvider = TmEntriesCountFamily._();

/// Total count of TM entries (for pagination)

final class TmEntriesCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Total count of TM entries (for pagination)
  const TmEntriesCountProvider._({
    required TmEntriesCountFamily super.from,
    required ({String? targetLang, String? gameContext, double? minQuality})
    super.argument,
  }) : super(
         retry: null,
         name: r'tmEntriesCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tmEntriesCountHash();

  @override
  String toString() {
    return r'tmEntriesCountProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument =
        this.argument
            as ({String? targetLang, String? gameContext, double? minQuality});
    return tmEntriesCount(
      ref,
      targetLang: argument.targetLang,
      gameContext: argument.gameContext,
      minQuality: argument.minQuality,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TmEntriesCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tmEntriesCountHash() => r'a0efd6ec21fa36eea925c526bd51dd2dfea5df71';

/// Total count of TM entries (for pagination)

final class TmEntriesCountFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<int>,
          ({String? targetLang, String? gameContext, double? minQuality})
        > {
  const TmEntriesCountFamily._()
    : super(
        retry: null,
        name: r'tmEntriesCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Total count of TM entries (for pagination)

  TmEntriesCountProvider call({
    String? targetLang,
    String? gameContext,
    double? minQuality,
  }) => TmEntriesCountProvider._(
    argument: (
      targetLang: targetLang,
      gameContext: gameContext,
      minQuality: minQuality,
    ),
    from: this,
  );

  @override
  String toString() => r'tmEntriesCountProvider';
}

/// TM statistics

@ProviderFor(tmStatistics)
const tmStatisticsProvider = TmStatisticsFamily._();

/// TM statistics

final class TmStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TmStatistics>,
          TmStatistics,
          FutureOr<TmStatistics>
        >
    with $FutureModifier<TmStatistics>, $FutureProvider<TmStatistics> {
  /// TM statistics
  const TmStatisticsProvider._({
    required TmStatisticsFamily super.from,
    required ({String? targetLang, String? gameContext}) super.argument,
  }) : super(
         retry: null,
         name: r'tmStatisticsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tmStatisticsHash();

  @override
  String toString() {
    return r'tmStatisticsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<TmStatistics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TmStatistics> create(Ref ref) {
    final argument =
        this.argument as ({String? targetLang, String? gameContext});
    return tmStatistics(
      ref,
      targetLang: argument.targetLang,
      gameContext: argument.gameContext,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TmStatisticsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tmStatisticsHash() => r'000862d694b44d3f6c554b4a784a6089bff45152';

/// TM statistics

final class TmStatisticsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<TmStatistics>,
          ({String? targetLang, String? gameContext})
        > {
  const TmStatisticsFamily._()
    : super(
        retry: null,
        name: r'tmStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TM statistics

  TmStatisticsProvider call({String? targetLang, String? gameContext}) =>
      TmStatisticsProvider._(
        argument: (targetLang: targetLang, gameContext: gameContext),
        from: this,
      );

  @override
  String toString() => r'tmStatisticsProvider';
}

/// Search TM entries by text

@ProviderFor(tmSearchResults)
const tmSearchResultsProvider = TmSearchResultsFamily._();

/// Search TM entries by text

final class TmSearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationMemoryEntry>>,
          List<TranslationMemoryEntry>,
          FutureOr<List<TranslationMemoryEntry>>
        >
    with
        $FutureModifier<List<TranslationMemoryEntry>>,
        $FutureProvider<List<TranslationMemoryEntry>> {
  /// Search TM entries by text
  const TmSearchResultsProvider._({
    required TmSearchResultsFamily super.from,
    required ({
      String searchText,
      TmSearchScope searchIn,
      String? targetLang,
      int limit,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'tmSearchResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tmSearchResultsHash();

  @override
  String toString() {
    return r'tmSearchResultsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranslationMemoryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranslationMemoryEntry>> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String searchText,
              TmSearchScope searchIn,
              String? targetLang,
              int limit,
            });
    return tmSearchResults(
      ref,
      searchText: argument.searchText,
      searchIn: argument.searchIn,
      targetLang: argument.targetLang,
      limit: argument.limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TmSearchResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tmSearchResultsHash() => r'b130204119090f2e05b3593396b892506b35fcc3';

/// Search TM entries by text

final class TmSearchResultsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranslationMemoryEntry>>,
          ({
            String searchText,
            TmSearchScope searchIn,
            String? targetLang,
            int limit,
          })
        > {
  const TmSearchResultsFamily._()
    : super(
        retry: null,
        name: r'tmSearchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Search TM entries by text

  TmSearchResultsProvider call({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLang,
    int limit = 50,
  }) => TmSearchResultsProvider._(
    argument: (
      searchText: searchText,
      searchIn: searchIn,
      targetLang: targetLang,
      limit: limit,
    ),
    from: this,
  );

  @override
  String toString() => r'tmSearchResultsProvider';
}

/// Selected TM entry (for edit/details)

@ProviderFor(SelectedTmEntry)
const selectedTmEntryProvider = SelectedTmEntryProvider._();

/// Selected TM entry (for edit/details)
final class SelectedTmEntryProvider
    extends $NotifierProvider<SelectedTmEntry, TranslationMemoryEntry?> {
  /// Selected TM entry (for edit/details)
  const SelectedTmEntryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedTmEntryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedTmEntryHash();

  @$internal
  @override
  SelectedTmEntry create() => SelectedTmEntry();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationMemoryEntry? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationMemoryEntry?>(value),
    );
  }
}

String _$selectedTmEntryHash() => r'83913aa65e3d53c87ba8c9677b498c0bdfa289ae';

/// Selected TM entry (for edit/details)

abstract class _$SelectedTmEntry extends $Notifier<TranslationMemoryEntry?> {
  TranslationMemoryEntry? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<TranslationMemoryEntry?, TranslationMemoryEntry?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TranslationMemoryEntry?, TranslationMemoryEntry?>,
              TranslationMemoryEntry?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Current filter state

@ProviderFor(TmFilterState)
const tmFilterStateProvider = TmFilterStateProvider._();

/// Current filter state
final class TmFilterStateProvider
    extends $NotifierProvider<TmFilterState, TmFilters> {
  /// Current filter state
  const TmFilterStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmFilterStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmFilterStateHash();

  @$internal
  @override
  TmFilterState create() => TmFilterState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TmFilters value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TmFilters>(value),
    );
  }
}

String _$tmFilterStateHash() => r'2e875f58f2a619d161130c888ff2dfb648ec8a50';

/// Current filter state

abstract class _$TmFilterState extends $Notifier<TmFilters> {
  TmFilters build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<TmFilters, TmFilters>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TmFilters, TmFilters>,
              TmFilters,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Current page number

@ProviderFor(TmPageState)
const tmPageStateProvider = TmPageStateProvider._();

/// Current page number
final class TmPageStateProvider extends $NotifierProvider<TmPageState, int> {
  /// Current page number
  const TmPageStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmPageStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmPageStateHash();

  @$internal
  @override
  TmPageState create() => TmPageState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$tmPageStateHash() => r'9d42218aa6b94ce6c48197dbd2f11bc76bdb1546';

/// Current page number

abstract class _$TmPageState extends $Notifier<int> {
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

@ProviderFor(TmImportState)
const tmImportStateProvider = TmImportStateProvider._();

/// Import state
final class TmImportStateProvider
    extends $NotifierProvider<TmImportState, AsyncValue<TmImportResult?>> {
  /// Import state
  const TmImportStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmImportStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmImportStateHash();

  @$internal
  @override
  TmImportState create() => TmImportState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<TmImportResult?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<TmImportResult?>>(value),
    );
  }
}

String _$tmImportStateHash() => r'05cc4f8d3ce10194f5f72b126e576f20cc9c8ebb';

/// Import state

abstract class _$TmImportState extends $Notifier<AsyncValue<TmImportResult?>> {
  AsyncValue<TmImportResult?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<AsyncValue<TmImportResult?>, AsyncValue<TmImportResult?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TmImportResult?>,
                AsyncValue<TmImportResult?>
              >,
              AsyncValue<TmImportResult?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Export state

@ProviderFor(TmExportState)
const tmExportStateProvider = TmExportStateProvider._();

/// Export state
final class TmExportStateProvider
    extends $NotifierProvider<TmExportState, AsyncValue<TmExportResult?>> {
  /// Export state
  const TmExportStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmExportStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmExportStateHash();

  @$internal
  @override
  TmExportState create() => TmExportState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<TmExportResult?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<TmExportResult?>>(value),
    );
  }
}

String _$tmExportStateHash() => r'93ed1e2ddc47a9db3fd5ac7d71e84bf46c3af33e';

/// Export state

abstract class _$TmExportState extends $Notifier<AsyncValue<TmExportResult?>> {
  AsyncValue<TmExportResult?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<AsyncValue<TmExportResult?>, AsyncValue<TmExportResult?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TmExportResult?>,
                AsyncValue<TmExportResult?>
              >,
              AsyncValue<TmExportResult?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Cleanup state

@ProviderFor(TmCleanupState)
const tmCleanupStateProvider = TmCleanupStateProvider._();

/// Cleanup state
final class TmCleanupStateProvider
    extends $NotifierProvider<TmCleanupState, AsyncValue<int?>> {
  /// Cleanup state
  const TmCleanupStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmCleanupStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmCleanupStateHash();

  @$internal
  @override
  TmCleanupState create() => TmCleanupState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<int?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<int?>>(value),
    );
  }
}

String _$tmCleanupStateHash() => r'fce065c7b0a50bd91c75c6b813dcf4f20c249df5';

/// Cleanup state

abstract class _$TmCleanupState extends $Notifier<AsyncValue<int?>> {
  AsyncValue<int?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<int?>, AsyncValue<int?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int?>, AsyncValue<int?>>,
              AsyncValue<int?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Delete TM entry state

@ProviderFor(TmDeleteState)
const tmDeleteStateProvider = TmDeleteStateProvider._();

/// Delete TM entry state
final class TmDeleteStateProvider
    extends $NotifierProvider<TmDeleteState, AsyncValue<bool?>> {
  /// Delete TM entry state
  const TmDeleteStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmDeleteStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmDeleteStateHash();

  @$internal
  @override
  TmDeleteState create() => TmDeleteState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<bool?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<bool?>>(value),
    );
  }
}

String _$tmDeleteStateHash() => r'aa0277843ec6c2436d248f7399d6b797004669a3';

/// Delete TM entry state

abstract class _$TmDeleteState extends $Notifier<AsyncValue<bool?>> {
  AsyncValue<bool?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<bool?>, AsyncValue<bool?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool?>, AsyncValue<bool?>>,
              AsyncValue<bool?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
