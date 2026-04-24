import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  group('EditorFilter — single-value severity filter', () {
    test('defaults to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilter, isNull);
      expect(state.hasActiveFilters, isFalse);
    });

    test('setSeverityFilter replaces the value and flips hasActiveFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilter(ValidationSeverity.error);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilter, ValidationSeverity.error);
      expect(state.hasActiveFilters, isTrue);
    });

    test('setSeverityFilter(null) clears severity', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setSeverityFilter(null);
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('clearFilters wipes severityFilter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilter(ValidationSeverity.warning);
      notifier.clearFilters();
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('dropping needsReview from status wipes severityFilter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilter(TranslationVersionStatus.needsReview);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setStatusFilter(TranslationVersionStatus.translated);
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('setStatusFilter(null) does not wipe severityFilter when status was not needsReview', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilter(TranslationVersionStatus.translated);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setStatusFilter(null);
      expect(container.read(editorFilterProvider).severityFilter,
          ValidationSeverity.error);
    });
  });
}
