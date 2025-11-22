// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// History service provider
///
/// Provides access to the history service for recording and managing
/// translation version history.

@ProviderFor(historyService)
const historyServiceProvider = HistoryServiceProvider._();

/// History service provider
///
/// Provides access to the history service for recording and managing
/// translation version history.

final class HistoryServiceProvider
    extends
        $FunctionalProvider<IHistoryService, IHistoryService, IHistoryService>
    with $Provider<IHistoryService> {
  /// History service provider
  ///
  /// Provides access to the history service for recording and managing
  /// translation version history.
  const HistoryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyServiceHash();

  @$internal
  @override
  $ProviderElement<IHistoryService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  IHistoryService create(Ref ref) {
    return historyService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IHistoryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IHistoryService>(value),
    );
  }
}

String _$historyServiceHash() => r'15db73988257c24f3409ca5b9c84fc0223ec2e9c';

/// Provider for history entries of a specific translation version
///
/// Returns all history entries for a version, ordered by creation date (newest first).

@ProviderFor(versionHistory)
const versionHistoryProvider = VersionHistoryFamily._();

/// Provider for history entries of a specific translation version
///
/// Returns all history entries for a version, ordered by creation date (newest first).

final class VersionHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationVersionHistory>>,
          List<TranslationVersionHistory>,
          FutureOr<List<TranslationVersionHistory>>
        >
    with
        $FutureModifier<List<TranslationVersionHistory>>,
        $FutureProvider<List<TranslationVersionHistory>> {
  /// Provider for history entries of a specific translation version
  ///
  /// Returns all history entries for a version, ordered by creation date (newest first).
  const VersionHistoryProvider._({
    required VersionHistoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'versionHistoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$versionHistoryHash();

  @override
  String toString() {
    return r'versionHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranslationVersionHistory>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranslationVersionHistory>> create(Ref ref) {
    final argument = this.argument as String;
    return versionHistory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VersionHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$versionHistoryHash() => r'e921ff437bc77e2362419ed39b03537dd6312362';

/// Provider for history entries of a specific translation version
///
/// Returns all history entries for a version, ordered by creation date (newest first).

final class VersionHistoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranslationVersionHistory>>,
          String
        > {
  const VersionHistoryFamily._()
    : super(
        retry: null,
        name: r'versionHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for history entries of a specific translation version
  ///
  /// Returns all history entries for a version, ordered by creation date (newest first).

  VersionHistoryProvider call(String versionId) =>
      VersionHistoryProvider._(argument: versionId, from: this);

  @override
  String toString() => r'versionHistoryProvider';
}

/// Provider for a specific history entry

@ProviderFor(historyEntry)
const historyEntryProvider = HistoryEntryFamily._();

/// Provider for a specific history entry

final class HistoryEntryProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationVersionHistory>,
          TranslationVersionHistory,
          FutureOr<TranslationVersionHistory>
        >
    with
        $FutureModifier<TranslationVersionHistory>,
        $FutureProvider<TranslationVersionHistory> {
  /// Provider for a specific history entry
  const HistoryEntryProvider._({
    required HistoryEntryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'historyEntryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$historyEntryHash();

  @override
  String toString() {
    return r'historyEntryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<TranslationVersionHistory> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TranslationVersionHistory> create(Ref ref) {
    final argument = this.argument as String;
    return historyEntry(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is HistoryEntryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$historyEntryHash() => r'd4681cfd4ae57c48b9ce9d51df07a00c698acb85';

/// Provider for a specific history entry

final class HistoryEntryFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<TranslationVersionHistory>, String> {
  const HistoryEntryFamily._()
    : super(
        retry: null,
        name: r'historyEntryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for a specific history entry

  HistoryEntryProvider call(String historyId) =>
      HistoryEntryProvider._(argument: historyId, from: this);

  @override
  String toString() => r'historyEntryProvider';
}

/// Provider for comparing two history versions

@ProviderFor(versionComparison)
const versionComparisonProvider = VersionComparisonFamily._();

/// Provider for comparing two history versions

final class VersionComparisonProvider
    extends
        $FunctionalProvider<
          AsyncValue<VersionComparison>,
          VersionComparison,
          FutureOr<VersionComparison>
        >
    with
        $FutureModifier<VersionComparison>,
        $FutureProvider<VersionComparison> {
  /// Provider for comparing two history versions
  const VersionComparisonProvider._({
    required VersionComparisonFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'versionComparisonProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$versionComparisonHash();

  @override
  String toString() {
    return r'versionComparisonProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<VersionComparison> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<VersionComparison> create(Ref ref) {
    final argument = this.argument as (String, String);
    return versionComparison(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is VersionComparisonProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$versionComparisonHash() => r'368dd616f99cff095f52cd8ecdfc19892a0ff982';

/// Provider for comparing two history versions

final class VersionComparisonFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<VersionComparison>,
          (String, String)
        > {
  const VersionComparisonFamily._()
    : super(
        retry: null,
        name: r'versionComparisonProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for comparing two history versions

  VersionComparisonProvider call(String historyId1, String historyId2) =>
      VersionComparisonProvider._(
        argument: (historyId1, historyId2),
        from: this,
      );

  @override
  String toString() => r'versionComparisonProvider';
}

/// Provider for history statistics

@ProviderFor(historyStatistics)
const historyStatisticsProvider = HistoryStatisticsProvider._();

/// Provider for history statistics

final class HistoryStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<HistoryStats>,
          HistoryStats,
          FutureOr<HistoryStats>
        >
    with $FutureModifier<HistoryStats>, $FutureProvider<HistoryStats> {
  /// Provider for history statistics
  const HistoryStatisticsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyStatisticsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyStatisticsHash();

  @$internal
  @override
  $FutureProviderElement<HistoryStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HistoryStats> create(Ref ref) {
    return historyStatistics(ref);
  }
}

String _$historyStatisticsHash() => r'19b90c2f22cf5f91a03d6142914107dea4942d55';

/// Provider for history statistics of a specific version

@ProviderFor(versionHistoryStatistics)
const versionHistoryStatisticsProvider = VersionHistoryStatisticsFamily._();

/// Provider for history statistics of a specific version

final class VersionHistoryStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<HistoryStats>,
          HistoryStats,
          FutureOr<HistoryStats>
        >
    with $FutureModifier<HistoryStats>, $FutureProvider<HistoryStats> {
  /// Provider for history statistics of a specific version
  const VersionHistoryStatisticsProvider._({
    required VersionHistoryStatisticsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'versionHistoryStatisticsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$versionHistoryStatisticsHash();

  @override
  String toString() {
    return r'versionHistoryStatisticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<HistoryStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HistoryStats> create(Ref ref) {
    final argument = this.argument as String;
    return versionHistoryStatistics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VersionHistoryStatisticsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$versionHistoryStatisticsHash() =>
    r'372d0f0f04f89edd9eb96d4bc1b8ddf16e415462';

/// Provider for history statistics of a specific version

final class VersionHistoryStatisticsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<HistoryStats>, String> {
  const VersionHistoryStatisticsFamily._()
    : super(
        retry: null,
        name: r'versionHistoryStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for history statistics of a specific version

  VersionHistoryStatisticsProvider call(String versionId) =>
      VersionHistoryStatisticsProvider._(argument: versionId, from: this);

  @override
  String toString() => r'versionHistoryStatisticsProvider';
}

/// Undo/Redo Manager Provider
///
/// This is a singleton provider that maintains the undo/redo state
/// throughout the application lifecycle. It's kept alive to preserve
/// the undo/redo history even when widgets are disposed.

@ProviderFor(UndoRedoManagerNotifier)
const undoRedoManagerProvider = UndoRedoManagerNotifierProvider._();

/// Undo/Redo Manager Provider
///
/// This is a singleton provider that maintains the undo/redo state
/// throughout the application lifecycle. It's kept alive to preserve
/// the undo/redo history even when widgets are disposed.
final class UndoRedoManagerNotifierProvider
    extends $NotifierProvider<UndoRedoManagerNotifier, UndoRedoManagerState> {
  /// Undo/Redo Manager Provider
  ///
  /// This is a singleton provider that maintains the undo/redo state
  /// throughout the application lifecycle. It's kept alive to preserve
  /// the undo/redo history even when widgets are disposed.
  const UndoRedoManagerNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'undoRedoManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$undoRedoManagerNotifierHash();

  @$internal
  @override
  UndoRedoManagerNotifier create() => UndoRedoManagerNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UndoRedoManagerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UndoRedoManagerState>(value),
    );
  }
}

String _$undoRedoManagerNotifierHash() =>
    r'83a35caee50e09a9c74d2fb44f93a05afc4e4ccb';

/// Undo/Redo Manager Provider
///
/// This is a singleton provider that maintains the undo/redo state
/// throughout the application lifecycle. It's kept alive to preserve
/// the undo/redo history even when widgets are disposed.

abstract class _$UndoRedoManagerNotifier
    extends $Notifier<UndoRedoManagerState> {
  UndoRedoManagerState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<UndoRedoManagerState, UndoRedoManagerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UndoRedoManagerState, UndoRedoManagerState>,
              UndoRedoManagerState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for checking if undo is available

@ProviderFor(canUndo)
const canUndoProvider = CanUndoProvider._();

/// Provider for checking if undo is available

final class CanUndoProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider for checking if undo is available
  const CanUndoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canUndoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canUndoHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return canUndo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$canUndoHash() => r'11b9fb284b9581ff5987e3521ab2ba983b0a243b';

/// Provider for checking if redo is available

@ProviderFor(canRedo)
const canRedoProvider = CanRedoProvider._();

/// Provider for checking if redo is available

final class CanRedoProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider for checking if redo is available
  const CanRedoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canRedoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canRedoHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return canRedo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$canRedoHash() => r'0a8e2c6c34ef6ee8994b9327d59e0b985b9b6cda';
