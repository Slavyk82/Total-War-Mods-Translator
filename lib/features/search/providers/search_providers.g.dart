// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Current search query state

@ProviderFor(SearchQuery)
const searchQueryProvider = SearchQueryProvider._();

/// Current search query state
final class SearchQueryProvider
    extends $NotifierProvider<SearchQuery, SearchQueryModel> {
  /// Current search query state
  const SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchQueryModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchQueryModel>(value),
    );
  }
}

String _$searchQueryHash() => r'12a53ede851dae45d99ef0b1cc5ba2e0077bea4c';

/// Current search query state

abstract class _$SearchQuery extends $Notifier<SearchQueryModel> {
  SearchQueryModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<SearchQueryModel, SearchQueryModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SearchQueryModel, SearchQueryModel>,
              SearchQueryModel,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Execute search and get results

@ProviderFor(searchResults)
const searchResultsProvider = SearchResultsFamily._();

/// Execute search and get results

final class SearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<SearchResultsModel>,
          SearchResultsModel,
          FutureOr<SearchResultsModel>
        >
    with
        $FutureModifier<SearchResultsModel>,
        $FutureProvider<SearchResultsModel> {
  /// Execute search and get results
  const SearchResultsProvider._({
    required SearchResultsFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'searchResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$searchResultsHash();

  @override
  String toString() {
    return r'searchResultsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SearchResultsModel> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SearchResultsModel> create(Ref ref) {
    final argument = this.argument as int;
    return searchResults(ref, page: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SearchResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$searchResultsHash() => r'4c66e4f722fdb5320d0657b1d281f4af27813d28';

/// Execute search and get results

final class SearchResultsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SearchResultsModel>, int> {
  const SearchResultsFamily._()
    : super(
        retry: null,
        name: r'searchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Execute search and get results

  SearchResultsProvider call({int page = 1}) =>
      SearchResultsProvider._(argument: page, from: this);

  @override
  String toString() => r'searchResultsProvider';
}

/// Search history (last 50 searches)

@ProviderFor(searchHistory)
const searchHistoryProvider = SearchHistoryProvider._();

/// Search history (last 50 searches)

final class SearchHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Map<String, dynamic>>>,
          List<Map<String, dynamic>>,
          FutureOr<List<Map<String, dynamic>>>
        >
    with
        $FutureModifier<List<Map<String, dynamic>>>,
        $FutureProvider<List<Map<String, dynamic>>> {
  /// Search history (last 50 searches)
  const SearchHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryHash();

  @$internal
  @override
  $FutureProviderElement<List<Map<String, dynamic>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Map<String, dynamic>>> create(Ref ref) {
    return searchHistory(ref);
  }
}

String _$searchHistoryHash() => r'893b327184ab0ae9c1724d5667725eee1488d2a1';

/// Saved searches list

@ProviderFor(savedSearches)
const savedSearchesProvider = SavedSearchesProvider._();

/// Saved searches list

final class SavedSearchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SavedSearch>>,
          List<SavedSearch>,
          FutureOr<List<SavedSearch>>
        >
    with
        $FutureModifier<List<SavedSearch>>,
        $FutureProvider<List<SavedSearch>> {
  /// Saved searches list
  const SavedSearchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'savedSearchesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$savedSearchesHash();

  @$internal
  @override
  $FutureProviderElement<List<SavedSearch>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SavedSearch>> create(Ref ref) {
    return savedSearches(ref);
  }
}

String _$savedSearchesHash() => r'a67dafc916e5c39143b34eddbcb3f580de26f719';

/// Save a search

@ProviderFor(SaveSearchAction)
const saveSearchActionProvider = SaveSearchActionProvider._();

/// Save a search
final class SaveSearchActionProvider
    extends $NotifierProvider<SaveSearchAction, AsyncValue<void>> {
  /// Save a search
  const SaveSearchActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'saveSearchActionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$saveSearchActionHash();

  @$internal
  @override
  SaveSearchAction create() => SaveSearchAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$saveSearchActionHash() => r'098298797d7bf8fbb55d84e27c22bf5138de9376';

/// Save a search

abstract class _$SaveSearchAction extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Delete a saved search

@ProviderFor(DeleteSearchAction)
const deleteSearchActionProvider = DeleteSearchActionProvider._();

/// Delete a saved search
final class DeleteSearchActionProvider
    extends $NotifierProvider<DeleteSearchAction, AsyncValue<void>> {
  /// Delete a saved search
  const DeleteSearchActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteSearchActionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteSearchActionHash();

  @$internal
  @override
  DeleteSearchAction create() => DeleteSearchAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$deleteSearchActionHash() =>
    r'1615bd801f5354b37f553a1fafad500108a849f9';

/// Delete a saved search

abstract class _$DeleteSearchAction extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Execute a saved search

@ProviderFor(ExecuteSavedSearchAction)
const executeSavedSearchActionProvider = ExecuteSavedSearchActionProvider._();

/// Execute a saved search
final class ExecuteSavedSearchActionProvider
    extends $NotifierProvider<ExecuteSavedSearchAction, AsyncValue<void>> {
  /// Execute a saved search
  const ExecuteSavedSearchActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'executeSavedSearchActionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$executeSavedSearchActionHash();

  @$internal
  @override
  ExecuteSavedSearchAction create() => ExecuteSavedSearchAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$executeSavedSearchActionHash() =>
    r'896f9097f02978e65b6bd4e1b5813462f124dea0';

/// Execute a saved search

abstract class _$ExecuteSavedSearchAction extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Clear search history

@ProviderFor(ClearHistoryAction)
const clearHistoryActionProvider = ClearHistoryActionProvider._();

/// Clear search history
final class ClearHistoryActionProvider
    extends $NotifierProvider<ClearHistoryAction, AsyncValue<void>> {
  /// Clear search history
  const ClearHistoryActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clearHistoryActionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clearHistoryActionHash();

  @$internal
  @override
  ClearHistoryAction create() => ClearHistoryAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$clearHistoryActionHash() =>
    r'ae24c4bcaac96cb1f3b40ebd695a73218e999abb';

/// Clear search history

abstract class _$ClearHistoryAction extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
