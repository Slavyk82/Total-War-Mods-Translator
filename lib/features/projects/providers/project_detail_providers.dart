import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/language.dart';
import '../../../providers/shared/repository_providers.dart';

// Re-export shared repository providers for backward compatibility
export '../../../providers/shared/repository_providers.dart'
    show translationUnitRepositoryProvider, translationVersionRepositoryProvider;

/// Project language enriched with its [Language] record and per-language
/// translation counts. Used by the editor language switcher and by the
/// `openProjectEditor` helper that picks a default language on navigation.
class ProjectLanguageDetails {
  final ProjectLanguage projectLanguage;
  final Language language;
  final int totalUnits;
  final int translatedUnits;
  final int pendingUnits;
  final int needsReviewUnits;

  const ProjectLanguageDetails({
    required this.projectLanguage,
    required this.language,
    this.totalUnits = 0,
    this.translatedUnits = 0,
    this.pendingUnits = 0,
    this.needsReviewUnits = 0,
  });

  /// Calculate progress percentage based on actual translation counts.
  /// Only units with status = 'translated' count as complete.
  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }
}

/// Provider for project languages by project ID.
///
/// Uses batch fetching (getByIds) to avoid N+1 query pattern.
final projectLanguagesProvider = FutureProvider.family<List<ProjectLanguageDetails>, String>((ref, projectId) async {
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);

  final langResult = await projectLangRepo.getByProject(projectId);
  if (langResult.isErr) {
    throw Exception('Failed to load project languages');
  }

  final projectLanguages = langResult.unwrap();

  // Optimized: Batch fetch all languages in single query to avoid N+1 problem
  final languageIds = projectLanguages.map((pl) => pl.languageId).toList();
  final languagesResult = await langRepo.getByIds(languageIds);

  if (languagesResult.isErr) {
    throw Exception('Failed to load languages');
  }

  // Create lookup map for O(1) access
  final languagesMap = <String, Language>{};
  for (final lang in languagesResult.unwrap()) {
    languagesMap[lang.id] = lang;
  }

  // Build details list with fast lookups
  final List<ProjectLanguageDetails> languageDetails = [];
  for (final projLang in projectLanguages) {
    final language = languagesMap[projLang.languageId];
    if (language != null) {
      languageDetails.add(ProjectLanguageDetails(
        projectLanguage: projLang,
        language: language,
      ));
    }
  }

  return languageDetails;
});
