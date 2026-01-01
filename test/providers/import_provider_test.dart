import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/providers/import_export/import_provider.dart';

void main() {
  group('ImportProgressState', () {
    test('initial state has correct defaults', () {
      const state = ImportProgressState();

      expect(state.isImporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });

    test('copyWith creates new state with updated values', () {
      const state = ImportProgressState();

      final newState = state.copyWith(
        isImporting: true,
        current: 50,
        total: 100,
      );

      expect(newState.isImporting, isTrue);
      expect(newState.current, 50);
      expect(newState.total, 100);
    });

    test('progress calculates correctly', () {
      const state = ImportProgressState(
        isImporting: true,
        current: 25,
        total: 100,
      );

      expect(state.progress, 0.25);
    });

    test('progress returns 0 when total is 0', () {
      const state = ImportProgressState(
        isImporting: true,
        current: 0,
        total: 0,
      );

      expect(state.progress, 0.0);
    });

    test('percentage calculates correctly', () {
      const state = ImportProgressState(
        isImporting: true,
        current: 75,
        total: 100,
      );

      expect(state.percentage, 75);
    });

    test('percentage rounds correctly', () {
      const state = ImportProgressState(
        isImporting: true,
        current: 33,
        total: 100,
      );

      expect(state.percentage, 33);
    });
  });

  group('ImportSettingsStateNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has CSV format and empty IDs', () {
      final state = container.read(importSettingsStateProvider);

      expect(state.format, ImportFormat.csv);
      expect(state.projectId, '');
      expect(state.targetLanguageId, '');
    });

    test('update replaces entire settings', () {
      const newSettings = ImportSettings(
        format: ImportFormat.json,
        projectId: 'project-123',
        targetLanguageId: 'lang-456',
        encoding: 'utf-16',
      );

      container.read(importSettingsStateProvider.notifier).update(newSettings);

      final state = container.read(importSettingsStateProvider);

      expect(state.format, ImportFormat.json);
      expect(state.projectId, 'project-123');
      expect(state.targetLanguageId, 'lang-456');
      expect(state.encoding, 'utf-16');
    });

    test('updateFormat changes only format', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateFormat(ImportFormat.excel);

      final state = container.read(importSettingsStateProvider);

      expect(state.format, ImportFormat.excel);
      expect(state.projectId, '');
    });

    test('updateProjectId changes only project ID', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateProjectId('new-project');

      final state = container.read(importSettingsStateProvider);

      expect(state.projectId, 'new-project');
      expect(state.format, ImportFormat.csv);
    });

    test('updateTargetLanguageId changes only language ID', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateTargetLanguageId('fr');

      final state = container.read(importSettingsStateProvider);

      expect(state.targetLanguageId, 'fr');
    });

    test('updateEncoding changes only encoding', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateEncoding('utf-16');

      final state = container.read(importSettingsStateProvider);

      expect(state.encoding, 'utf-16');
    });

    test('updateHasHeaderRow changes only header row flag', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateHasHeaderRow(false);

      final state = container.read(importSettingsStateProvider);

      expect(state.hasHeaderRow, isFalse);
    });

    test('updateColumnMapping changes only column mapping', () {
      final mapping = {
        'col1': ImportColumn.key,
        'col2': ImportColumn.sourceText,
      };

      container
          .read(importSettingsStateProvider.notifier)
          .updateColumnMapping(mapping);

      final state = container.read(importSettingsStateProvider);

      expect(state.columnMapping, mapping);
    });

    test('updateConflictStrategy changes only strategy', () {
      container
          .read(importSettingsStateProvider.notifier)
          .updateConflictStrategy(ConflictResolutionStrategy.overwrite);

      final state = container.read(importSettingsStateProvider);

      expect(state.conflictStrategy, ConflictResolutionStrategy.overwrite);
    });

    test('reset returns to initial state', () {
      final notifier = container.read(importSettingsStateProvider.notifier);

      notifier.updateFormat(ImportFormat.json);
      notifier.updateProjectId('project-123');
      notifier.updateTargetLanguageId('fr');

      notifier.reset();

      final state = container.read(importSettingsStateProvider);

      expect(state.format, ImportFormat.csv);
      expect(state.projectId, '');
      expect(state.targetLanguageId, '');
    });
  });

  group('ImportPreviewDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is null', () {
      final state = container.read(importPreviewDataProvider);

      expect(state, isNull);
    });

    test('clear sets state to null', () {
      container.read(importPreviewDataProvider.notifier).clear();

      final state = container.read(importPreviewDataProvider);

      expect(state, isNull);
    });
  });

  group('ImportConflictsDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty list', () {
      final state = container.read(importConflictsDataProvider);

      expect(state, isEmpty);
    });

    test('clear sets state to empty list', () {
      container.read(importConflictsDataProvider.notifier).clear();

      final state = container.read(importConflictsDataProvider);

      expect(state, isEmpty);
    });
  });

  group('ConflictResolutionsDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has empty resolutions', () {
      final state = container.read(conflictResolutionsDataProvider);

      expect(state.resolutions, isEmpty);
      expect(state.defaultResolution, isNull);
    });

    test('setResolution adds resolution for key', () {
      container
          .read(conflictResolutionsDataProvider.notifier)
          .setResolution('key1', ConflictResolution.useImported);

      final state = container.read(conflictResolutionsDataProvider);

      expect(state.resolutions['key1'], ConflictResolution.useImported);
    });

    test('setResolution can update existing resolution', () {
      final notifier = container.read(conflictResolutionsDataProvider.notifier);

      notifier.setResolution('key1', ConflictResolution.keepExisting);
      notifier.setResolution('key1', ConflictResolution.useImported);

      final state = container.read(conflictResolutionsDataProvider);

      expect(state.resolutions['key1'], ConflictResolution.useImported);
    });

    test('setResolution preserves other resolutions', () {
      final notifier = container.read(conflictResolutionsDataProvider.notifier);

      notifier.setResolution('key1', ConflictResolution.keepExisting);
      notifier.setResolution('key2', ConflictResolution.useImported);

      final state = container.read(conflictResolutionsDataProvider);

      expect(state.resolutions['key1'], ConflictResolution.keepExisting);
      expect(state.resolutions['key2'], ConflictResolution.useImported);
    });

    test('setDefaultResolution updates default', () {
      container
          .read(conflictResolutionsDataProvider.notifier)
          .setDefaultResolution(ConflictResolution.merge);

      final state = container.read(conflictResolutionsDataProvider);

      expect(state.defaultResolution, ConflictResolution.merge);
    });

    test('clear resets to initial state', () {
      final notifier = container.read(conflictResolutionsDataProvider.notifier);

      notifier.setResolution('key1', ConflictResolution.keepExisting);
      notifier.setDefaultResolution(ConflictResolution.merge);

      notifier.clear();

      final state = container.read(conflictResolutionsDataProvider);

      expect(state.resolutions, isEmpty);
      expect(state.defaultResolution, isNull);
    });
  });

  group('ImportProgressNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is not importing', () {
      final state = container.read(importProgressProvider);

      expect(state.isImporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });

    test('start sets importing state with total', () {
      container.read(importProgressProvider.notifier).start(100);

      final state = container.read(importProgressProvider);

      expect(state.isImporting, isTrue);
      expect(state.current, 0);
      expect(state.total, 100);
    });

    test('update changes current value', () {
      final notifier = container.read(importProgressProvider.notifier);
      notifier.start(100);
      notifier.update(50);

      final state = container.read(importProgressProvider);

      expect(state.current, 50);
      expect(state.isImporting, isTrue);
    });

    test('complete sets isImporting to false', () {
      final notifier = container.read(importProgressProvider.notifier);
      notifier.start(100);
      notifier.update(100);
      notifier.complete();

      final state = container.read(importProgressProvider);

      expect(state.isImporting, isFalse);
    });

    test('reset returns to initial state', () {
      final notifier = container.read(importProgressProvider.notifier);
      notifier.start(100);
      notifier.update(50);

      notifier.reset();

      final state = container.read(importProgressProvider);

      expect(state.isImporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });
  });

  group('ImportResultDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is null', () {
      final state = container.read(importResultDataProvider);

      expect(state, isNull);
    });

    test('clear sets state to null', () {
      container.read(importResultDataProvider.notifier).clear();

      final state = container.read(importResultDataProvider);

      expect(state, isNull);
    });
  });

  group('ConflictResolutions model', () {
    test('getResolution returns specific resolution when exists', () {
      final resolutions = const ConflictResolutions(
        resolutions: {
          'key1': ConflictResolution.keepExisting,
          'key2': ConflictResolution.useImported,
        },
      );

      expect(resolutions.getResolution('key1'), ConflictResolution.keepExisting);
      expect(resolutions.getResolution('key2'), ConflictResolution.useImported);
    });

    test('getResolution returns default when key not found', () {
      final resolutions = const ConflictResolutions(
        resolutions: {'key1': ConflictResolution.keepExisting},
        defaultResolution: ConflictResolution.merge,
      );

      expect(resolutions.getResolution('unknown'), ConflictResolution.merge);
    });

    test('getResolution returns null when no default and key not found', () {
      const resolutions = ConflictResolutions(
        resolutions: {'key1': ConflictResolution.keepExisting},
      );

      expect(resolutions.getResolution('unknown'), isNull);
    });

    test('setResolution creates new instance with updated resolution', () {
      const original = ConflictResolutions();

      final updated = original.setResolution('key1', ConflictResolution.merge);

      expect(original.resolutions, isEmpty);
      expect(updated.resolutions['key1'], ConflictResolution.merge);
    });
  });

  group('ImportConflict model', () {
    test('isResolved returns true when resolution is set', () {
      const conflict = ImportConflict(
        key: 'test-key',
        existingData: ConflictTranslation(translatedText: 'existing'),
        importedData: ConflictTranslation(translatedText: 'imported'),
        resolution: ConflictResolution.useImported,
      );

      expect(conflict.isResolved, isTrue);
    });

    test('isResolved returns false when resolution is null', () {
      const conflict = ImportConflict(
        key: 'test-key',
        existingData: ConflictTranslation(translatedText: 'existing'),
        importedData: ConflictTranslation(translatedText: 'imported'),
      );

      expect(conflict.isResolved, isFalse);
    });

    test('copyWith creates new conflict with updated values', () {
      const conflict = ImportConflict(
        key: 'test-key',
        existingData: ConflictTranslation(translatedText: 'existing'),
        importedData: ConflictTranslation(translatedText: 'imported'),
      );

      final resolved = conflict.copyWith(
        resolution: ConflictResolution.keepExisting,
      );

      expect(conflict.resolution, isNull);
      expect(resolved.resolution, ConflictResolution.keepExisting);
      expect(resolved.key, 'test-key');
    });
  });

  group('ImportSettings model', () {
    test('default values are correct', () {
      const settings = ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'en',
      );

      expect(settings.encoding, 'utf-8');
      expect(settings.hasHeaderRow, isTrue);
      expect(settings.columnMapping, isEmpty);
      expect(settings.conflictStrategy, ConflictResolutionStrategy.skipExisting);
    });

    test('copyWith preserves unspecified values', () {
      const settings = ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'en',
        encoding: 'utf-16',
      );

      final updated = settings.copyWith(projectId: 'proj-2');

      expect(updated.format, ImportFormat.csv);
      expect(updated.projectId, 'proj-2');
      expect(updated.targetLanguageId, 'en');
      expect(updated.encoding, 'utf-16');
    });
  });

  group('ImportValidationOptions model', () {
    test('default values are all true', () {
      const options = ImportValidationOptions();

      expect(options.checkDuplicates, isTrue);
      expect(options.validateColumns, isTrue);
      expect(options.warnSourceMismatch, isTrue);
      expect(options.validateLanguage, isTrue);
    });

    test('copyWith updates specified values', () {
      const options = ImportValidationOptions();

      final updated = options.copyWith(
        checkDuplicates: false,
        validateColumns: false,
      );

      expect(updated.checkDuplicates, isFalse);
      expect(updated.validateColumns, isFalse);
      expect(updated.warnSourceMismatch, isTrue);
      expect(updated.validateLanguage, isTrue);
    });
  });

  group('ConflictTranslation model', () {
    test('creates with all fields', () {
      final translation = ConflictTranslation(
        sourceText: 'Hello',
        translatedText: 'Bonjour',
        status: 'translated',
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        changedBy: 'user',
        notes: 'Verified',
      );

      expect(translation.sourceText, 'Hello');
      expect(translation.translatedText, 'Bonjour');
      expect(translation.status, 'translated');
      expect(translation.changedBy, 'user');
      expect(translation.notes, 'Verified');
    });

    test('copyWith updates specified fields', () {
      const translation = ConflictTranslation(
        sourceText: 'Hello',
        translatedText: 'Bonjour',
      );

      final updated = translation.copyWith(
        translatedText: 'Salut',
        status: 'reviewed',
      );

      expect(updated.sourceText, 'Hello');
      expect(updated.translatedText, 'Salut');
      expect(updated.status, 'reviewed');
    });
  });
}
