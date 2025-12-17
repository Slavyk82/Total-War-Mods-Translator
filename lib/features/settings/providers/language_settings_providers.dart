import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import '../../../models/domain/language.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../repositories/language_repository.dart';
import '../../../repositories/translation_memory_repository.dart';
import '../../../services/service_locator.dart';
import 'settings_providers.dart';

part 'language_settings_providers.g.dart';

/// Provider for language repository in settings context
@riverpod
LanguageRepository settingsLanguageRepository(Ref ref) {
  return ServiceLocator.get<LanguageRepository>();
}

/// State class for language settings
class LanguageSettingsState {
  final List<Language> languages;
  final String defaultLanguageCode;
  final bool isLoading;
  final String? error;

  const LanguageSettingsState({
    required this.languages,
    required this.defaultLanguageCode,
    this.isLoading = false,
    this.error,
  });

  LanguageSettingsState copyWith({
    List<Language>? languages,
    String? defaultLanguageCode,
    bool? isLoading,
    String? error,
  }) {
    return LanguageSettingsState(
      languages: languages ?? this.languages,
      defaultLanguageCode: defaultLanguageCode ?? this.defaultLanguageCode,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for managing language settings
@riverpod
class LanguageSettings extends _$LanguageSettings {
  @override
  Future<LanguageSettingsState> build() async {
    final repository = ref.read(settingsLanguageRepositoryProvider);
    final settingsService = ref.read(settingsServiceProvider);

    // Load all languages
    final languagesResult = await repository.getAll();
    final languages = languagesResult.when(
      ok: (list) => list,
      err: (_) => <Language>[],
    );

    // Load default language code from settings
    final defaultLanguageCode = await settingsService.getString(
      SettingsKeys.defaultTargetLanguage,
      defaultValue: SettingsKeys.defaultTargetLanguageValue,
    );

    return LanguageSettingsState(
      languages: languages,
      defaultLanguageCode: defaultLanguageCode,
    );
  }

  /// Set the default target language
  Future<(bool, String?)> setDefaultLanguage(String languageCode) async {
    final settingsService = ref.read(settingsServiceProvider);

    try {
      await settingsService.setString(
        SettingsKeys.defaultTargetLanguage,
        languageCode,
      );

      // Only update state if ref is still mounted
      if (ref.mounted) {
        // Update state
        final currentState = state.value;
        if (currentState != null) {
          state = AsyncValue.data(
            currentState.copyWith(defaultLanguageCode: languageCode),
          );
        }

        // Also invalidate the general settings provider
        ref.invalidate(generalSettingsProvider);
      }

      return (true, null);
    } catch (e) {
      return (false, 'Failed to set default language: $e');
    }
  }

  /// Add a new custom language
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> addCustomLanguage({
    required String code,
    required String name,
  }) async {
    final repository = ref.read(settingsLanguageRepositoryProvider);

    // Validate inputs
    if (code.trim().isEmpty) {
      return (false, 'Language code is required');
    }
    if (name.trim().isEmpty) {
      return (false, 'Language name is required');
    }

    // Check if code already exists
    final codeExistsResult = await repository.codeExists(code.trim().toLowerCase());
    if (codeExistsResult.isOk && codeExistsResult.unwrap()) {
      return (false, 'A language with code "$code" already exists');
    }

    // Create new language
    final newLanguage = Language(
      id: const Uuid().v4(),
      code: code.trim().toLowerCase(),
      name: name.trim(),
      nativeName: name.trim(), // Use name as native name for custom languages
      isActive: true,
      isCustom: true,
    );

    final insertResult = await repository.insert(newLanguage);

    return insertResult.when(
      ok: (_) {
        // Only invalidate if ref is still mounted
        if (ref.mounted) {
          ref.invalidateSelf();
          // Invalidate shared language providers so new language appears everywhere
          ref.invalidate(allLanguagesProvider);
          ref.invalidate(activeLanguagesProvider);
        }
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Delete a custom language
  ///
  /// Returns (success, errorMessage)
  /// Only custom languages (isCustom = true) can be deleted.
  /// This will also delete all translation memory entries associated with this language.
  Future<(bool, String?)> deleteLanguage(String languageId) async {
    final repository = ref.read(settingsLanguageRepositoryProvider);
    final tmRepository = ServiceLocator.get<TranslationMemoryRepository>();

    // First verify it's a custom language
    final languageResult = await repository.getById(languageId);
    if (languageResult.isErr) {
      return (false, 'Language not found');
    }

    final language = languageResult.unwrap();
    if (!language.isCustom) {
      return (false, 'System languages cannot be deleted');
    }

    // Check if this is the default language
    final currentState = state.value;
    if (currentState != null && currentState.defaultLanguageCode == language.code) {
      return (false, 'Cannot delete the default language. Please select a different default first.');
    }

    // Clean up translation memory entries referencing this language
    // This must be done before deleting the language due to foreign key constraints
    final tmCleanupResult = await tmRepository.deleteByLanguageId(languageId);
    if (tmCleanupResult.isErr) {
      return (false, 'Failed to clean up translation memory: ${tmCleanupResult.unwrapErr().message}');
    }

    final deleteResult = await repository.delete(languageId);

    return deleteResult.when(
      ok: (_) {
        // Only invalidate if ref is still mounted
        if (ref.mounted) {
          ref.invalidateSelf();
          // Invalidate shared language providers so language is removed everywhere
          ref.invalidate(allLanguagesProvider);
          ref.invalidate(activeLanguagesProvider);
        }
        return (true, null);
      },
      err: (error) {
        // Check for foreign key constraint error (language is used in projects)
        final errorMessage = error.message.toLowerCase();
        if (errorMessage.contains('foreign key') ||
            errorMessage.contains('constraint failed')) {
          return (
            false,
            'This language is used in one or more projects. '
                'Remove it from all projects before deleting.',
          );
        }
        return (false, error.message);
      },
    );
  }
}
