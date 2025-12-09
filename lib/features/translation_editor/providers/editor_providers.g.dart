// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editor_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.

@ProviderFor(TranslationInProgress)
const translationInProgressProvider = TranslationInProgressProvider._();

/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.
final class TranslationInProgressProvider
    extends $NotifierProvider<TranslationInProgress, bool> {
  /// Global state tracking if a batch translation is in progress.
  /// Used to block navigation while translation is running.
  const TranslationInProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationInProgressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationInProgressHash();

  @$internal
  @override
  TranslationInProgress create() => TranslationInProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$translationInProgressHash() =>
    r'ac33a69c2047562b5ccbedf20e9f84db7af8e574';

/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.

abstract class _$TranslationInProgress extends $Notifier<bool> {
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

/// Provider for project repository

@ProviderFor(projectRepository)
const projectRepositoryProvider = ProjectRepositoryProvider._();

/// Provider for project repository

final class ProjectRepositoryProvider
    extends
        $FunctionalProvider<
          ProjectRepository,
          ProjectRepository,
          ProjectRepository
        >
    with $Provider<ProjectRepository> {
  /// Provider for project repository
  const ProjectRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProjectRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectRepository create(Ref ref) {
    return projectRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectRepository>(value),
    );
  }
}

String _$projectRepositoryHash() => r'824b61f9b6f8ba217dbb9243b13a8f6130c05946';

/// Provider for language repository

@ProviderFor(languageRepository)
const languageRepositoryProvider = LanguageRepositoryProvider._();

/// Provider for language repository

final class LanguageRepositoryProvider
    extends
        $FunctionalProvider<
          LanguageRepository,
          LanguageRepository,
          LanguageRepository
        >
    with $Provider<LanguageRepository> {
  /// Provider for language repository
  const LanguageRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'languageRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$languageRepositoryHash();

  @$internal
  @override
  $ProviderElement<LanguageRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LanguageRepository create(Ref ref) {
    return languageRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanguageRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanguageRepository>(value),
    );
  }
}

String _$languageRepositoryHash() =>
    r'4ec3febceb5ae544cecf768ad1f2048f573e25d5';

/// Provider for translation unit repository

@ProviderFor(translationUnitRepository)
const translationUnitRepositoryProvider = TranslationUnitRepositoryProvider._();

/// Provider for translation unit repository

final class TranslationUnitRepositoryProvider
    extends
        $FunctionalProvider<
          TranslationUnitRepository,
          TranslationUnitRepository,
          TranslationUnitRepository
        >
    with $Provider<TranslationUnitRepository> {
  /// Provider for translation unit repository
  const TranslationUnitRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationUnitRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationUnitRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranslationUnitRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationUnitRepository create(Ref ref) {
    return translationUnitRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationUnitRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationUnitRepository>(value),
    );
  }
}

String _$translationUnitRepositoryHash() =>
    r'695ca016e650276618da20fe20a917194ca5cc93';

/// Provider for translation version repository

@ProviderFor(translationVersionRepository)
const translationVersionRepositoryProvider =
    TranslationVersionRepositoryProvider._();

/// Provider for translation version repository

final class TranslationVersionRepositoryProvider
    extends
        $FunctionalProvider<
          TranslationVersionRepository,
          TranslationVersionRepository,
          TranslationVersionRepository
        >
    with $Provider<TranslationVersionRepository> {
  /// Provider for translation version repository
  const TranslationVersionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationVersionRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationVersionRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranslationVersionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationVersionRepository create(Ref ref) {
    return translationVersionRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationVersionRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationVersionRepository>(value),
    );
  }
}

String _$translationVersionRepositoryHash() =>
    r'f15c93f2b3d840ce8bab483eb72a49ed352229f4';

/// Provider for translation memory service

@ProviderFor(translationMemoryService)
const translationMemoryServiceProvider = TranslationMemoryServiceProvider._();

