import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  group('EditorFilter — severityFilters', () {
    test('defaults to empty set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilters, isEmpty);
      expect(state.hasActiveFilters, isFalse);
    });

    test('setSeverityFilters replaces the set and flips hasActiveFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilters({ValidationSeverity.error});
      final state = container.read(editorFilterProvider);
      expect(state.severityFilters, {ValidationSeverity.error});
      expect(state.hasActiveFilters, isTrue);
    });

    test('clearFilters wipes severityFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilters(
          {ValidationSeverity.error, ValidationSeverity.warning});
      notifier.clearFilters();
      expect(container.read(editorFilterProvider).severityFilters, isEmpty);
    });

    test('dropping needsReview from status wipes severityFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilters({TranslationVersionStatus.needsReview});
      notifier.setSeverityFilters({ValidationSeverity.error});
      notifier.setStatusFilters({TranslationVersionStatus.translated});
      expect(container.read(editorFilterProvider).severityFilters, isEmpty);
    });
  });
}
