import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/import_export_service.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for the export filtering bug: `executeExport`/`previewExport`
/// previously called `getAll()` and ignored `projectId`, `targetLanguageId` and
/// `filterOptions`, leaking every project's/language's translations into a
/// single export. These tests pin the scoped + filtered behavior.
void main() {
  late Database db;
  late ImportExportService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();

    final versionRepo = TranslationVersionRepository();
    final unitRepo = TranslationUnitRepository();
    final projectLanguageRepo = ProjectLanguageRepository();
    final historyRepo = TranslationVersionHistoryRepository();
    final history = HistoryServiceImpl(
      historyRepository: historyRepo,
      versionRepository: versionRepo,
    );

    service = ImportExportService(
      FileServiceImpl(),
      unitRepo,
      versionRepo,
      history,
      projectLanguageRepo,
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Future<void> insertLanguage(String id, String code, String name) =>
        db.insert('languages', {
          'id': id,
          'code': code,
          'name': name,
          'native_name': name,
          'is_active': 1,
        });

    Future<void> insertProject(String id) => db.insert('projects', {
          'id': id,
          'name': 'Project $id',
          'game_installation_id': 'game-1',
          'created_at': now,
          'updated_at': now,
        });

    Future<void> insertProjectLanguage(
            String id, String projectId, String languageId) =>
        db.insert('project_languages', {
          'id': id,
          'project_id': projectId,
          'language_id': languageId,
          'status': 'pending',
          'progress_percent': 0,
          'created_at': now,
          'updated_at': now,
        });

    Future<void> insertUnit(String id, String projectId, String key,
            {String? context}) =>
        db.insert('translation_units', {
          'id': id,
          'project_id': projectId,
          'key': key,
          'source_text': 'source of $key',
          'context': context,
          'is_obsolete': 0,
          'created_at': now,
          'updated_at': now,
        });

    Future<void> insertVersion(
            String id, String unitId, String projectLanguageId, String status,
            {String? text}) =>
        db.insert('translation_versions', {
          'id': id,
          'unit_id': unitId,
          'project_language_id': projectLanguageId,
          'translated_text': text,
          'is_manually_edited': 0,
          'status': status,
          'created_at': now,
          'updated_at': now,
        });

    await insertLanguage('lang_fr', 'fr', 'French');
    await insertLanguage('lang_de', 'de', 'German');

    await insertProject('proj-1');
    await insertProject('proj-2');

    await insertProjectLanguage('pl-fr', 'proj-1', 'lang_fr');
    await insertProjectLanguage('pl-de', 'proj-1', 'lang_de');
    await insertProjectLanguage('pl-fr2', 'proj-2', 'lang_fr');

    await insertUnit('u1', 'proj-1', 'KEY_1');
    await insertUnit('u2', 'proj-1', 'KEY_2', context: 'campaign/intro');
    await insertUnit('u3', 'proj-1', 'KEY_3');
    await insertUnit('u4', 'proj-1', 'KEY_4');
    await insertUnit('u5', 'proj-2', 'KEY_5');

    // proj-1 / French: 2 translated, 1 pending (untranslated).
    await insertVersion('v1', 'u1', 'pl-fr', 'translated', text: 'Bonjour');
    await insertVersion('v2', 'u2', 'pl-fr', 'translated', text: 'Monde');
    await insertVersion('v3', 'u3', 'pl-fr', 'pending');
    // proj-1 / German — must never appear in a French export.
    await insertVersion('v4', 'u4', 'pl-de', 'translated', text: 'Hallo');
    // proj-2 / French — must never appear in a proj-1 export.
    await insertVersion('v5', 'u5', 'pl-fr2', 'translated', text: 'Other');
  });

  tearDown(() => TestDatabase.close(db));

  ExportSettings settings({ExportFilterOptions? filter}) => ExportSettings(
        format: ExportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        filterOptions: filter ?? const ExportFilterOptions(),
      );

  test('export is scoped to the chosen project and target language', () async {
    final result = await service.previewExport(settings());
    expect(result.isOk, isTrue);
    // v1, v2, v3 — NOT v4 (German) and NOT v5 (other project).
    expect(result.value.totalRows, 3);
  });

  test('validatedOnly excludes non-translated versions', () async {
    final result = await service.previewExport(
      settings(filter: const ExportFilterOptions(validatedOnly: true)),
    );
    expect(result.isOk, isTrue);
    expect(result.value.totalRows, 2); // v3 (pending) dropped
  });

  test('translationsOnly excludes versions with empty target text', () async {
    final result = await service.previewExport(
      settings(filter: const ExportFilterOptions(translationsOnly: true)),
    );
    expect(result.isOk, isTrue);
    expect(result.value.totalRows, 2); // v3 has null translated_text
  });

  test('statusFilter keeps only the requested statuses', () async {
    final result = await service.previewExport(
      settings(filter: const ExportFilterOptions(statusFilter: ['pending'])),
    );
    expect(result.isOk, isTrue);
    expect(result.value.totalRows, 1); // only v3
  });

  test('contextFilter matches against the unit context', () async {
    final result = await service.previewExport(
      settings(filter: const ExportFilterOptions(contextFilter: 'campaign')),
    );
    expect(result.isOk, isTrue);
    expect(result.value.totalRows, 1); // only u2 has a campaign context
  });
}
