// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_notification_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Listens to batch events and triggers appropriate notifications
///
/// This provider handles side effects (notifications) separately from state management.
/// It's kept alive for the entire app lifecycle to ensure notifications work globally.

@ProviderFor(BatchNotifications)
const batchNotificationsProvider = BatchNotificationsProvider._();

/// Listens to batch events and triggers appropriate notifications
///
/// This provider handles side effects (notifications) separately from state management.
/// It's kept alive for the entire app lifecycle to ensure notifications work globally.
final class BatchNotificationsProvider
    extends $NotifierProvider<BatchNotifications, void> {
  /// Listens to batch events and triggers appropriate notifications
  ///
  /// This provider handles side effects (notifications) separately from state management.
  /// It's kept alive for the entire app lifecycle to ensure notifications work globally.
  const BatchNotificationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchNotificationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchNotificationsHash();

  @$internal
  @override
  BatchNotifications create() => BatchNotifications();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$batchNotificationsHash() =>
    r'17d9cb4cbf6e7c0f8ae9af5ad60f8199d5b36678';

/// Listens to batch events and triggers appropriate notifications
///
/// This provider handles side effects (notifications) separately from state management.
/// It's kept alive for the entire app lifecycle to ensure notifications work globally.

abstract class _$BatchNotifications extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
