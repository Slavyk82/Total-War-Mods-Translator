import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/import_export/export_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/history/i_history_service.dart';

/// Async-path tests for the export notifiers. These drive the real
/// [ImportExportService] (constructed inside the notifier) against mocked file
/// service + repositories so the notifier state machine — including the
/// `err: throw` branches and progress transitions — is exercised.
class MockFileService extends Mock implements IFileService {}

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class MockTranslationUnitRepository extends Mock
    implements TranslationUnitRepository {}

class MockHistoryService extends Mock implements IHistoryService {}

ProjectLanguage _projectLanguage() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return ProjectLanguage(
    id: 'pl-1',
    projectId: 'proj-1',
    languageId: 'fr',
    createdAt: now,
    updatedAt: now,
  );
}

const _settings = ExportSettings(
  format: ExportFormat.csv,
  projectId: 'proj-1',
  targetLanguageId: 'fr',
);

void main() {
  setUpAll(() {
    registerFallbackValue(<Map<String, String>>[]);
  });

  late MockFileService mockFileService;
  late MockProjectLanguageRepository mockProjectLangRepo;
  late MockTranslationVersionRepository mockVersionRepo;
  late MockTranslationUnitRepository mockUnitRepo;
  late MockHistoryService mockHistoryService;
  late ProviderContainer container;

  setUp(() {
    mockFileService = MockFileService();
    mockProjectLangRepo = MockProjectLanguageRepository();
    mockVersionRepo = MockTranslationVersionRepository();
    mockUnitRepo = MockTranslationUnitRepository();
    mockHistoryService = MockHistoryService();
    container = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(mockFileService),
      projectLanguageRepositoryProvider.overrideWithValue(mockProjectLangRepo),
      translationVersionRepositoryProvider.overrideWithValue(mockVersionRepo),
      translationUnitRepositoryProvider.overrideWithValue(mockUnitRepo),
      historyServiceProvider.overrideWithValue(mockHistoryService),
    ]);
    // These notifiers are autoDispose; keep them mounted for the whole test so
    // an async `state = ...` write does not land on a disposed Ref.
    container.listen(exportPreviewDataProvider, (_, _) {});
    container.listen(exportResultDataProvider, (_, _) {});
    container.listen(exportProgressProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  // Resolve project language + (empty) version set successfully.
  void stubEmptyVersions() {
    when(() => mockProjectLangRepo.getByProjectAndLanguage(any(), any()))
        .thenAnswer((_) async =>
            Ok<ProjectLanguage, TWMTDatabaseException>(_projectLanguage()));
    when(() => mockVersionRepo.getByProjectLanguage(any())).thenAnswer(
        (_) async =>
            Ok<List<TranslationVersion>, TWMTDatabaseException>([]));
  }

  group('ExportPreviewData.loadPreview', () {
    test('stores a preview on success', () async {
      stubEmptyVersions();

      await container
          .read(exportPreviewDataProvider.notifier)
          .loadPreview(_settings);

      final preview = container.read(exportPreviewDataProvider);
      expect(preview, isNotNull);
      expect(preview!.totalRows, 0);
      expect(preview.previewRows, isEmpty);
    });

    test('throws and leaves state null when the repository errors', () async {
      when(() => mockProjectLangRepo.getByProjectAndLanguage(any(), any()))
          .thenAnswer((_) async => Err<ProjectLanguage, TWMTDatabaseException>(
              const TWMTDatabaseException('db down')));

      await expectLater(
        container.read(exportPreviewDataProvider.notifier).loadPreview(_settings),
        throwsA(isA<ServiceException>()),
      );

      expect(container.read(exportPreviewDataProvider), isNull);
    });
  });

  group('ExportResultData.executeExport', () {
    test('writes a result and completes progress on success', () async {
      stubEmptyVersions();

      final tempDir = Directory.systemTemp.createTempSync('twmt_export_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}${Platform.pathSeparator}out.csv';
      // executeExport reads File(outputPath).length(), so the file must exist.
      File(outputPath).writeAsStringSync('key\nvalue\n');

      when(() => mockFileService.exportToCsv(
            data: any(named: 'data'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async => Ok<String, ExportException>(outputPath));

      await container
          .read(exportResultDataProvider.notifier)
          .executeExport(_settings, outputPath);

      final result = container.read(exportResultDataProvider);
      expect(result, isNotNull);
      expect(result!.rowCount, 0);
      expect(container.read(exportProgressProvider).isExporting, isFalse);
    });

    test('throws and completes progress when the repository errors', () async {
      when(() => mockProjectLangRepo.getByProjectAndLanguage(any(), any()))
          .thenAnswer((_) async => Err<ProjectLanguage, TWMTDatabaseException>(
              const TWMTDatabaseException('db down')));

      await expectLater(
        container
            .read(exportResultDataProvider.notifier)
            .executeExport(_settings, 'unused-output.csv'),
        throwsA(isA<ServiceException>()),
      );

      // The err branch calls progressNotifier.complete() before rethrowing.
      expect(container.read(exportProgressProvider).isExporting, isFalse);
      expect(container.read(exportResultDataProvider), isNull);
    });
  });
}
