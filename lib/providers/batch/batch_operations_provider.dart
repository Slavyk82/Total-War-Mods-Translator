import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'batch_operations_provider.g.dart';

/// State for batch operations (translate, validate, export, etc.)
class BatchOperationState {
  final bool isInProgress;
  final BatchOperationType? currentOperation;
  final int totalItems;
  final int processedItems;
  final int successCount;
  final int failureCount;
  final String? currentItem;
  final String? errorMessage;
  final DateTime? startedAt;

  const BatchOperationState({
    this.isInProgress = false,
    this.currentOperation,
    this.totalItems = 0,
    this.processedItems = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.currentItem,
    this.errorMessage,
    this.startedAt,
  });

  BatchOperationState copyWith({
    bool? isInProgress,
    BatchOperationType? currentOperation,
    int? totalItems,
    int? processedItems,
    int? successCount,
    int? failureCount,
    String? currentItem,
    String? errorMessage,
    DateTime? startedAt,
  }) {
    return BatchOperationState(
      isInProgress: isInProgress ?? this.isInProgress,
      currentOperation: currentOperation ?? this.currentOperation,
      totalItems: totalItems ?? this.totalItems,
      processedItems: processedItems ?? this.processedItems,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      currentItem: currentItem ?? this.currentItem,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  double get progress =>
      totalItems > 0 ? (processedItems / totalItems) : 0.0;

  int get remainingItems => totalItems - processedItems;

  bool get hasErrors => failureCount > 0;

  Duration? get elapsedTime =>
      startedAt != null ? DateTime.now().difference(startedAt!) : null;

  /// Estimate remaining time based on current progress
  Duration? get estimatedTimeRemaining {
    if (startedAt == null || processedItems == 0) return null;
    final elapsed = DateTime.now().difference(startedAt!);
    final avgTimePerItem = elapsed.inMilliseconds / processedItems;
    final remainingMs = avgTimePerItem * remainingItems;
    return Duration(milliseconds: remainingMs.round());
  }
}

/// Types of batch operations
enum BatchOperationType {
  translate,
  validate,
  export,
  applyGlossary,
  clearTranslations,
  deleteUnits,
  markAsValidated,
}

/// Provider for managing batch operation state
@riverpod
class BatchOperation extends _$BatchOperation {
  @override
  BatchOperationState build() {
    return const BatchOperationState();
  }

  /// Start a batch operation
  void start({
    required BatchOperationType operation,
    required int totalItems,
  }) {
    state = BatchOperationState(
      isInProgress: true,
      currentOperation: operation,
      totalItems: totalItems,
      processedItems: 0,
      successCount: 0,
      failureCount: 0,
      startedAt: DateTime.now(),
    );
  }

  /// Update progress
  void updateProgress({
    required int processedItems,
    required int successCount,
    required int failureCount,
    String? currentItem,
  }) {
    state = state.copyWith(
      processedItems: processedItems,
      successCount: successCount,
      failureCount: failureCount,
      currentItem: currentItem,
    );
  }

  /// Increment success count
  void incrementSuccess({String? currentItem}) {
    state = state.copyWith(
      processedItems: state.processedItems + 1,
      successCount: state.successCount + 1,
      currentItem: currentItem,
    );
  }

  /// Increment failure count
  void incrementFailure({String? currentItem, String? errorMessage}) {
    state = state.copyWith(
      processedItems: state.processedItems + 1,
      failureCount: state.failureCount + 1,
      currentItem: currentItem,
      errorMessage: errorMessage,
    );
  }

  /// Complete the operation
  void complete() {
    state = state.copyWith(
      isInProgress: false,
      currentItem: null,
    );
  }

  /// Cancel the operation
  void cancel() {
    state = const BatchOperationState();
  }

  /// Reset state
  void reset() {
    state = const BatchOperationState();
  }
}

/// State for batch translate dialog
class BatchTranslateState {
  final String? selectedProvider;
  final String? selectedModel;
  final String? qualityMode;
  final bool useGlossary;
  final bool useTranslationMemory;

  const BatchTranslateState({
    this.selectedProvider,
    this.selectedModel,
    this.qualityMode = 'balanced',
    this.useGlossary = true,
    this.useTranslationMemory = true,
  });

  BatchTranslateState copyWith({
    String? selectedProvider,
    String? selectedModel,
    String? qualityMode,
    bool? useGlossary,
    bool? useTranslationMemory,
  }) {
    return BatchTranslateState(
      selectedProvider: selectedProvider ?? this.selectedProvider,
      selectedModel: selectedModel ?? this.selectedModel,
      qualityMode: qualityMode ?? this.qualityMode,
      useGlossary: useGlossary ?? this.useGlossary,
      useTranslationMemory: useTranslationMemory ?? this.useTranslationMemory,
    );
  }
}

/// Provider for batch translate dialog state
@riverpod
class BatchTranslateConfig extends _$BatchTranslateConfig {
  @override
  BatchTranslateState build() {
    return const BatchTranslateState();
  }

  void setProvider(String provider) {
    state = state.copyWith(selectedProvider: provider);
  }

  void setModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  void setQualityMode(String mode) {
    state = state.copyWith(qualityMode: mode);
  }

  void setUseGlossary(bool value) {
    state = state.copyWith(useGlossary: value);
  }

  void setUseTranslationMemory(bool value) {
    state = state.copyWith(useTranslationMemory: value);
  }

  void reset() {
    state = const BatchTranslateState();
  }
}

/// Validation issue for batch validation
class ValidationIssue {
  final String unitKey;
  final String unitId;
  final String versionId;
  final ValidationSeverity severity;
  final String issueType;
  final String description;
  final String sourceText;
  final String translatedText;

  const ValidationIssue({
    required this.unitKey,
    required this.unitId,
    required this.versionId,
    required this.severity,
    required this.issueType,
    required this.description,
    required this.sourceText,
    required this.translatedText,
  });
}

/// Severity of validation issues
enum ValidationSeverity {
  error,
  warning,
}

/// State for batch validation results
class BatchValidationState {
  final List<ValidationIssue> issues;
  final int totalValidated;
  final int passedCount;
  final bool showOnlyErrors;
  final bool showOnlyWarnings;

  const BatchValidationState({
    this.issues = const [],
    this.totalValidated = 0,
    this.passedCount = 0,
    this.showOnlyErrors = false,
    this.showOnlyWarnings = false,
  });

  BatchValidationState copyWith({
    List<ValidationIssue>? issues,
    int? totalValidated,
    int? passedCount,
    bool? showOnlyErrors,
    bool? showOnlyWarnings,
  }) {
    return BatchValidationState(
      issues: issues ?? this.issues,
      totalValidated: totalValidated ?? this.totalValidated,
      passedCount: passedCount ?? this.passedCount,
      showOnlyErrors: showOnlyErrors ?? this.showOnlyErrors,
      showOnlyWarnings: showOnlyWarnings ?? this.showOnlyWarnings,
    );
  }

  int get errorCount =>
      issues.where((i) => i.severity == ValidationSeverity.error).length;

  int get warningCount =>
      issues.where((i) => i.severity == ValidationSeverity.warning).length;

  int get issuesFoundCount => issues.length;

  List<ValidationIssue> get filteredIssues {
    if (showOnlyErrors) {
      return issues.where((i) => i.severity == ValidationSeverity.error).toList();
    }
    if (showOnlyWarnings) {
      return issues.where((i) => i.severity == ValidationSeverity.warning).toList();
    }
    return issues;
  }
}

/// Provider for batch validation results
@riverpod
class BatchValidationResults extends _$BatchValidationResults {
  @override
  BatchValidationState build() {
    return const BatchValidationState();
  }

  void setResults({
    required List<ValidationIssue> issues,
    required int totalValidated,
    required int passedCount,
  }) {
    state = BatchValidationState(
      issues: issues,
      totalValidated: totalValidated,
      passedCount: passedCount,
    );
  }

  void toggleShowOnlyErrors() {
    state = state.copyWith(
      showOnlyErrors: !state.showOnlyErrors,
      showOnlyWarnings: false,
    );
  }

  void toggleShowOnlyWarnings() {
    state = state.copyWith(
      showOnlyWarnings: !state.showOnlyWarnings,
      showOnlyErrors: false,
    );
  }

  void reset() {
    state = const BatchValidationState();
  }
}
