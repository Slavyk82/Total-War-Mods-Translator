// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mods_screen_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

/// Filtered mods based on search query

@ProviderFor(filteredMods)
const filteredModsProvider = FilteredModsProvider._();

/// Filtered mods based on search query

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
  /// Filtered mods based on search query
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

String _$filteredModsHash() => r'6091b1570c5bac904bcaf42410ee41bb571d00e6';

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