/// Provider for translation memory service

final class TranslationMemoryServiceProvider
    extends
        $FunctionalProvider<
          ITranslationMemoryService,
          ITranslationMemoryService,
          ITranslationMemoryService
        >
    with $Provider<ITranslationMemoryService> {
  /// Provider for translation memory service
  const TranslationMemoryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationMemoryServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationMemoryServiceHash();

  @$internal
  @override
  $ProviderElement<ITranslationMemoryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ITranslationMemoryService create(Ref ref) {
    return translationMemoryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ITranslationMemoryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ITranslationMemoryService>(value),
    );
  }
}

String _$translationMemoryServiceHash() =>
    r'80bd642ababfe9fa006f7a215789bcb49e25361d';

/// Provider for search service

@ProviderFor(searchService)
const searchServiceProvider = SearchServiceProvider._();

/// Provider for search service

final class SearchServiceProvider
    extends $FunctionalProvider<ISearchService, ISearchService, ISearchService>
    with $Provider<ISearchService> {
  /// Provider for search service
  const SearchServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchServiceHash();

  @$internal
  @override
  $ProviderElement<ISearchService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ISearchService create(Ref ref) {
    return searchService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ISearchService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ISearchService>(value),
    );
  }
}

String _$searchServiceHash() => r'0c2a414bac2d6fc3353372f24f9f0c1acb532325';

/// Provider for undo/redo manager

@ProviderFor(undoRedoManager)
const undoRedoManagerProvider = UndoRedoManagerProvider._();

/// Provider for undo/redo manager

final class UndoRedoManagerProvider
    extends
        $FunctionalProvider<UndoRedoManager, UndoRedoManager, UndoRedoManager>
    with $Provider<UndoRedoManager> {
  /// Provider for undo/redo manager
  const UndoRedoManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'undoRedoManagerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$undoRedoManagerHash();

  @$internal
  @override
  $ProviderElement<UndoRedoManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UndoRedoManager create(Ref ref) {
    return undoRedoManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UndoRedoManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UndoRedoManager>(value),
    );
  }
}

String _$undoRedoManagerHash() => r'ec4a43830e57e09cb3c3e0e0a952dcfb70bd0dbf';

/// Provider for current project

@ProviderFor(currentProject)
const currentProjectProvider = CurrentProjectFamily._();

/// Provider for current project

