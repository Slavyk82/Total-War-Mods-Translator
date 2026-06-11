import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/projects/project_initialization_service_impl.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';

import '../helpers/test_database.dart';

/// Fake extraction directory that does NOT exist on disk, so the service's
/// post-import cleanup (`Directory(...).exists()`) is a no-op.
final _fakeExtractDir =
    '${Directory.systemTemp.path}/twmt_init_savepoint_test_nonexistent';

final _fakeTsvPath = '$_fakeExtractDir/text/db/test_file.loc.tsv';

/// RPFM stub: reports a single extracted TSV file. Everything else is an
/// unexpected-path failure.
class _StubRpfmService implements IRpfmService {
  @override
  Stream<RpfmLogMessage> get logStream => const Stream.empty();

  @override
  Future<Result<RpfmExtractResult, RpfmServiceException>>
      extractLocalizationFilesAsTsv(
    String packFilePath, {
    String? outputDirectory,
    String? schemaPath,
  }) async {
    return Ok(RpfmExtractResult(
      packFilePath: packFilePath,
      outputDirectory: _fakeExtractDir,
      extractedFiles: [_fakeTsvPath],
      localizationFileCount: 1,
      totalSizeBytes: 0,
      durationMs: 0,
      timestamp: DateTime.now(),
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('IRpfmService.${invocation.memberName} '
          'should not be called by initializeProject in this test');
}

/// Parser stub: returns a caller-supplied list of entries for the single
/// extracted file.
class _StubLocalizationParser implements ILocalizationParser {
  _StubLocalizationParser(this._entries);

  final List<LocalizationEntry> _entries;

  @override
  Future<Result<LocalizationFile, FileServiceException>> parseFile({
    required String filePath,
    String encoding = 'utf-8',
    String? languageCode,
  }) async {
    return Ok(LocalizationFile(
      fileName: 'test_file.loc',
      filePath: filePath,
      languageCode: 'en',
      entries: _entries,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ILocalizationParser.${invocation.memberName} '
          'should not be called by initializeProject in this test');
}

/// Integration tests pinning the per-unit error tolerance of
/// [ProjectInitializationServiceImpl.initializeProject]: each unit (and its
/// per-language versions) is isolated behind a savepoint inside the per-file
/// transaction, so one bad row is skipped while the rest of the file commits
/// — the same contract addNewUnits pins in
/// add_new_units_transaction_test.dart.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Future<void> lang(String id, String code) => db.insert('languages', {
          'id': id,
          'code': code,
          'name': code,
          'native_name': code,
          'is_active': 1,
        });
    Future<void> project(String id) => db.insert('projects', {
          'id': id,
          'name': 'Project $id',
          'game_installation_id': 'game-1',
          'created_at': now,
          'updated_at': now,
        });
    Future<void> projectLanguage(String id, String projectId, String langId) =>
        db.insert('project_languages', {
          'id': id,
          'project_id': projectId,
          'language_id': langId,
          'status': 'pending',
          'progress_percent': 0,
          'created_at': now,
          'updated_at': now,
        });

    await lang('lang_en', 'en');
    await lang('lang_fr', 'fr');
    await project('P');
    await projectLanguage('pl_en', 'P', 'lang_en');
    await projectLanguage('pl_fr', 'P', 'lang_fr');
  });

  tearDown(() => TestDatabase.close(db));

  Future<int> count(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    return (rows.first.values.first as int?) ?? 0;
  }

  ProjectInitializationServiceImpl buildService(
      List<LocalizationEntry> entries) {
    return ProjectInitializationServiceImpl(
      rpfmService: _StubRpfmService(),
      locParser: _StubLocalizationParser(entries),
      unitRepository: TranslationUnitRepository(),
      languageRepository: ProjectLanguageRepository(),
      analysisCacheRepository: ModUpdateAnalysisCacheRepository(),
    );
  }

  test('success: each imported unit gets exactly one version per language',
      () async {
    final service = buildService(const [
      LocalizationEntry(key: 'KEY_1', value: 'src 1'),
      LocalizationEntry(key: 'KEY_2', value: 'src 2'),
    ]);

    final result = await service.initializeProject(
      projectId: 'P',
      packFilePath: 'C:/nonexistent/test.pack',
    );

    expect(result.isOk, isTrue);
    expect(result.value, 2);

    expect(
      await count('SELECT COUNT(*) FROM translation_units WHERE project_id = ?',
          ['P']),
      2,
    );
    expect(
      await count('''
        SELECT COUNT(*) FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
      ''', ['P']),
      4,
    );
  });

  test(
      'partial failure: the bad entry is rolled back, '
      'the rest of the file still commits', () async {
    // Force the version insert to fail for ONE specific unit (KEY_BAD) while
    // the others succeed. The per-unit savepoint must roll back KEY_BAD's
    // already-inserted unit row, skip it, and still commit the good units —
    // instead of losing the whole file's batch.
    await db.execute('''
      CREATE TRIGGER trg_test_fail_bad_unit
      BEFORE INSERT ON translation_versions
      WHEN (SELECT key FROM translation_units WHERE id = NEW.unit_id)
           = 'KEY_BAD'
      BEGIN
        SELECT RAISE(ABORT, 'forced test failure');
      END
    ''');

    final service = buildService(const [
      LocalizationEntry(key: 'KEY_GOOD_1', value: 'src 1'),
      LocalizationEntry(key: 'KEY_BAD', value: 'src bad'),
      LocalizationEntry(key: 'KEY_GOOD_2', value: 'src 2'),
    ]);

    final result = await service.initializeProject(
      projectId: 'P',
      packFilePath: 'C:/nonexistent/test.pack',
    );

    expect(result.isOk, isTrue);
    expect(result.value, 2, reason: 'only the two good units are counted');

    // The bad unit's row (inserted before its version failed) was rolled back.
    expect(
      await count(
          'SELECT COUNT(*) FROM translation_units WHERE project_id = ? AND key = ?',
          ['P', 'KEY_BAD']),
      0,
      reason: 'the failing unit must be rolled back by its savepoint',
    );

    // Both good units survive with a full version set (2 languages each).
    for (final key in ['KEY_GOOD_1', 'KEY_GOOD_2']) {
      expect(
        await count(
            'SELECT COUNT(*) FROM translation_units WHERE project_id = ? AND key = ?',
            ['P', key]),
        1,
        reason: 'unit $key must survive the sibling failure',
      );
      expect(
        await count('''
          SELECT COUNT(*) FROM translation_versions tv
          INNER JOIN translation_units tu ON tv.unit_id = tu.id
          WHERE tu.project_id = ? AND tu.key = ?
        ''', ['P', key]),
        2,
        reason: 'unit $key must keep a version for every project language',
      );
    }
  });
}
