// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statistics_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for statistics overview

@ProviderFor(statisticsOverview)
const statisticsOverviewProvider = StatisticsOverviewProvider._();

/// Provider for statistics overview

final class StatisticsOverviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<StatisticsOverview>,
          StatisticsOverview,
          FutureOr<StatisticsOverview>
        >
    with
        $FutureModifier<StatisticsOverview>,
        $FutureProvider<StatisticsOverview> {
  /// Provider for statistics overview
  const StatisticsOverviewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statisticsOverviewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statisticsOverviewHash();

  @$internal
  @override
  $FutureProviderElement<StatisticsOverview> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<StatisticsOverview> create(Ref ref) {
    return statisticsOverview(ref);
  }
}

String _$statisticsOverviewHash() =>
    r'3b9e4612da089d3a58c0fee11025b0008aacc7d5';

/// Provider for daily progress data

@ProviderFor(dailyProgressData)
const dailyProgressDataProvider = DailyProgressDataFamily._();

/// Provider for daily progress data

final class DailyProgressDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DailyProgress>>,
          List<DailyProgress>,
          FutureOr<List<DailyProgress>>
        >
    with
        $FutureModifier<List<DailyProgress>>,
        $FutureProvider<List<DailyProgress>> {
  /// Provider for daily progress data
  const DailyProgressDataProvider._({
    required DailyProgressDataFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'dailyProgressDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyProgressDataHash();

  @override
  String toString() {
    return r'dailyProgressDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<DailyProgress>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DailyProgress>> create(Ref ref) {
    final argument = this.argument as int;
    return dailyProgressData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DailyProgressDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyProgressDataHash() => r'367897dcf592cec9278b3dc293d8baf3435660b2';

/// Provider for daily progress data

final class DailyProgressDataFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<DailyProgress>>, int> {
  const DailyProgressDataFamily._()
    : super(
        retry: null,
        name: r'dailyProgressDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for daily progress data

  DailyProgressDataProvider call(int days) =>
      DailyProgressDataProvider._(argument: days, from: this);

  @override
  String toString() => r'dailyProgressDataProvider';
}

/// Provider for monthly usage data

@ProviderFor(monthlyUsageData)
const monthlyUsageDataProvider = MonthlyUsageDataFamily._();

/// Provider for monthly usage data

final class MonthlyUsageDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MonthlyUsage>>,
          List<MonthlyUsage>,
          FutureOr<List<MonthlyUsage>>
        >
    with
        $FutureModifier<List<MonthlyUsage>>,
        $FutureProvider<List<MonthlyUsage>> {
  /// Provider for monthly usage data
  const MonthlyUsageDataProvider._({
    required MonthlyUsageDataFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'monthlyUsageDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$monthlyUsageDataHash();

  @override
  String toString() {
    return r'monthlyUsageDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<MonthlyUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MonthlyUsage>> create(Ref ref) {
    final argument = this.argument as int;
    return monthlyUsageData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MonthlyUsageDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monthlyUsageDataHash() => r'1c6d7d3557a91ccce58e5f08d4c23a1709d12597';

/// Provider for monthly usage data

final class MonthlyUsageDataFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<MonthlyUsage>>, int> {
  const MonthlyUsageDataFamily._()
    : super(
        retry: null,
        name: r'monthlyUsageDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for monthly usage data

  MonthlyUsageDataProvider call(int months) =>
      MonthlyUsageDataProvider._(argument: months, from: this);

  @override
  String toString() => r'monthlyUsageDataProvider';
}

/// Provider for TM effectiveness data

@ProviderFor(tmEffectivenessData)
const tmEffectivenessDataProvider = TmEffectivenessDataProvider._();

/// Provider for TM effectiveness data

final class TmEffectivenessDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<TmEffectiveness>,
          TmEffectiveness,
          FutureOr<TmEffectiveness>
        >
    with $FutureModifier<TmEffectiveness>, $FutureProvider<TmEffectiveness> {
  /// Provider for TM effectiveness data
  const TmEffectivenessDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tmEffectivenessDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tmEffectivenessDataHash();

  @$internal
  @override
  $FutureProviderElement<TmEffectiveness> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TmEffectiveness> create(Ref ref) {
    return tmEffectivenessData(ref);
  }
}

String _$tmEffectivenessDataHash() =>
    r'd8022fa8201002619abce67033cb1da1d85d891b';

/// Provider for project statistics data

@ProviderFor(projectStatsData)
const projectStatsDataProvider = ProjectStatsDataProvider._();

/// Provider for project statistics data

final class ProjectStatsDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ProjectStats>>,
          List<ProjectStats>,
          FutureOr<List<ProjectStats>>
        >
    with
        $FutureModifier<List<ProjectStats>>,
        $FutureProvider<List<ProjectStats>> {
  /// Provider for project statistics data
  const ProjectStatsDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectStatsDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectStatsDataHash();

  @$internal
  @override
  $FutureProviderElement<List<ProjectStats>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ProjectStats>> create(Ref ref) {
    return projectStatsData(ref);
  }
}

String _$projectStatsDataHash() => r'6fdddf5b98217968643b9a9f6b78fb6464b87f5a';