final class CurrentProjectProvider
    extends $FunctionalProvider<AsyncValue<Project>, Project, FutureOr<Project>>
    with $FutureModifier<Project>, $FutureProvider<Project> {
  /// Provider for current project
  const CurrentProjectProvider._({
    required CurrentProjectFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'currentProjectProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentProjectHash();

  @override
  String toString() {
    return r'currentProjectProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Project> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Project> create(Ref ref) {
    final argument = this.argument as String;
    return currentProject(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentProjectProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentProjectHash() => r'1c16bf9e6590b8362042afaa1d6959eabc63d82d';

/// Provider for current project

final class CurrentProjectFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Project>, String> {
  const CurrentProjectFamily._()
    : super(
        retry: null,
        name: r'currentProjectProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for current project

  CurrentProjectProvider call(String projectId) =>
      CurrentProjectProvider._(argument: projectId, from: this);

  @override
  String toString() => r'currentProjectProvider';
}

/// Provider for current language

@ProviderFor(currentLanguage)
const currentLanguageProvider = CurrentLanguageFamily._();

/// Provider for current language

final class CurrentLanguageProvider
    extends
        $FunctionalProvider<AsyncValue<Language>, Language, FutureOr<Language>>
    with $FutureModifier<Language>, $FutureProvider<Language> {
  /// Provider for current language
  const CurrentLanguageProvider._({
    required CurrentLanguageFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'currentLanguageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentLanguageHash();

  @override
  String toString() {
    return r'currentLanguageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Language> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Language> create(Ref ref) {
    final argument = this.argument as String;
    return currentLanguage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentLanguageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentLanguageHash() => r'1b802c7c4c01ed2799d337f505eb7bfee449679c';

/// Provider for current language

final class CurrentLanguageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Language>, String> {
  const CurrentLanguageFamily._()
    : super(
        retry: null,
        name: r'currentLanguageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for current language

  CurrentLanguageProvider call(String languageId) =>
      CurrentLanguageProvider._(argument: languageId, from: this);

  @override
  String toString() => r'currentLanguageProvider';
}

/// Provider for filter state

@ProviderFor(EditorFilter)
const editorFilterProvider = EditorFilterProvider._();

/// Provider for filter state
final class EditorFilterProvider
    extends $NotifierProvider<EditorFilter, EditorFilterState> {
  /// Provider for filter state
  const EditorFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'editorFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$editorFilterHash();

  @$internal
  @override
  EditorFilter create() => EditorFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorFilterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorFilterState>(value),
    );
  }
}

String _$editorFilterHash() => r'0ac3147de5fae642e9222a2369bacf4a2af3b14a';

/// Provider for filter state

abstract class _$EditorFilter extends $Notifier<EditorFilterState> {
  EditorFilterState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<EditorFilterState, EditorFilterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorFilterState, EditorFilterState>,
              EditorFilterState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for selection state

@ProviderFor(EditorSelection)
const editorSelectionProvider = EditorSelectionProvider._();

/// Provider for selection state
final class EditorSelectionProvider
    extends $NotifierProvider<EditorSelection, EditorSelectionState> {
  /// Provider for selection state
  const EditorSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'editorSelectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$editorSelectionHash();

  @$internal
  @override
  EditorSelection create() => EditorSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorSelectionState>(value),
    );
  }
}

String _$editorSelectionHash() => r'f8243178162919cdc53a9cd1ede1d2c67c2244bf';

/// Provider for selection state

abstract class _$EditorSelection extends $Notifier<EditorSelectionState> {
  EditorSelectionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<EditorSelectionState, EditorSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorSelectionState, EditorSelectionState>,
              EditorSelectionState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for translation rows (units + versions)

@ProviderFor(translationRows)
const translationRowsProvider = TranslationRowsFamily._();

/// Provider for translation rows (units + versions)

final class TranslationRowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationRow>>,
          List<TranslationRow>,
          FutureOr<List<TranslationRow>>
        >
    with
        $FutureModifier<List<TranslationRow>>,
        $FutureProvider<List<TranslationRow>> {
  /// Provider for translation rows (units + versions)
  const TranslationRowsProvider._({
    required TranslationRowsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'translationRowsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$translationRowsHash();

  @override
  String toString() {
    return r'translationRowsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranslationRow>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranslationRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return translationRows(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is TranslationRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$translationRowsHash() => r'18273cf1fff73ac0773924e2d041732baff3f33e';

/// Provider for translation rows (units + versions)

final class TranslationRowsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranslationRow>>,
          (String, String)
        > {
  const TranslationRowsFamily._()
    : super(
        retry: null,
        name: r'translationRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for translation rows (units + versions)

  TranslationRowsProvider call(String projectId, String languageId) =>
      TranslationRowsProvider._(argument: (projectId, languageId), from: this);

  @override
  String toString() => r'translationRowsProvider';
}

/// Provider for filtered translation rows
/// Applies status filters, TM source filters, and search query from EditorFilterState

@ProviderFor(filteredTranslationRows)
const filteredTranslationRowsProvider = FilteredTranslationRowsFamily._();

/// Provider for filtered translation rows
/// Applies status filters, TM source filters, and search query from EditorFilterState

final class FilteredTranslationRowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationRow>>,
          List<TranslationRow>,
          FutureOr<List<TranslationRow>>
        >
    with
        $FutureModifier<List<TranslationRow>>,
        $FutureProvider<List<TranslationRow>> {
  /// Provider for filtered translation rows
  /// Applies status filters, TM source filters, and search query from EditorFilterState
  const FilteredTranslationRowsProvider._({
    required FilteredTranslationRowsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'filteredTranslationRowsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$filteredTranslationRowsHash();

  @override
  String toString() {
    return r'filteredTranslationRowsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranslationRow>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranslationRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return filteredTranslationRows(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is FilteredTranslationRowsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$filteredTranslationRowsHash() =>
    r'16434b9d99d78e50beb141b972602f379bfdb217';

/// Provider for filtered translation rows
/// Applies status filters, TM source filters, and search query from EditorFilterState

final class FilteredTranslationRowsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranslationRow>>,
          (String, String)
        > {
  const FilteredTranslationRowsFamily._()
    : super(
        retry: null,
        name: r'filteredTranslationRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for filtered translation rows
  /// Applies status filters, TM source filters, and search query from EditorFilterState

  FilteredTranslationRowsProvider call(String projectId, String languageId) =>
      FilteredTranslationRowsProvider._(
        argument: (projectId, languageId),
        from: this,
      );

  @override
  String toString() => r'filteredTranslationRowsProvider';
}

/// Provider for editor statistics
/// Uses database statistics for consistency with project list (excludes bracket-only units)

@ProviderFor(editorStats)
const editorStatsProvider = EditorStatsFamily._();

/// Provider for editor statistics
/// Uses database statistics for consistency with project list (excludes bracket-only units)

final class EditorStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<EditorStats>,
          EditorStats,
          FutureOr<EditorStats>
        >
    with $FutureModifier<EditorStats>, $FutureProvider<EditorStats> {
  /// Provider for editor statistics
  /// Uses database statistics for consistency with project list (excludes bracket-only units)
  const EditorStatsProvider._({
    required EditorStatsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'editorStatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$editorStatsHash();

  @override
  String toString() {
    return r'editorStatsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<EditorStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<EditorStats> create(Ref ref) {
    final argument = this.argument as (String, String);
    return editorStats(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is EditorStatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$editorStatsHash() => r'86d254d3c843d5906dfb0a803110657d18cb1dd4';

/// Provider for editor statistics
/// Uses database statistics for consistency with project list (excludes bracket-only units)

final class EditorStatsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<EditorStats>, (String, String)> {
  const EditorStatsFamily._()
    : super(
        retry: null,
        name: r'editorStatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for editor statistics
  /// Uses database statistics for consistency with project list (excludes bracket-only units)

  EditorStatsProvider call(String projectId, String languageId) =>
      EditorStatsProvider._(argument: (projectId, languageId), from: this);

  @override
  String toString() => r'editorStatsProvider';
}

/// Provider for validation service

@ProviderFor(validationService)
const validationServiceProvider = ValidationServiceProvider._();

/// Provider for validation service

final class ValidationServiceProvider
    extends
        $FunctionalProvider<
          ITranslationValidationService,
          ITranslationValidationService,
          ITranslationValidationService
        >
    with $Provider<ITranslationValidationService> {
  /// Provider for validation service
  const ValidationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'validationServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$validationServiceHash();

  @$internal
  @override
  $ProviderElement<ITranslationValidationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ITranslationValidationService create(Ref ref) {
    return validationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ITranslationValidationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ITranslationValidationService>(
        value,
      ),
    );
  }
}

String _$validationServiceHash() => r'146cc02490c1cac473ebd23f29386cc6126764d2';

/// Provider for logging service

@ProviderFor(loggingService)
const loggingServiceProvider = LoggingServiceProvider._();

/// Provider for logging service

final class LoggingServiceProvider
    extends $FunctionalProvider<LoggingService, LoggingService, LoggingService>
    with $Provider<LoggingService> {
  /// Provider for logging service
  const LoggingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loggingServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loggingServiceHash();

  @$internal
  @override
  $ProviderElement<LoggingService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LoggingService create(Ref ref) {
    return loggingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LoggingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LoggingService>(value),
    );
  }
}

String _$loggingServiceHash() => r'98bc9fb1afedab0c689d64503f088530b812608c';

/// Provider for translation batch repository

@ProviderFor(translationBatchRepository)
const translationBatchRepositoryProvider =
    TranslationBatchRepositoryProvider._();

/// Provider for translation batch repository

final class TranslationBatchRepositoryProvider
    extends
        $FunctionalProvider<
          TranslationBatchRepository,
          TranslationBatchRepository,
          TranslationBatchRepository
        >
    with $Provider<TranslationBatchRepository> {
  /// Provider for translation batch repository
  const TranslationBatchRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationBatchRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationBatchRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranslationBatchRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationBatchRepository create(Ref ref) {
    return translationBatchRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationBatchRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationBatchRepository>(value),
    );
  }
}

String _$translationBatchRepositoryHash() =>
    r'867f17953db2c8ad4818cee00c01c8efbfb3cf62';

/// Provider for translation batch unit repository

@ProviderFor(translationBatchUnitRepository)
const translationBatchUnitRepositoryProvider =
    TranslationBatchUnitRepositoryProvider._();

/// Provider for translation batch unit repository

final class TranslationBatchUnitRepositoryProvider
    extends
        $FunctionalProvider<
          TranslationBatchUnitRepository,
          TranslationBatchUnitRepository,
          TranslationBatchUnitRepository
        >
    with $Provider<TranslationBatchUnitRepository> {
  /// Provider for translation batch unit repository
  const TranslationBatchUnitRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationBatchUnitRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationBatchUnitRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranslationBatchUnitRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationBatchUnitRepository create(Ref ref) {
    return translationBatchUnitRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationBatchUnitRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationBatchUnitRepository>(
        value,
      ),
    );
  }
}

String _$translationBatchUnitRepositoryHash() =>
    r'2e2b0550357134c15e1801d6685728f0a69cc232';

/// Provider for project language repository

@ProviderFor(projectLanguageRepository)
const projectLanguageRepositoryProvider = ProjectLanguageRepositoryProvider._();

/// Provider for project language repository

final class ProjectLanguageRepositoryProvider
    extends
        $FunctionalProvider<
          ProjectLanguageRepository,
          ProjectLanguageRepository,
          ProjectLanguageRepository
        >
    with $Provider<ProjectLanguageRepository> {
  /// Provider for project language repository
  const ProjectLanguageRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectLanguageRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectLanguageRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProjectLanguageRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectLanguageRepository create(Ref ref) {
    return projectLanguageRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectLanguageRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectLanguageRepository>(value),
    );
  }
}

String _$projectLanguageRepositoryHash() =>
    r'21c62483d7ddf8a0ab754a51712bc87c778d2b8a';

/// Provider for translation orchestrator

@ProviderFor(translationOrchestrator)
const translationOrchestratorProvider = TranslationOrchestratorProvider._();

/// Provider for translation orchestrator

final class TranslationOrchestratorProvider
    extends
        $FunctionalProvider<
          ITranslationOrchestrator,
          ITranslationOrchestrator,
          ITranslationOrchestrator
        >
    with $Provider<ITranslationOrchestrator> {
  /// Provider for translation orchestrator
  const TranslationOrchestratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationOrchestratorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationOrchestratorHash();

  @$internal
  @override
  $ProviderElement<ITranslationOrchestrator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ITranslationOrchestrator create(Ref ref) {
    return translationOrchestrator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ITranslationOrchestrator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ITranslationOrchestrator>(value),
    );
  }
}

String _$translationOrchestratorHash() =>
    r'3d7e2a1c3073a9a1d926c67999527624c0c3adda';

/// Provider for export orchestrator service

@ProviderFor(exportOrchestratorService)
const exportOrchestratorServiceProvider = ExportOrchestratorServiceProvider._();

/// Provider for export orchestrator service

final class ExportOrchestratorServiceProvider
    extends
        $FunctionalProvider<
          ExportOrchestratorService,
          ExportOrchestratorService,
          ExportOrchestratorService
        >
    with $Provider<ExportOrchestratorService> {
  /// Provider for export orchestrator service
  const ExportOrchestratorServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportOrchestratorServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportOrchestratorServiceHash();

  @$internal
  @override
  $ProviderElement<ExportOrchestratorService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ExportOrchestratorService create(Ref ref) {
    return exportOrchestratorService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExportOrchestratorService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExportOrchestratorService>(value),
    );
  }
}

String _$exportOrchestratorServiceHash() =>
    r'1c960285d585ea32587263c30625ed1e5d6dfb2f';

/// Provider for LLM provider model repository

@ProviderFor(llmProviderModelRepository)
const llmProviderModelRepositoryProvider =
    LlmProviderModelRepositoryProvider._();

/// Provider for LLM provider model repository

final class LlmProviderModelRepositoryProvider
    extends
        $FunctionalProvider<
          LlmProviderModelRepository,
          LlmProviderModelRepository,
          LlmProviderModelRepository
        >
    with $Provider<LlmProviderModelRepository> {
  /// Provider for LLM provider model repository
  const LlmProviderModelRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'llmProviderModelRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$llmProviderModelRepositoryHash();

  @$internal
  @override
  $ProviderElement<LlmProviderModelRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LlmProviderModelRepository create(Ref ref) {
    return llmProviderModelRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LlmProviderModelRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LlmProviderModelRepository>(value),
    );
  }
}

String _$llmProviderModelRepositoryHash() =>
    r'4de547ac186d74c64d828f90d249d7a710d75994';

/// Provider for available LLM models (enabled, non-archived)
/// Returns all enabled models across all providers

@ProviderFor(availableLlmModels)
const availableLlmModelsProvider = AvailableLlmModelsProvider._();

/// Provider for available LLM models (enabled, non-archived)
/// Returns all enabled models across all providers

final class AvailableLlmModelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LlmProviderModel>>,
          List<LlmProviderModel>,
          FutureOr<List<LlmProviderModel>>
        >
    with
        $FutureModifier<List<LlmProviderModel>>,
        $FutureProvider<List<LlmProviderModel>> {
  /// Provider for available LLM models (enabled, non-archived)
  /// Returns all enabled models across all providers
  const AvailableLlmModelsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableLlmModelsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableLlmModelsHash();

  @$internal
  @override
  $FutureProviderElement<List<LlmProviderModel>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LlmProviderModel>> create(Ref ref) {
    return availableLlmModels(ref);
  }
}

String _$availableLlmModelsHash() =>
    r'c34fed8059ba73683e7daa911b45bf7d842288df';

/// Provider for the currently selected LLM model ID
/// This is local state (not persisted), used when launching translation batches
/// keepAlive prevents the state from being disposed when there are no listeners

@ProviderFor(SelectedLlmModel)
const selectedLlmModelProvider = SelectedLlmModelProvider._();

/// Provider for the currently selected LLM model ID
/// This is local state (not persisted), used when launching translation batches
/// keepAlive prevents the state from being disposed when there are no listeners
final class SelectedLlmModelProvider
    extends $NotifierProvider<SelectedLlmModel, String?> {
  /// Provider for the currently selected LLM model ID
  /// This is local state (not persisted), used when launching translation batches
  /// keepAlive prevents the state from being disposed when there are no listeners
  const SelectedLlmModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedLlmModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedLlmModelHash();

  @$internal
  @override
  SelectedLlmModel create() => SelectedLlmModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedLlmModelHash() => r'188d4f5b67d00e0f51b93af14a0d0ef8af221347';

/// Provider for the currently selected LLM model ID
/// This is local state (not persisted), used when launching translation batches
/// keepAlive prevents the state from being disposed when there are no listeners

abstract class _$SelectedLlmModel extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
