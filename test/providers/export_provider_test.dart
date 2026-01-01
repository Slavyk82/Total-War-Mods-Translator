import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/providers/import_export/export_provider.dart';

void main() {
  group('ExportProgressState', () {
    test('initial state has correct defaults', () {
      const state = ExportProgressState();

      expect(state.isExporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });

    test('copyWith creates new state with updated values', () {
      const state = ExportProgressState();

      final newState = state.copyWith(
        isExporting: true,
        current: 50,
        total: 100,
      );

      expect(newState.isExporting, isTrue);
      expect(newState.current, 50);
      expect(newState.total, 100);
    });

    test('progress calculates correctly', () {
      const state = ExportProgressState(
        isExporting: true,
        current: 25,
        total: 100,
      );

      expect(state.progress, 0.25);
    });

    test('progress returns 0 when total is 0', () {
      const state = ExportProgressState(
        isExporting: true,
        current: 0,
        total: 0,
      );

      expect(state.progress, 0.0);
    });

    test('percentage calculates correctly', () {
      const state = ExportProgressState(
        isExporting: true,
        current: 75,
        total: 100,
      );

      expect(state.percentage, 75);
    });

    test('percentage rounds correctly', () {
      const state = ExportProgressState(
        isExporting: true,
        current: 33,
        total: 100,
      );

      expect(state.percentage, 33);
    });

    test('copyWith preserves unspecified values', () {
      const state = ExportProgressState(
        isExporting: true,
        current: 50,
        total: 100,
      );

      final newState = state.copyWith(current: 75);

      expect(newState.isExporting, isTrue);
      expect(newState.current, 75);
      expect(newState.total, 100);
    });
  });

  group('ExportSettingsStateNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has CSV format and empty IDs', () {
      final state = container.read(exportSettingsStateProvider);

      expect(state.format, ExportFormat.csv);
      expect(state.projectId, '');
      expect(state.targetLanguageId, '');
    });

    test('update replaces entire settings', () {
      const newSettings = ExportSettings(
        format: ExportFormat.json,
        projectId: 'project-123',
        targetLanguageId: 'lang-456',
      );

      container.read(exportSettingsStateProvider.notifier).update(newSettings);

      final state = container.read(exportSettingsStateProvider);

      expect(state.format, ExportFormat.json);
      expect(state.projectId, 'project-123');
      expect(state.targetLanguageId, 'lang-456');
    });

    test('updateFormat changes only format', () {
      container
          .read(exportSettingsStateProvider.notifier)
          .updateFormat(ExportFormat.excel);

      final state = container.read(exportSettingsStateProvider);

      expect(state.format, ExportFormat.excel);
      expect(state.projectId, '');
    });

    test('updateProjectId changes only project ID', () {
      container
          .read(exportSettingsStateProvider.notifier)
          .updateProjectId('new-project');

      final state = container.read(exportSettingsStateProvider);

      expect(state.projectId, 'new-project');
      expect(state.format, ExportFormat.csv);
    });

    test('updateTargetLanguageId changes only language ID', () {
      container
          .read(exportSettingsStateProvider.notifier)
          .updateTargetLanguageId('de');

      final state = container.read(exportSettingsStateProvider);

      expect(state.targetLanguageId, 'de');
    });

    test('updateColumns changes columns list', () {
      final columns = [
        ExportColumn.key,
        ExportColumn.sourceText,
        ExportColumn.notes,
      ];

      container
          .read(exportSettingsStateProvider.notifier)
          .updateColumns(columns);

      final state = container.read(exportSettingsStateProvider);

      expect(state.columns, columns);
    });

    test('toggleColumn adds column when not present', () {
      container
          .read(exportSettingsStateProvider.notifier)
          .toggleColumn(ExportColumn.notes);

      final state = container.read(exportSettingsStateProvider);

      expect(state.columns, contains(ExportColumn.notes));
    });

    test('toggleColumn removes column when present', () {
      container
          .read(exportSettingsStateProvider.notifier)
          .toggleColumn(ExportColumn.status);

      final state = container.read(exportSettingsStateProvider);

      expect(state.columns, isNot(contains(ExportColumn.status)));
    });

    test('toggleColumn can toggle same column on and off', () {
      final notifier = container.read(exportSettingsStateProvider.notifier);

      // Initial state should have status
      var state = container.read(exportSettingsStateProvider);
      expect(state.columns, contains(ExportColumn.status));

      // Toggle off
      notifier.toggleColumn(ExportColumn.status);
      state = container.read(exportSettingsStateProvider);
      expect(state.columns, isNot(contains(ExportColumn.status)));

      // Toggle on
      notifier.toggleColumn(ExportColumn.status);
      state = container.read(exportSettingsStateProvider);
      expect(state.columns, contains(ExportColumn.status));
    });

    test('updateFilterOptions changes filter options', () {
      const options = ExportFilterOptions(
        translationsOnly: true,
        validatedOnly: true,
      );

      container
          .read(exportSettingsStateProvider.notifier)
          .updateFilterOptions(options);

      final state = container.read(exportSettingsStateProvider);

      expect(state.filterOptions.translationsOnly, isTrue);
      expect(state.filterOptions.validatedOnly, isTrue);
    });

    test('updateFormatOptions changes format options', () {
      const options = ExportFormatOptions(
        includeHeader: false,
        prettyPrint: false,
        encoding: 'utf-16',
      );

      container
          .read(exportSettingsStateProvider.notifier)
          .updateFormatOptions(options);

      final state = container.read(exportSettingsStateProvider);

      expect(state.formatOptions.includeHeader, isFalse);
      expect(state.formatOptions.prettyPrint, isFalse);
      expect(state.formatOptions.encoding, 'utf-16');
    });

    test('reset returns to initial state', () {
      final notifier = container.read(exportSettingsStateProvider.notifier);

      notifier.updateFormat(ExportFormat.json);
      notifier.updateProjectId('project-123');
      notifier.updateTargetLanguageId('fr');

      notifier.reset();

      final state = container.read(exportSettingsStateProvider);

      expect(state.format, ExportFormat.csv);
      expect(state.projectId, '');
      expect(state.targetLanguageId, '');
    });
  });

  group('ExportPreviewDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is null', () {
      final state = container.read(exportPreviewDataProvider);

      expect(state, isNull);
    });

    test('clear sets state to null', () {
      container.read(exportPreviewDataProvider.notifier).clear();

      final state = container.read(exportPreviewDataProvider);

      expect(state, isNull);
    });
  });

  group('ExportProgressNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is not exporting', () {
      final state = container.read(exportProgressProvider);

      expect(state.isExporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });

    test('start sets exporting state with total', () {
      container.read(exportProgressProvider.notifier).start(100);

      final state = container.read(exportProgressProvider);

      expect(state.isExporting, isTrue);
      expect(state.current, 0);
      expect(state.total, 100);
    });

    test('update changes current value', () {
      final notifier = container.read(exportProgressProvider.notifier);
      notifier.start(100);
      notifier.update(50);

      final state = container.read(exportProgressProvider);

      expect(state.current, 50);
      expect(state.isExporting, isTrue);
    });

    test('complete sets isExporting to false', () {
      final notifier = container.read(exportProgressProvider.notifier);
      notifier.start(100);
      notifier.update(100);
      notifier.complete();

      final state = container.read(exportProgressProvider);

      expect(state.isExporting, isFalse);
    });

    test('reset returns to initial state', () {
      final notifier = container.read(exportProgressProvider.notifier);
      notifier.start(100);
      notifier.update(50);

      notifier.reset();

      final state = container.read(exportProgressProvider);

      expect(state.isExporting, isFalse);
      expect(state.current, 0);
      expect(state.total, 0);
    });
  });

  group('ExportResultDataNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is null', () {
      final state = container.read(exportResultDataProvider);

      expect(state, isNull);
    });

    test('clear sets state to null', () {
      container.read(exportResultDataProvider.notifier).clear();

      final state = container.read(exportResultDataProvider);

      expect(state, isNull);
    });
  });

  group('ExportSettings model', () {
    test('default values are correct', () {
      const settings = ExportSettings(
        format: ExportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'en',
      );

      expect(settings.columns, contains(ExportColumn.key));
      expect(settings.columns, contains(ExportColumn.sourceText));
      expect(settings.columns, contains(ExportColumn.targetText));
      expect(settings.columns, contains(ExportColumn.status));
      expect(settings.filterOptions.translationsOnly, isFalse);
      expect(settings.filterOptions.validatedOnly, isFalse);
      expect(settings.formatOptions.includeHeader, isTrue);
      expect(settings.formatOptions.prettyPrint, isTrue);
    });

    test('copyWith preserves unspecified values', () {
      const settings = ExportSettings(
        format: ExportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'en',
      );

      final updated = settings.copyWith(projectId: 'proj-2');

      expect(updated.format, ExportFormat.csv);
      expect(updated.projectId, 'proj-2');
      expect(updated.targetLanguageId, 'en');
    });
  });

  group('ExportFilterOptions model', () {
    test('default values are correct', () {
      const options = ExportFilterOptions();

      expect(options.statusFilter, isNull);
      expect(options.contextFilter, isNull);
      expect(options.translationsOnly, isFalse);
      expect(options.validatedOnly, isFalse);
      expect(options.createdAfter, isNull);
      expect(options.updatedAfter, isNull);
    });

    test('copyWith updates specified values', () {
      const options = ExportFilterOptions();

      final updated = options.copyWith(
        translationsOnly: true,
        statusFilter: ['translated', 'reviewed'],
      );

      expect(updated.translationsOnly, isTrue);
      expect(updated.statusFilter, ['translated', 'reviewed']);
      expect(updated.validatedOnly, isFalse);
    });
  });

  group('ExportFormatOptions model', () {
    test('default values are correct', () {
      const options = ExportFormatOptions();

      expect(options.includeHeader, isTrue);
      expect(options.prettyPrint, isTrue);
      expect(options.encoding, 'utf-8');
      expect(options.locPrefix, isNull);
    });

    test('copyWith updates specified values', () {
      const options = ExportFormatOptions();

      final updated = options.copyWith(
        includeHeader: false,
        encoding: 'utf-16',
        locPrefix: 'loc_',
      );

      expect(updated.includeHeader, isFalse);
      expect(updated.encoding, 'utf-16');
      expect(updated.locPrefix, 'loc_');
      expect(updated.prettyPrint, isTrue);
    });
  });

  group('ExportFormat enum', () {
    test('has all expected values', () {
      expect(ExportFormat.values, contains(ExportFormat.csv));
      expect(ExportFormat.values, contains(ExportFormat.json));
      expect(ExportFormat.values, contains(ExportFormat.excel));
      expect(ExportFormat.values, contains(ExportFormat.loc));
    });
  });

  group('ExportColumn enum', () {
    test('has all expected values', () {
      expect(ExportColumn.values, contains(ExportColumn.key));
      expect(ExportColumn.values, contains(ExportColumn.sourceText));
      expect(ExportColumn.values, contains(ExportColumn.targetText));
      expect(ExportColumn.values, contains(ExportColumn.status));
      expect(ExportColumn.values, contains(ExportColumn.notes));
      expect(ExportColumn.values, contains(ExportColumn.context));
      expect(ExportColumn.values, contains(ExportColumn.createdAt));
      expect(ExportColumn.values, contains(ExportColumn.updatedAt));
      expect(ExportColumn.values, contains(ExportColumn.changedBy));
    });
  });
}
