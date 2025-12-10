// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mods_screen_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Filter state for mods screen

@ProviderFor(ModsFilterState)
const modsFilterStateProvider = ModsFilterStateProvider._();

/// Filter state for mods screen
final class ModsFilterStateProvider
    extends $NotifierProvider<ModsFilterState, ModsFilter> {
  /// Filter state for mods screen
  const ModsFilterStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modsFilterStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modsFilterStateHash();

  @$internal
  @override
  ModsFilterState create() => ModsFilterState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModsFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModsFilter>(value),
    );
  }
}

String _$modsFilterStateHash() => r'd8e0a297739808ad4f533931d4f1a27804b12149';

/// Filter state for mods screen

abstract class _$ModsFilterState extends $Notifier<ModsFilter> {
  ModsFilter build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ModsFilter, ModsFilter>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ModsFilter, ModsFilter>,
              ModsFilter,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Search query state for mods screen

@ProviderFor(ModsSearchQuery)
const modsSearchQueryProvider = ModsSearchQueryProvider._();

/// Search query state for mods screen
final class ModsSearchQueryProvider
    extends $NotifierProvider<ModsSearchQuery, String> {
  /// Search query state for mods screen
  const ModsSearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modsSearchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modsSearchQueryHash();

  @$internal
  @override
  ModsSearchQuery create() => ModsSearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$modsSearchQueryHash() => r'29093f1c5c9eaa73b481e8726313e9cfbd2237dc';

/// Search query state for mods screen

abstract class _$ModsSearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Show hidden mods filter state

@ProviderFor(ShowHiddenMods)
const showHiddenModsProvider = ShowHiddenModsProvider._();

/// Show hidden mods filter state
final class ShowHiddenModsProvider
    extends $NotifierProvider<ShowHiddenMods, bool> {
  /// Show hidden mods filter state
  const ShowHiddenModsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'showHiddenModsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$showHiddenModsHash();

  @$internal
  @override
  ShowHiddenMods create() => ShowHiddenMods();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$showHiddenModsHash() => r'cc0423131033c63bf5e6069be2c5c1e600f2d5f3';

/// Show hidden mods filter state

abstract class _$ShowHiddenMods extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Filtered mods based on search query, filter, and hidden state

@ProviderFor(filteredMods)
const filteredModsProvider = FilteredModsProvider._();

/// Filtered mods based on search query, filter, and hidden state

final class FilteredModsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DetectedMod>>,
          List<DetectedMod>,
          FutureOr<List<DetectedMod>>
        >
    with
        $FutureModifier<List<DetectedMod>>,
        $FutureProvider<List<DetectedMod>> {
  /// Filtered mods based on search query, filter, and hidden state
  const FilteredModsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filteredModsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filteredModsHash();

  @$internal
  @override
  $FutureProviderElement<List<DetectedMod>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DetectedMod>> create(Ref ref) {
    return filteredMods(ref);
  }
}

String _$filteredModsHash() => r'7e099664fe3def340adefe0b666db2226b4ed1df';

/// Provider for total mods count (excluding hidden)

@ProviderFor(totalModsCount)
const totalModsCountProvider = TotalModsCountProvider._();

/// Provider for total mods count (excluding hidden)

final class TotalModsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Provider for total mods count (excluding hidden)
  const TotalModsCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'totalModsCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$totalModsCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return totalModsCount(ref);
  }
}

String _$totalModsCountHash() => r'12bfe0517c7973432b664eea1b619ea8daf562be';

/// Provider for hidden mods count

@ProviderFor(hiddenModsCount)
const hiddenModsCountProvider = HiddenModsCountProvider._();

/// Provider for hidden mods count

final class HiddenModsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Provider for hidden mods count
  const HiddenModsCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hiddenModsCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hiddenModsCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return hiddenModsCount(ref);
  }
}

String _$hiddenModsCountHash() => r'561ea8aa67a3499a42fcccfdebfeca3a3f75132d';

/// Provider for not imported mods count (respects hidden filter)

@ProviderFor(notImportedModsCount)
const notImportedModsCountProvider = NotImportedModsCountProvider._();

/// Provider for not imported mods count (respects hidden filter)

