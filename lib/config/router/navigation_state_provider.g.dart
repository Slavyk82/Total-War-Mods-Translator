// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for navigation state with SharedPreferences persistence

@ProviderFor(NavigationStateNotifier)
const navigationStateProvider = NavigationStateNotifierProvider._();

/// Provider for navigation state with SharedPreferences persistence
final class NavigationStateNotifierProvider
    extends $NotifierProvider<NavigationStateNotifier, NavigationState> {
  /// Provider for navigation state with SharedPreferences persistence
  const NavigationStateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'navigationStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$navigationStateNotifierHash();

  @$internal
  @override
  NavigationStateNotifier create() => NavigationStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NavigationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NavigationState>(value),
    );
  }
}

String _$navigationStateNotifierHash() =>
    r'9de05b8c8d119eff04f641d89c0f2ff57b19743a';

/// Provider for navigation state with SharedPreferences persistence

abstract class _$NavigationStateNotifier extends $Notifier<NavigationState> {
  NavigationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<NavigationState, NavigationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NavigationState, NavigationState>,
              NavigationState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
