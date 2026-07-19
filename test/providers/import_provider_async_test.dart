import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/models/import_preview.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/import_export/import_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/history/i_history_service.dart';

/// Async-path tests for the import notifiers. They drive the real
/// [ImportExportService] (constructed inside each notifier) against a mocked
/// file service + repositories, exercising the notifier state machine and its
/// `err: throw` branches.
class MockFileService extends Mock implements IFileService {}

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class MockTranslationUnitRepository extends Mock
    implements TranslationUnitRepository {}

class MockHistoryService extends Mock implements IHistoryService {}

const _settings = ImportSettings(
  format: ImportFormat.csv,
  projectId: 'proj-1',
  targetLanguageId: 'fr',
);

ImportPreview _preview({String filePath = 'in.csv', String? contentHash}) =>
    ImportPreview(
      filePath: filePath,
      headers: const ['key', 'source_text'],
      previewRows: const [],
      totalRows: 0,
      fileSize: 0,
      encoding: 'utf-8',
      contentHash: contentHash,
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
    container.listen(importPreviewDataProvider, (_, _) {});
    container.listen(importConflictsDataProvider, (_, _) {});
    container.listen(importResultDataProvider, (_, _) {});
    container.listen(importProgressProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  void stubCsvOk() {
    when(() => mockFileService.importFromCsv(
          filePath: any(named: 'filePath'),
          hasHeader: any(named: 'hasHeader'),
          encoding: any(named: 'encoding'),
        )).thenAnswer((_) async => Ok<List<Map<String, String>>, ImportException>(
          [
            {'key': 'k1', 'source_text': 'Hello'},
          ],
        ));
  }

  void stubCsvErr() {
    when(() => mockFileService.importFromCsv(
          filePath: any(named: 'filePath'),
          hasHeader: any(named: 'hasHeader'),
          encoding: any(named: 'encoding'),
        )).thenAnswer((_) async => Err<List<Map<String, String>>, ImportException>(
          const ImportException('parse failed', 'in.csv', 'csv'),
        ));
  }

  group('ImportPreviewData.loadPreview', () {
    test('stores a preview parsed from a real file on success', () async {
      stubCsvOk();

      final tempDir = Directory.systemTemp.createTempSync('twmt_import_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final filePath = '${tempDir.path}${Platform.pathSeparator}in.csv';
      // previewImport calls File(filePath).length()/exists() + hashes content,
      // so the file must physically exist on disk.
      File(filePath).writeAsStringSync('key,source_text\nk1,Hello\n');

      await container
          .read(importPreviewDataProvider.notifier)
          .loadPreview(filePath, _settings);

      final preview = container.read(importPreviewDataProvider);
      expect(preview, isNotNull);
      expect(preview!.totalRows, 1);
      expect(preview.headers, contains('key'));
      expect(preview.contentHash, isNotNull);
    });

    test('throws when the file does not exist', () async {
      final missing =
          '${Directory.systemTemp.path}${Platform.pathSeparator}nope-does-not-exist.csv';

      await expectLater(
        container
            .read(importPreviewDataProvider.notifier)
            .loadPreview(missing, _settings),
        throwsA(isA<ServiceException>()),
      );

      expect(container.read(importPreviewDataProvider), isNull);
    });
  });

  group('ImportConflictsData.detectConflicts', () {
    test('returns no conflicts when no key column is mapped', () async {
      stubCsvOk();

      await container
          .read(importConflictsDataProvider.notifier)
          .detectConflicts(_preview(), _settings);

      expect(container.read(importConflictsDataProvider), isEmpty);
    });

    test('throws when the underlying file read fails', () async {
      stubCsvErr();

      await expectLater(
        container
            .read(importConflictsDataProvider.notifier)
            .detectConflicts(_preview(), _settings),
        throwsA(isA<ServiceException>()),
      );

      expect(container.read(importConflictsDataProvider), isEmpty);
    });
  });

  group('ImportResultData.executeImport', () {
    test('throws and completes progress when the file read fails', () async {
      stubCsvErr();

      await expectLater(
        container.read(importResultDataProvider.notifier).executeImport(
              'in.csv',
              _settings,
              const ConflictResolutions(),
            ),
        throwsA(isA<ServiceException>()),
      );

      // The err branch calls progressNotifier.complete() before rethrowing.
      expect(container.read(importProgressProvider).isImporting, isFalse);
      expect(container.read(importResultDataProvider), isNull);
    });
  });

  group('importValidationProvider', () {
    test('reports invalid when required column mappings are missing', () async {
      // Default settings have an empty columnMapping, so validation flags the
      // missing key + source/target columns without ever re-reading the file.
      final result = await container.read(
        importValidationProvider(preview: _preview(), settings: _settings)
            .future,
      );

      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
      expect(result.missingColumns, contains('key'));
    });
  });
}
