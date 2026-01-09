/// State for editing/creating a compilation.
///
/// Contains all the form state and compilation progress information
/// used by the compilation editor screen.
class CompilationEditorState {
  final String? compilationId;
  final String name;
  final String prefix;
  final String packName;
  final String? selectedLanguageId;
  final Set<String> selectedProjectIds;
  final bool isCompiling;
  final bool isCancelled;
  final double progress;
  final String? currentStep;
  final String? errorMessage;
  final String? successMessage;
  final bool generatePackImage;

  const CompilationEditorState({
    this.compilationId,
    this.name = '',
    this.prefix = '',
    this.packName = 'my_pack',
    this.selectedLanguageId,
    this.selectedProjectIds = const {},
    this.isCompiling = false,
    this.isCancelled = false,
    this.progress = 0.0,
    this.currentStep,
    this.errorMessage,
    this.successMessage,
    this.generatePackImage = true,
  });

  /// Generate default prefix based on language code.
  static String defaultPrefixForLanguage(String languageCode) {
    return '!!!!!!!!!!_${languageCode}_compilation_twmt_';
  }

  CompilationEditorState copyWith({
    String? compilationId,
    String? name,
    String? prefix,
    String? packName,
    String? selectedLanguageId,
    Set<String>? selectedProjectIds,
    bool? isCompiling,
    bool? isCancelled,
    double? progress,
    String? currentStep,
    String? errorMessage,
    String? successMessage,
    bool? generatePackImage,
  }) {
    return CompilationEditorState(
      compilationId: compilationId ?? this.compilationId,
      name: name ?? this.name,
      prefix: prefix ?? this.prefix,
      packName: packName ?? this.packName,
      selectedLanguageId: selectedLanguageId ?? this.selectedLanguageId,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      isCompiling: isCompiling ?? this.isCompiling,
      isCancelled: isCancelled ?? this.isCancelled,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      errorMessage: errorMessage,
      successMessage: successMessage,
      generatePackImage: generatePackImage ?? this.generatePackImage,
    );
  }

  bool get isEditing => compilationId != null;

  /// Full pack filename with lowercase enforced.
  String get fullPackName => '$prefix$packName.pack'.toLowerCase();

  bool get canSave =>
      name.isNotEmpty &&
      prefix.isNotEmpty &&
      packName.isNotEmpty &&
      selectedLanguageId != null &&
      selectedProjectIds.isNotEmpty &&
      !isCompiling;

  bool get canCompile => canSave && !isCompiling;
}
