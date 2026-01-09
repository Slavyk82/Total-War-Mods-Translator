import '../../../models/domain/project.dart';

/// Project with translation statistics for a specific language.
///
/// Used in the compilation editor to display projects with their
/// translation progress for the selected target language.
class ProjectWithTranslationInfo {
  final Project project;
  final int totalUnits;
  final int translatedUnits;

  const ProjectWithTranslationInfo({
    required this.project,
    this.totalUnits = 0,
    this.translatedUnits = 0,
  });

  String get id => project.id;
  String get displayName => project.displayName;
  String? get imageUrl => project.imageUrl;

  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }
}
