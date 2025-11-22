import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart'
    as import_models;
import 'package:twmt/features/import_export/models/import_preview.dart';
import 'package:twmt/features/import_export/models/import_result.dart';
import 'package:twmt/features/import_export/services/import_export_service.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/service_locator.dart';

part 'import_provider.g.dart';

/// Current import settings
@riverpod
class ImportSettingsState extends _$ImportSettingsState {
  @override
  import_models.ImportSettings build() => const import_models.ImportSettings(
        format: import_models.ImportFormat.csv,
        projectId: '',
        targetLanguageId: '',
      );

  void update(import_models.ImportSettings settings) {
    state = settings;
  }

  void updateFormat(import_models.ImportFormat format) {
    state = state.copyWith(format: format);
  }

  void updateProjectId(String projectId) {
    state = state.copyWith(projectId: projectId);
  }

  void updateTargetLanguageId(String languageId) {
    state = state.copyWith(targetLanguageId: languageId);
  }

  void updateEncoding(String encoding) {
    state = state.copyWith(encoding: encoding);
  }

  void updateHasHeaderRow(bool hasHeader) {
    state = state.copyWith(hasHeaderRow: hasHeader);
  }

  void updateColumnMapping(Map<String, import_models.ImportColumn> mapping) {
    state = state.copyWith(columnMapping: mapping);
  }

  void updateConflictStrategy(import_models.ConflictResolutionStrategy strategy) {
    state = state.copyWith(conflictStrategy: strategy);
  }

  void reset() {
    state = const import_models.ImportSettings(
      format: import_models.ImportFormat.csv,
      projectId: '',
      targetLanguageId: '',
    );
  }
}

/// Import preview data
@riverpod
class ImportPreviewData extends _$ImportPreviewData {
  @override
  ImportPreview? build() => null;

  Future<void> loadPreview(String filePath, import_models.ImportSettings settings) async {
    state = null;

    final service = ImportExportService(
      ServiceLocator.get<IFileService>(),
      ServiceLocator.get<TranslationUnitRepository>(),
      ServiceLocator.get<TranslationVersionRepository>(),
    );

    final result = await service.previewImport(filePath, settings);

    result.when(
      ok: (preview) => state = preview,
      err: (error) => throw error,
    );
  }

  void clear() {
    state = null;
  }
}

/// Import conflicts
@riverpod
class ImportConflictsData extends _$ImportConflictsData {
  @override
  List<ImportConflict> build() => [];

  Future<void> detectConflicts(
    ImportPreview preview,
    import_models.ImportSettings settings,
  ) async {
    state = [];

    final service = ImportExportService(
      ServiceLocator.get<IFileService>(),
      ServiceLocator.get<TranslationUnitRepository>(),
      ServiceLocator.get<TranslationVersionRepository>(),
    );

    final result = await service.detectConflicts(preview, settings);

    result.when(
      ok: (conflicts) => state = conflicts,
      err: (error) => throw error,
    );
  }

  void clear() {
    state = [];
  }
}

/// Conflict resolutions
@riverpod
class ConflictResolutionsData extends _$ConflictResolutionsData {
  @override
  ConflictResolutions build() => const ConflictResolutions();

  void setResolution(String key, ConflictResolution resolution) {
    state = state.setResolution(key, resolution);
  }

  void setDefaultResolution(ConflictResolution resolution) {
    state = state.copyWith(defaultResolution: resolution);
  }

  void clear() {
    state = const ConflictResolutions();
  }
}

/// Import progress state
@riverpod
class ImportProgress extends _$ImportProgress {
  @override
  ImportProgressState build() => const ImportProgressState();

  void start(int total) {
    state = ImportProgressState(
      isImporting: true,
      current: 0,
      total: total,
    );
  }

  void update(int current) {
    state = state.copyWith(current: current);
  }

  void complete() {
    state = state.copyWith(isImporting: false);
  }

  void reset() {
    state = const ImportProgressState();
  }
}

/// Import results
@riverpod
class ImportResultData extends _$ImportResultData {
  @override
  ImportResult? build() => null;

  Future<void> executeImport(
    String filePath,
    import_models.ImportSettings settings,
    ConflictResolutions resolutions,
  ) async {
    state = null;

    final progressNotifier = ref.read(importProgressProvider.notifier);
    progressNotifier.start(100);

    final service = ImportExportService(
      ServiceLocator.get<IFileService>(),
      ServiceLocator.get<TranslationUnitRepository>(),
      ServiceLocator.get<TranslationVersionRepository>(),
    );

    final result = await service.executeImport(
      filePath,
      settings,
      resolutions,
      onProgress: (current, total) {
        progressNotifier.update(current);
      },
    );

    result.when(
      ok: (importResult) {
        state = importResult;
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

/// Import validation result
@riverpod
Future<ImportValidationResult> importValidation(
  Ref ref, {
  required ImportPreview preview,
  required import_models.ImportSettings settings,
}) async {
  final service = ImportExportService(
    ServiceLocator.get<IFileService>(),
    ServiceLocator.get<TranslationUnitRepository>(),
    ServiceLocator.get<TranslationVersionRepository>(),
  );

  final result = await service.validateImport(preview, settings);

  return result.when(
    ok: (validation) => validation,
    err: (error) => throw error,
  );
}

/// Import progress state model
class ImportProgressState {
  final bool isImporting;
  final int current;
  final int total;

  const ImportProgressState({
    this.isImporting = false,
    this.current = 0,
    this.total = 0,
  });

  double get progress => total > 0 ? current / total : 0.0;
  int get percentage => (progress * 100).round();

  ImportProgressState copyWith({
    bool? isImporting,
    int? current,
    int? total,
  }) {
    return ImportProgressState(
      isImporting: isImporting ?? this.isImporting,
      current: current ?? this.current,
      total: total ?? this.total,
    );
  }
}

