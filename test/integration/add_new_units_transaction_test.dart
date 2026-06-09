import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';

import '../helpers/test_database.dart';

/// Stub RPFM/parser dependencies. [ModUpdateAnalysisService.addNewUnits] never
/// touches them, so any call is an unexpected-path failure.
class _StubRpfmService implements IRpfmService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('IRpfmService.${invocation.memberName} '
          'should not be called by addNewUnits');
}

class _StubLocalizationParser implements ILocalizationParser {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ILocalizationParser.${invocation.memberName} '
          'should not be called by addNewUnits');
}

/// A project-language repository that returns a caller-supplied list,
/// independent of the database. Used to inject a duplicate project_language id
/// so the second version insert for a unit violates the
/// UNIQUE(unit_id, project_language_id) constraint and forces a rollback.
class _StubLanguageRepository extends ProjectLanguageRepository {
  _StubLanguageRepository(this._languages);

  final List<ProjectLanguage> _languages;

  @override
  Future<Result<List<ProjectLanguage>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return Ok(_languages);
  }
}

/// Integration tests pinning the transactional behavior of
/// [ModUpdateAnalysisService.addNewUnits]: a unit and its per-language versions
/// must be inserted atomically. On success every unit has one version per
/// language; on a version-insert failure the unit is rolled back and not
/// counted.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    // FK enforcement stays off (as openMigrated leaves it) so seed rows don't
    // need the full FK graph — matching the existing integration tests. The
    // rollback path under test is driven by the UNIQUE(unit_id,
    // project_language_id) constraint, which fires regardless of FK enforcement.

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

  ModUpdateAnalysisService buildService({ProjectLanguageRepository? langRepo}) {
    return ModUpdateAnalysisService(
      rpfmService: _StubRpfmService(),
      locParser: _StubLocalizationParser(),
      unitRepository: TranslationUnitRepository(),
      versionRepository: TranslationVersionRepository(),
      languageRepository: langRepo ?? ProjectLanguageRepository(),
    );
  }

  ModUpdateAnalysis analysisWith(List<NewUnitData> units) => ModUpdateAnalysis(
        newUnitsCount: units.length,
        removedUnitsCount: 0,
        modifiedUnitsCount: 0,
        totalPackUnits: units.length,
        totalProjectUnits: 0,
        newUnitsData: units,
      );

  test('success: each added unit gets exactly one version per language',
      () async {
    final service = buildService();
    final result = await service.addNewUnits(
      projectId: 'P',
      analysis: analysisWith(const [
        NewUnitData(key: 'KEY_1', sourceText: 'src 1'),
        NewUnitData(key: 'KEY_2', sourceText: 'src 2'),
      ]),
    );

    expect(result.isOk, isTrue);
    expect(result.value, 2); // both units counted

    // Two units inserted.
    expect(
      await count('SELECT COUNT(*) FROM translation_units WHERE project_id = ?',
          ['P']),
      2,
    );

    // One version per (unit, language): 2 units x 2 languages = 4.
    expect(
      await count('''
        SELECT COUNT(*) FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
      ''', ['P']),
      4,
    );

    // Each unit has versions for both project languages.
    for (final key in ['KEY_1', 'KEY_2']) {
      expect(
        await count('''
          SELECT COUNT(DISTINCT tv.project_language_id)
          FROM translation_versions tv
          INNER JOIN translation_units tu ON tv.unit_id = tu.id
          WHERE tu.project_id = ? AND tu.key = ?
        ''', ['P', key]),
        2,
        reason: 'unit $key must have a version for every project language',
      );
    }
  });

  test('rollback: a failing version insert leaves no orphan unit behind',
      () async {
    // Inject a duplicate project_language id. The unit insert succeeds and the
    // first version (unit, dup) inserts, but the second version for the same
    // (unit, dup) violates UNIQUE(unit_id, project_language_id) and aborts the
    // transaction — rolling back the unit and the first version too.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dup = ProjectLanguage(
      id: 'pl_en',
      projectId: 'P',
      languageId: 'lang_en',
      createdAt: now,
      updatedAt: now,
    );
    final service =
        buildService(langRepo: _StubLanguageRepository([dup, dup]));

    final result = await service.addNewUnits(
      projectId: 'P',
      analysis: analysisWith(const [
        NewUnitData(key: 'KEY_FAIL', sourceText: 'src fail'),
      ]),
    );

    // The method swallows the per-unit failure and reports zero added.
    expect(result.isOk, isTrue);
    expect(result.value, 0, reason: 'a rolled-back unit must not be counted');

    // No unit and no versions survived the rollback.
    expect(
      await count(
          'SELECT COUNT(*) FROM translation_units WHERE project_id = ? AND key = ?',
          ['P', 'KEY_FAIL']),
      0,
      reason: 'the unit must be rolled back, not left behind',
    );
    expect(
      await count('''
        SELECT COUNT(*) FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
      ''', ['P']),
      0,
      reason: 'no partial set of versions may survive',
    );
  });
}
