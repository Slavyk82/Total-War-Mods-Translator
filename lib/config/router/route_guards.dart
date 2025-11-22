import '../../repositories/project_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../services/service_locator.dart';

/// Route guards for validating navigation parameters
///
/// These guards validate that resources exist before navigating to detail views.
/// Instead of blocking navigation (bad UX), we allow navigation and show error in the screen.
class RouteGuards {
  /// Validate that a project exists
  static Future<String?> validateProjectExists(String projectId) async {
    try {
      final repository = ServiceLocator.get<ProjectRepository>();
      final result = await repository.getById(projectId);

      if (result.isErr) {
        return 'Project not found: $projectId';
      }

      return null; // Valid
    } catch (e) {
      return 'Error loading project: $e';
    }
  }

  /// Validate that a project language exists
  static Future<String?> validateProjectLanguageExists(
    String projectId,
    String languageId,
  ) async {
    try {
      final projectRepository = ServiceLocator.get<ProjectRepository>();
      final projectLanguageRepository = ServiceLocator.get<ProjectLanguageRepository>();

      // First check project exists
      final projectResult = await projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return 'Project not found: $projectId';
      }

      // Check language is configured for this project
      final languagesResult = await projectLanguageRepository.getByProject(projectId);
      if (languagesResult.isErr) {
        return 'Error loading project languages: ${languagesResult.error}';
      }

      final languages = languagesResult.value;
      final hasLanguage = languages.any((pl) => pl.languageId == languageId);

      if (!hasLanguage) {
        return 'Language $languageId not configured for this project';
      }

      return null; // Valid
    } catch (e) {
      return 'Error validating project language: $e';
    }
  }

  /// Validate mod ID (basic check - mod details are loaded in the screen)
  static String? validateModId(String modId) {
    if (modId.isEmpty) {
      return 'Mod ID cannot be empty';
    }
    return null; // Valid
  }
}

/// Redirect logic for route guards
///
/// Usage in GoRouter:
/// ```dart
/// redirect: (context, state) {
///   return RouteRedirects.requiresNoEmptyParams(state, ['projectId']);
/// }
/// ```
class RouteRedirects {
  /// Check for empty required parameters and redirect to error page if found
  static String? requiresNoEmptyParams(
    dynamic state,
    List<String> requiredParams,
  ) {
    for (final param in requiredParams) {
      final value = (state as dynamic).pathParameters[param];
      if (value == null || value.isEmpty) {
        return '/error?message=Missing required parameter: $param';
      }
    }
    return null; // No redirect needed
  }

  /// Redirect to home if not authenticated (future use)
  static String? requiresAuth(dynamic state, bool isAuthenticated) {
    if (!isAuthenticated) {
      return '/';
    }
    return null;
  }
}
