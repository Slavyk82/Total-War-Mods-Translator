// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selected_game_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for the list of configured games (games with a path set in settings)

@ProviderFor(configuredGames)
const configuredGamesProvider = ConfiguredGamesProvider._();

/// Provider for the list of configured games (games with a path set in settings)

final class ConfiguredGamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ConfiguredGame>>,
          List<ConfiguredGame>,
          FutureOr<List<ConfiguredGame>>
        >
    with
        $FutureModifier<List<ConfiguredGame>>,
        $FutureProvider<List<ConfiguredGame>> {
  /// Provider for the list of configured games (games with a path set in settings)
  const ConfiguredGamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'configuredGamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$configuredGamesHash();

  @$internal
  @override
  $FutureProviderElement<List<ConfiguredGame>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ConfiguredGame>> create(Ref ref) {
    return configuredGames(ref);
  }
}

String _$configuredGamesHash() => r'f4b6b71112b7cf5f1e852a5ca02db1b6f4f5ec66';

/// Provider for the currently selected game

@ProviderFor(SelectedGame)
const selectedGameProvider = SelectedGameProvider._();

/// Provider for the currently selected game
final class SelectedGameProvider
    extends $AsyncNotifierProvider<SelectedGame, ConfiguredGame?> {
  /// Provider for the currently selected game
  const SelectedGameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGameProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGameHash();

  @$internal
  @override
  SelectedGame create() => SelectedGame();
}

String _$selectedGameHash() => r'4692134879b3af12f7a8b366c6dbca219225a3b7';

/// Provider for the currently selected game

abstract class _$SelectedGame extends $AsyncNotifier<ConfiguredGame?> {
  FutureOr<ConfiguredGame?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<ConfiguredGame?>, ConfiguredGame?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ConfiguredGame?>, ConfiguredGame?>,
              AsyncValue<ConfiguredGame?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
