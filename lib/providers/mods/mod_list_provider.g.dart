// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides list of detected mods after scanning Workshop folder (without creating projects)

@ProviderFor(DetectedMods)
const detectedModsProvider = DetectedModsProvider._();

/// Provides list of detected mods after scanning Workshop folder (without creating projects)
final class DetectedModsProvider
    extends $AsyncNotifierProvider<DetectedMods, List<DetectedMod>> {
  /// Provides list of detected mods after scanning Workshop folder (without creating projects)
  const DetectedModsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'detectedModsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$detectedModsHash();

  @$internal
  @override
  DetectedMods create() => DetectedMods();
}

String _$detectedModsHash() => r'09e06823e06843cbb3b0cbb304e44343c8f7ad6a';

/// Provides list of detected mods after scanning Workshop folder (without creating projects)

abstract class _$DetectedMods extends $AsyncNotifier<List<DetectedMod>> {
  FutureOr<List<DetectedMod>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<List<DetectedMod>>, List<DetectedMod>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<DetectedMod>>, List<DetectedMod>>,
              AsyncValue<List<DetectedMod>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provides list of all projects from database

@ProviderFor(allProjects)
const allProjectsProvider = AllProjectsProvider._();

/// Provides list of all projects from database

final class AllProjectsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Project>>,
          List<Project>,
          FutureOr<List<Project>>
        >
    with $FutureModifier<List<Project>>, $FutureProvider<List<Project>> {
  /// Provides list of all projects from database
  const AllProjectsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allProjectsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allProjectsHash();

  @$internal
  @override
  $FutureProviderElement<List<Project>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Project>> create(Ref ref) {
    return allProjects(ref);
  }
}

String _$allProjectsHash() => r'c32dc5cb43db1de7ea10afe726eeb72c876a7b9c';

/// Checks if a mod has an update available

@ProviderFor(modUpdateAvailable)
const modUpdateAvailableProvider = ModUpdateAvailableFamily._();

/// Checks if a mod has an update available

final class ModUpdateAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Checks if a mod has an update available
  const ModUpdateAvailableProvider._({
    required ModUpdateAvailableFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'modUpdateAvailableProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$modUpdateAvailableHash();

  @override
  String toString() {
    return r'modUpdateAvailableProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return modUpdateAvailable(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ModUpdateAvailableProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$modUpdateAvailableHash() =>
    r'a029c3cdebaed129bb02a637bd0765c1fddd7444';

/// Checks if a mod has an update available

final class ModUpdateAvailableFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  const ModUpdateAvailableFamily._()
    : super(
        retry: null,
        name: r'modUpdateAvailableProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Checks if a mod has an update available

  ModUpdateAvailableProvider call(String projectId) =>
      ModUpdateAvailableProvider._(argument: projectId, from: this);

  @override
  String toString() => r'modUpdateAvailableProvider';
}

/// Provides list of projects with available updates
/// Performance: Uses single pass filter instead of N+1 provider calls

@ProviderFor(modsWithUpdates)
const modsWithUpdatesProvider = ModsWithUpdatesProvider._();

/// Provides list of projects with available updates
/// Performance: Uses single pass filter instead of N+1 provider calls

final class ModsWithUpdatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Project>>,
          List<Project>,
          FutureOr<List<Project>>
        >
    with $FutureModifier<List<Project>>, $FutureProvider<List<Project>> {
  /// Provides list of projects with available updates
  /// Performance: Uses single pass filter instead of N+1 provider calls
  const ModsWithUpdatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modsWithUpdatesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modsWithUpdatesHash();

  @$internal
  @override
  $FutureProviderElement<List<Project>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Project>> create(Ref ref) {
    return modsWithUpdates(ref);
  }
}

String _$modsWithUpdatesHash() => r'e97f6d2c07988f8febdda41e6c421ac4caecab11';

/// Provider for update banner visibility state

@ProviderFor(UpdateBannerVisible)
const updateBannerVisibleProvider = UpdateBannerVisibleProvider._();

/// Provider for update banner visibility state
final class UpdateBannerVisibleProvider
    extends $AsyncNotifierProvider<UpdateBannerVisible, bool> {
  /// Provider for update banner visibility state
  const UpdateBannerVisibleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateBannerVisibleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateBannerVisibleHash();

  @$internal
  @override
  UpdateBannerVisible create() => UpdateBannerVisible();
}

String _$updateBannerVisibleHash() =>
    r'9bd1d1d43b5ccb95539ea65fad7448e6b43895f4';

/// Provider for update banner visibility state

abstract class _$UpdateBannerVisible extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
