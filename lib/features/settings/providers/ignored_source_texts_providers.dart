import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/domain/ignored_source_text.dart';
import '../../../services/translation/ignored_source_text_service.dart';
import '../../../services/service_locator.dart';

part 'ignored_source_texts_providers.g.dart';

/// Provider for IgnoredSourceTextService
@riverpod
IgnoredSourceTextService ignoredSourceTextService(Ref ref) {
  return ServiceLocator.get<IgnoredSourceTextService>();
}

/// Notifier for managing ignored source texts
@riverpod
class IgnoredSourceTexts extends _$IgnoredSourceTexts {
  @override
  Future<List<IgnoredSourceText>> build() async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.getAll();
    return result.when(
      ok: (texts) => texts,
      err: (_) => [],
    );
  }

  /// Add a new ignored source text
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> addText(String sourceText) async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.add(sourceText);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        ref.invalidate(enabledIgnoredTextsCountProvider);
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Update an existing ignored source text
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> updateText(String id, String newSourceText) async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.update(id, newSourceText);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        ref.invalidate(enabledIgnoredTextsCountProvider);
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Delete an ignored source text
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> deleteText(String id) async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.delete(id);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        ref.invalidate(enabledIgnoredTextsCountProvider);
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Toggle an ignored source text's enabled status
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> toggleEnabled(String id) async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.toggleEnabled(id);

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        ref.invalidate(enabledIgnoredTextsCountProvider);
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }

  /// Reset to default values
  ///
  /// Returns (success, errorMessage)
  Future<(bool, String?)> resetToDefaults() async {
    final service = ref.read(ignoredSourceTextServiceProvider);
    final result = await service.resetToDefaults();

    return result.when(
      ok: (_) {
        ref.invalidateSelf();
        ref.invalidate(enabledIgnoredTextsCountProvider);
        return (true, null);
      },
      err: (error) => (false, error.message),
    );
  }
}

/// Provider for the count of enabled ignored source texts
@riverpod
Future<int> enabledIgnoredTextsCount(Ref ref) async {
  final service = ref.read(ignoredSourceTextServiceProvider);
  return service.getEnabledCount();
}
