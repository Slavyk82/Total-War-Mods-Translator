import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart'
    as export_models;
import 'package:twmt/features/import_export/models/export_result.dart';
import 'package:twmt/features/import_export/services/import_export_service.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/service_locator.dart';

part 'export_provider.g.dart';

/// Current export settings
@riverpod
class ExportSettingsState extends _$ExportSettingsState {
  @override
  export_models.ExportSettings build() => const export_models.ExportSettings(
        format: export_models.ExportFormat.csv,
        projectId: '',
        targetLanguageId: '',
      );

  void update(export_models.ExportSettings settings) {
    state = settings;
  }

  void updateFormat(export_models.ExportFormat format) {
    state = state.copyWith(format: format);
  }

  void updateProjectId(String projectId) {
    state = state.copyWith(projectId: projectId);
  }

  void updateTargetLanguageId(String languageId) {
    state = state.copyWith(targetLanguageId: languageId);
  }

  void updateColumns(List<export_models.ExportColumn> columns) {
    state = state.copyWith(columns: columns);
  }

  void toggleColumn(export_models.ExportColumn column) {
    final columns = List<export_models.ExportColumn>.from(state.columns);
    if (columns.contains(column)) {
      columns.remove(column);
    } else {
      columns.add(column);
    }
    state = state.copyWith(columns: columns);
  }

  void updateFilterOptions(export_models.ExportFilterOptions options) {
    state = state.copyWith(filterOptions: options);
  }

  void updateFormatOptions(export_models.ExportFormatOptions options) {
    state = state.copyWith(formatOptions: options);
  }

  void reset() {
    state = const export_models.ExportSettings(
      format: export_models.ExportFormat.csv,
      projectId: '',
      targetLanguageId: '',
    );
  }
}

/// Export preview data
@riverpod
class ExportPreviewData extends _$ExportPreviewData {
  @override
  ExportPreview? build() => null;

  Future<void> loadPreview(export_models.ExportSettings settings) async {
    state = null;

    final service = ImportExportService(
      ServiceLocator.get<IFileService>(),
      ServiceLocator.get<TranslationUnitRepository>(),
      ServiceLocator.get<TranslationVersionRepository>(),
    );

    final result = await service.previewExport(settings);

    result.when(
      ok: (preview) => state = preview,
      err: (error) => throw error,
    );
  }

  void clear() {
    state = null;
  }
}

/// Export progress state
@riverpod
class ExportProgress extends _$ExportProgress {
  @override
  ExportProgressState build() => const ExportProgressState();

  void start(int total) {
    state = ExportProgressState(
      isExporting: true,
      current: 0,
      total: total,
    );
  }

  void update(int current) {
    state = state.copyWith(current: current);
  }

  void complete() {
    state = state.copyWith(isExporting: false);
  }

  void reset() {
    state = const ExportProgressState();
  }
}

/// Export results
@riverpod
class ExportResultData extends _$ExportResultData {
  @override
  ExportResult? build() => null;

  Future<void> executeExport(
    export_models.ExportSettings settings,
    String outputPath,
  ) async {
    state = null;

    final progressNotifier = ref.read(exportProgressProvider.notifier);
    progressNotifier.start(100);

    final service = ImportExportService(
      ServiceLocator.get<IFileService>(),
      ServiceLocator.get<TranslationUnitRepository>(),
      ServiceLocator.get<TranslationVersionRepository>(),
    );

    final result = await service.executeExport(
      settings,
      outputPath,
      onProgress: (current, total) {
        progressNotifier.update(current);
      },
    );

    result.when(
      ok: (exportResult) {
        state = exportResult;
        progressNotifier.complete();
      },
      err: (error) {
        progressNotifier.complete();
        throw error;
      },
    );
  }

  void clear() {
    state = null;
  }
}

/// Export progress state model
class ExportProgressState {
  final bool isExporting;
  final int current;
  final int total;

  const ExportProgressState({
    this.isExporting = false,
    this.current = 0,
    this.total = 0,
  });

  double get progress => total > 0 ? current / total : 0.0;
  int get percentage => (progress * 100).round();

  ExportProgressState copyWith({
    bool? isExporting,
    int? current,
    int? total,
  }) {
    return ExportProgressState(
      isExporting: isExporting ?? this.isExporting,
      current: current ?? this.current,
      total: total ?? this.total,
    );
  }
}