final class NotImportedModsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Provider for not imported mods count (respects hidden filter)
  const NotImportedModsCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notImportedModsCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notImportedModsCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return notImportedModsCount(ref);
  }
}

String _$notImportedModsCountHash() =>
    r'c60aaa5a09ed76437ecda9067685cbc43b7c8bc3';

/// Provider for mods needing update count (respects hidden filter)

@ProviderFor(needsUpdateModsCount)
const needsUpdateModsCountProvider = NeedsUpdateModsCountProvider._();

/// Provider for mods needing update count (respects hidden filter)

final class NeedsUpdateModsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Provider for mods needing update count (respects hidden filter)
  const NeedsUpdateModsCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'needsUpdateModsCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$needsUpdateModsCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return needsUpdateModsCount(ref);
  }
}

String _$needsUpdateModsCountHash() =>
    r'4eca06098ef9f967460938bf7d069267c679558a';

/// Provider for count of projects with pending changes.
/// Uses the same logic as the Projects screen: compares Steam timestamp vs local file timestamp
/// and checks if the cache has changes. This ensures consistency between screens.

@ProviderFor(projectsWithPendingChangesCount)
const projectsWithPendingChangesCountProvider =
    ProjectsWithPendingChangesCountProvider._();

/// Provider for count of projects with pending changes.
/// Uses the same logic as the Projects screen: compares Steam timestamp vs local file timestamp
/// and checks if the cache has changes. This ensures consistency between screens.

final class ProjectsWithPendingChangesCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Provider for count of projects with pending changes.
  /// Uses the same logic as the Projects screen: compares Steam timestamp vs local file timestamp
  /// and checks if the cache has changes. This ensures consistency between screens.
  const ProjectsWithPendingChangesCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectsWithPendingChangesCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectsWithPendingChangesCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return projectsWithPendingChangesCount(ref);
  }
}

String _$projectsWithPendingChangesCountHash() =>
    r'1fd9664b50be5b5750bad64eb42f55b4c96a7c03';

/// Refresh trigger for mods list

@ProviderFor(ModsRefreshTrigger)
const modsRefreshTriggerProvider = ModsRefreshTriggerProvider._();

/// Refresh trigger for mods list
final class ModsRefreshTriggerProvider
    extends $NotifierProvider<ModsRefreshTrigger, int> {
  /// Refresh trigger for mods list
  const ModsRefreshTriggerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modsRefreshTriggerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modsRefreshTriggerHash();

  @$internal
  @override
  ModsRefreshTrigger create() => ModsRefreshTrigger();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$modsRefreshTriggerHash() =>
    r'bbe7a9dff95a64e12d2eb2c3c34ee68c7e0479a2';

/// Refresh trigger for mods list

abstract class _$ModsRefreshTrigger extends $Notifier<int> {
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

/// Loading state for mods screen

@ProviderFor(ModsLoadingState)
const modsLoadingStateProvider = ModsLoadingStateProvider._();

/// Loading state for mods screen
final class ModsLoadingStateProvider
    extends $NotifierProvider<ModsLoadingState, bool> {
  /// Loading state for mods screen
  const ModsLoadingStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modsLoadingStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modsLoadingStateHash();

  @$internal
  @override
  ModsLoadingState create() => ModsLoadingState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$modsLoadingStateHash() => r'844327f73b5ad4b7619dc0a8c277aafdf2c784cd';

/// Loading state for mods screen

abstract class _$ModsLoadingState extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Toggle mod hidden status

@ProviderFor(ModHiddenToggle)
const modHiddenToggleProvider = ModHiddenToggleProvider._();

/// Toggle mod hidden status
final class ModHiddenToggleProvider
    extends $AsyncNotifierProvider<ModHiddenToggle, void> {
  /// Toggle mod hidden status
  const ModHiddenToggleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modHiddenToggleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modHiddenToggleHash();

  @$internal
  @override
  ModHiddenToggle create() => ModHiddenToggle();
}

String _$modHiddenToggleHash() => r'84cc1c4068118d1c013e53de8e1eb7c0add5bbb7';

/// Toggle mod hidden status

abstract class _$ModHiddenToggle extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
