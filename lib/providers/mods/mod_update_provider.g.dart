// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_update_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for managing mod update queue and progress

@ProviderFor(ModUpdateQueue)
const modUpdateQueueProvider = ModUpdateQueueProvider._();

/// Provider for managing mod update queue and progress
final class ModUpdateQueueProvider
    extends $NotifierProvider<ModUpdateQueue, Map<String, ModUpdateInfo>> {
  /// Provider for managing mod update queue and progress
  const ModUpdateQueueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modUpdateQueueProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modUpdateQueueHash();

  @$internal
  @override
  ModUpdateQueue create() => ModUpdateQueue();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ModUpdateInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ModUpdateInfo>>(value),
    );
  }
}

String _$modUpdateQueueHash() => r'873dc745d53adf730cb348010dd670d1b8bec16d';

/// Provider for managing mod update queue and progress

abstract class _$ModUpdateQueue extends $Notifier<Map<String, ModUpdateInfo>> {
  Map<String, ModUpdateInfo> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<Map<String, ModUpdateInfo>, Map<String, ModUpdateInfo>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, ModUpdateInfo>,
                Map<String, ModUpdateInfo>
              >,
              Map<String, ModUpdateInfo>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
