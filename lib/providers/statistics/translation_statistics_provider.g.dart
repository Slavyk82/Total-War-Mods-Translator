// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_statistics_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Real-time translation statistics that update as events occur

@ProviderFor(TranslationStatistics)
const translationStatisticsProvider = TranslationStatisticsProvider._();

/// Real-time translation statistics that update as events occur
final class TranslationStatisticsProvider
    extends $NotifierProvider<TranslationStatistics, TranslationStats> {
  /// Real-time translation statistics that update as events occur
  const TranslationStatisticsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationStatisticsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationStatisticsHash();

  @$internal
  @override
  TranslationStatistics create() => TranslationStatistics();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationStats value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationStats>(value),
    );
  }
}

String _$translationStatisticsHash() =>
    r'8751664f396eee77404e2f524e5a377861ec2f7a';

/// Real-time translation statistics that update as events occur

abstract class _$TranslationStatistics extends $Notifier<TranslationStats> {
  TranslationStats build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<TranslationStats, TranslationStats>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TranslationStats, TranslationStats>,
              TranslationStats,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
