import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mocktail/mocktail.dart';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';

import '../../../helpers/fakes/fake_logger.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockModUpdateAnalysisService extends Mock
    implements ModUpdateAnalysisService {}

/// Fake notifier to override [projectsWithDetailsProvider] with a fixed list.
class _FakeProjectsWithDetailsNotifier extends ProjectsWithDetailsNotifier {
  _FakeProjectsWithDetailsNotifier(this._items);
  final List<ProjectWithDetails> _items;
  @override
  Future<List<ProjectWithDetails>> build() async => _items;
}

Project _project({
  String id = 'p1',
  String name = 'Alpha',
  String? modSteamId,
  String gameInstallationId = 'g1',
  String? sourceFilePath,
  int updatedAt = 1000,
  bool hasModUpdateImpact = false,
  String? publishedSteamId,
  int? publishedAt,
}) {
  return Project(
    id: id,
    name: name,
    modSteamId: modSteamId,
    gameInstallationId: gameInstallationId,
    sourceFilePath: sourceFilePath,
    createdAt: 1,
    updatedAt: updatedAt,
    hasModUpdateImpact: hasModUpdateImpact,
    publishedSteamId: publishedSteamId,
    publishedAt: publishedAt,
  );
}

ProjectLanguage _projLang({
  String id = 'pl1',
  String projectId = 'p1',
  String languageId = 'lang_fr',
}) {
  return ProjectLanguage(
    id: id,
    projectId: projectId,
    languageId: languageId,
    createdAt: 1,
    updatedAt: 1,
  );
}

ProjectLanguageWithInfo _langInfo({
  String languageId = 'lang_fr',
  int total = 10,
  int translated = 10,
  int needsReview = 0,
}) {
  return ProjectLanguageWithInfo(
    projectLanguage: _projLang(languageId: languageId),
    totalUnits: total,
    translatedUnits: translated,
    needsReviewUnits: needsReview,
  );
}

ExportHistory _export({int exportedAt = 500}) {
  return ExportHistory(
    id: 'e1',
    projectId: 'p1',
    languages: '[]',
    format: ExportFormat.pack,
    validatedOnly: false,
    outputPath: 'out',
    entryCount: 0,
    exportedAt: exportedAt,
  );
}

ProjectWithDetails _pwd({
  Project? project,
  List<ProjectLanguageWithInfo>? languages,
  ModUpdateAnalysis? updateAnalysis,
  ExportHistory? lastPackExport,
}) {
  return ProjectWithDetails(
    project: project ?? _project(),
    languages: languages ?? const [],
    updateAnalysis: updateAnalysis,
    lastPackExport: lastPackExport,
  );
}

ProviderContainer _container({
  List<Override> overrides = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      loggingServiceProvider.overrideWithValue(FakeLogger()),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

ProviderContainer _withProjects(
  List<ProjectWithDetails> items, {
  List<Override> overrides = const [],
}) {
  return _container(
    overrides: [
      projectsWithDetailsProvider.overrideWith(
        () => _FakeProjectsWithDetailsNotifier(items),
      ),
      ...overrides,
    ],
  );
}

void main() {
  group('ProjectSortOption.displayName', () {
    test('covers all cases', () {
      expect(ProjectSortOption.name.displayName, 'Name');
      expect(ProjectSortOption.dateModified.displayName, 'Date Modified');
      expect(ProjectSortOption.dateExported.displayName, 'Date Exported');
      expect(ProjectSortOption.progress.displayName, 'Progress');
    });
  });

  group('projectQuickFilterFromUrlToken', () {
    test('maps every token + default null', () {
      expect(projectQuickFilterFromUrlToken('needs-review'),
          ProjectQuickFilter.needsReview);
      expect(projectQuickFilterFromUrlToken('needs-update'),
          ProjectQuickFilter.needsUpdate);
      expect(projectQuickFilterFromUrlToken('incomplete'),
          ProjectQuickFilter.incomplete);
      expect(projectQuickFilterFromUrlToken('ready-to-compile'),
          ProjectQuickFilter.hasCompleteLanguage);
      expect(projectQuickFilterFromUrlToken('exported'),
          ProjectQuickFilter.exported);
      expect(projectQuickFilterFromUrlToken('not-exported'),
          ProjectQuickFilter.notExported);
      expect(projectQuickFilterFromUrlToken('export-outdated'),
          ProjectQuickFilter.exportOutdated);
      expect(projectQuickFilterFromUrlToken('unknown'), isNull);
      expect(projectQuickFilterFromUrlToken(null), isNull);
    });
  });

  group('ProjectsFilterState', () {
    test('constructor defaults', () {
      const s = ProjectsFilterState();
      expect(s.searchQuery, '');
      expect(s.gameFilters, isEmpty);
      expect(s.languageFilters, isEmpty);
      expect(s.showOnlyWithUpdates, isFalse);
      expect(s.sortBy, ProjectSortOption.dateModified);
      expect(s.sortAscending, isFalse);
      expect(s.viewMode, ProjectViewMode.grid);
      expect(s.quickFilter, ProjectQuickFilter.none);
    });

    test('copyWith covers each field', () {
      const s = ProjectsFilterState();
      final c = s.copyWith(
        searchQuery: 'q',
        gameFilters: {'g'},
        languageFilters: {'l'},
        showOnlyWithUpdates: true,
        sortBy: ProjectSortOption.name,
        sortAscending: true,
        viewMode: ProjectViewMode.list,
        quickFilter: ProjectQuickFilter.exported,
      );
      expect(c.searchQuery, 'q');
      expect(c.gameFilters, {'g'});
      expect(c.languageFilters, {'l'});
      expect(c.showOnlyWithUpdates, isTrue);
      expect(c.sortBy, ProjectSortOption.name);
      expect(c.sortAscending, isTrue);
      expect(c.viewMode, ProjectViewMode.list);
      expect(c.quickFilter, ProjectQuickFilter.exported);

      // copyWith with no args keeps existing values
      final same = c.copyWith();
      expect(same.searchQuery, 'q');
      expect(same.gameFilters, {'g'});
      expect(same.viewMode, ProjectViewMode.list);
    });
  });

  group('ProjectsFilterNotifier', () {
    late ProviderContainer container;
    ProjectsFilterNotifier notifier() =>
        container.read(projectsFilterProvider.notifier);
    ProjectsFilterState state() => container.read(projectsFilterProvider);

    setUp(() {
      container = _container();
    });

    test('initial build is defaults', () {
      expect(state().searchQuery, '');
      expect(state().quickFilter, ProjectQuickFilter.none);
    });

    test('updateState replaces whole state', () {
      notifier().updateState(
        const ProjectsFilterState(searchQuery: 'x', sortAscending: true),
      );
      expect(state().searchQuery, 'x');
      expect(state().sortAscending, isTrue);
    });

    test('updateSearchQuery', () {
      notifier().updateSearchQuery('hello');
      expect(state().searchQuery, 'hello');
    });

    test('updateFilters', () {
      notifier().updateFilters(
        gameFilters: {'g1'},
        languageFilters: {'l1'},
        showOnlyWithUpdates: true,
      );
      expect(state().gameFilters, {'g1'});
      expect(state().languageFilters, {'l1'});
      expect(state().showOnlyWithUpdates, isTrue);
    });

    test('updateSort', () {
      notifier().updateSort(ProjectSortOption.progress, ascending: true);
      expect(state().sortBy, ProjectSortOption.progress);
      expect(state().sortAscending, isTrue);
    });

    test('toggleSort flips direction on same field', () {
      notifier().updateSort(ProjectSortOption.name, ascending: true);
      notifier().toggleSort(ProjectSortOption.name);
      expect(state().sortBy, ProjectSortOption.name);
      expect(state().sortAscending, isFalse);
    });

    test('toggleSort on new name field defaults ascending', () {
      notifier().updateSort(ProjectSortOption.progress, ascending: false);
      notifier().toggleSort(ProjectSortOption.name);
      expect(state().sortBy, ProjectSortOption.name);
      expect(state().sortAscending, isTrue);
    });

    test('toggleSort on new date field defaults descending', () {
      notifier().toggleSort(ProjectSortOption.dateExported);
      expect(state().sortBy, ProjectSortOption.dateExported);
      expect(state().sortAscending, isFalse);
    });

    test('updateViewMode', () {
      notifier().updateViewMode(ProjectViewMode.list);
      expect(state().viewMode, ProjectViewMode.list);
    });

    test('setQuickFilter', () {
      notifier().setQuickFilter(ProjectQuickFilter.needsReview);
      expect(state().quickFilter, ProjectQuickFilter.needsReview);
    });

    test('clearFilters resets filters but keeps search', () {
      notifier().updateSearchQuery('keep');
      notifier().updateFilters(
        gameFilters: {'g'},
        languageFilters: {'l'},
        showOnlyWithUpdates: true,
      );
      notifier().setQuickFilter(ProjectQuickFilter.exported);
      notifier().clearFilters();
      expect(state().searchQuery, 'keep');
      expect(state().gameFilters, isEmpty);
      expect(state().languageFilters, isEmpty);
      expect(state().showOnlyWithUpdates, isFalse);
      expect(state().quickFilter, ProjectQuickFilter.none);
    });

    test('resetAll resets everything', () {
      notifier().updateSearchQuery('q');
      notifier().setQuickFilter(ProjectQuickFilter.exported);
      notifier().resetAll();
      expect(state().searchQuery, '');
      expect(state().quickFilter, ProjectQuickFilter.none);
    });
  });

  group('filteredProjectsProvider — filters', () {
    test('search matches by name', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a', name: 'Alpha')),
        _pwd(project: _project(id: 'b', name: 'Beta')),
      ]);
      c.read(projectsFilterProvider.notifier).updateSearchQuery('alph');
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('search matches by modSteamId', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a', name: 'Alpha', modSteamId: '12345')),
        _pwd(project: _project(id: 'b', name: 'Beta', modSteamId: '99999')),
      ]);
      c.read(projectsFilterProvider.notifier).updateSearchQuery('123');
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('search excludes when neither name nor modId match', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a', name: 'Alpha', modSteamId: '12345')),
      ]);
      c.read(projectsFilterProvider.notifier).updateSearchQuery('zzz');
      final result = await c.read(filteredProjectsProvider.future);
      expect(result, isEmpty);
    });

    test('game filter', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a', gameInstallationId: 'g1')),
        _pwd(project: _project(id: 'b', gameInstallationId: 'g2')),
      ]);
      c.read(projectsFilterProvider.notifier).updateFilters(gameFilters: {'g1'});
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('language filter includes and excludes', () async {
      final c = _withProjects([
        _pwd(
          project: _project(id: 'a'),
          languages: [_langInfo(languageId: 'lang_fr')],
        ),
        _pwd(
          project: _project(id: 'b'),
          languages: [_langInfo(languageId: 'lang_de')],
        ),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .updateFilters(languageFilters: {'lang_fr'});
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('showOnlyWithUpdates', () async {
      final withUpd = _pwd(
        project: _project(id: 'a'),
        updateAnalysis: const ModUpdateAnalysis(
          newUnitsCount: 1,
          removedUnitsCount: 0,
          modifiedUnitsCount: 0,
          totalPackUnits: 1,
          totalProjectUnits: 0,
        ),
      );
      final without = _pwd(project: _project(id: 'b'));
      final c = _withProjects([withUpd, without]);
      c
          .read(projectsFilterProvider.notifier)
          .updateFilters(showOnlyWithUpdates: true);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter needsUpdate', () async {
      final hasUpd = _pwd(
        project: _project(id: 'a'),
        updateAnalysis: const ModUpdateAnalysis(
          newUnitsCount: 1,
          removedUnitsCount: 0,
          modifiedUnitsCount: 0,
          totalPackUnits: 1,
          totalProjectUnits: 0,
        ),
      );
      final c = _withProjects([hasUpd, _pwd(project: _project(id: 'b'))]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.needsUpdate);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter needsReview', () async {
      final c = _withProjects([
        _pwd(
          project: _project(id: 'a'),
          languages: [_langInfo(needsReview: 3)],
        ),
        _pwd(
          project: _project(id: 'b'),
          languages: [_langInfo(needsReview: 0)],
        ),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.needsReview);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter incomplete', () async {
      final c = _withProjects([
        // fully translated -> excluded by incomplete
        _pwd(
          project: _project(id: 'a'),
          languages: [_langInfo(total: 10, translated: 10)],
        ),
        // partial -> included
        _pwd(
          project: _project(id: 'b'),
          languages: [_langInfo(total: 10, translated: 5)],
        ),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.incomplete);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['b']);
    });

    test('quickFilter hasCompleteLanguage', () async {
      final c = _withProjects([
        _pwd(
          project: _project(id: 'a'),
          languages: [
            _langInfo(languageId: 'fr', total: 10, translated: 10),
            _langInfo(languageId: 'de', total: 10, translated: 2),
          ],
        ),
        _pwd(
          project: _project(id: 'b'),
          languages: [_langInfo(total: 10, translated: 3)],
        ),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.hasCompleteLanguage);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter exported', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a'), lastPackExport: _export()),
        _pwd(project: _project(id: 'b')),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.exported);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter notExported', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a'), lastPackExport: _export()),
        _pwd(project: _project(id: 'b')),
      ]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.notExported);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['b']);
    });

    test('quickFilter exportOutdated', () async {
      // updatedAt well after export checkpoint -> modified since export
      final outdated = _pwd(
        project: _project(id: 'a', updatedAt: 10000),
        lastPackExport: _export(exportedAt: 500),
      );
      // updatedAt before export -> not modified since export
      final fresh = _pwd(
        project: _project(id: 'b', updatedAt: 100),
        lastPackExport: _export(exportedAt: 5000),
      );
      final c = _withProjects([outdated, fresh]);
      c
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.exportOutdated);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.map((p) => p.project.id), ['a']);
    });

    test('quickFilter none returns all', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a')),
        _pwd(project: _project(id: 'b')),
      ]);
      final result = await c.read(filteredProjectsProvider.future);
      expect(result.length, 2);
    });
  });

  group('filteredProjectsProvider — sorting', () {
    Future<List<String>> ids(
      ProjectSortOption sort,
      bool ascending,
      List<ProjectWithDetails> items,
    ) async {
      final c = _withProjects(items);
      c
          .read(projectsFilterProvider.notifier)
          .updateSort(sort, ascending: ascending);
      final result = await c.read(filteredProjectsProvider.future);
      return result.map((p) => p.project.id).toList();
    }

    final byName = [
      _pwd(project: _project(id: 'a', name: 'Bravo')),
      _pwd(project: _project(id: 'b', name: 'Alpha')),
    ];

    test('name asc/desc', () async {
      expect(await ids(ProjectSortOption.name, true, byName), ['b', 'a']);
      expect(await ids(ProjectSortOption.name, false, byName), ['a', 'b']);
    });

    final byDate = [
      _pwd(project: _project(id: 'a', updatedAt: 100)),
      _pwd(project: _project(id: 'b', updatedAt: 200)),
    ];

    test('dateModified asc/desc', () async {
      expect(await ids(ProjectSortOption.dateModified, true, byDate),
          ['a', 'b']);
      expect(await ids(ProjectSortOption.dateModified, false, byDate),
          ['b', 'a']);
    });

    final byExport = [
      _pwd(project: _project(id: 'a'), lastPackExport: _export(exportedAt: 100)),
      _pwd(project: _project(id: 'b'), lastPackExport: _export(exportedAt: 900)),
      _pwd(project: _project(id: 'c')), // no export -> 0
    ];

    test('dateExported asc/desc', () async {
      expect(await ids(ProjectSortOption.dateExported, true, byExport),
          ['c', 'a', 'b']);
      expect(await ids(ProjectSortOption.dateExported, false, byExport),
          ['b', 'a', 'c']);
    });

    final byProgress = [
      _pwd(
        project: _project(id: 'a'),
        languages: [_langInfo(total: 10, translated: 2)],
      ),
      _pwd(
        project: _project(id: 'b'),
        languages: [_langInfo(total: 10, translated: 8)],
      ),
    ];

    test('progress asc/desc', () async {
      expect(await ids(ProjectSortOption.progress, true, byProgress),
          ['a', 'b']);
      expect(await ids(ProjectSortOption.progress, false, byProgress),
          ['b', 'a']);
    });
  });

  group('paginatedProjectsProvider', () {
    test('delegates to filtered', () async {
      final c = _withProjects([
        _pwd(project: _project(id: 'a')),
        _pwd(project: _project(id: 'b')),
      ]);
      final result = await c.read(paginatedProjectsProvider.future);
      expect(result.length, 2);
    });
  });

  group('projectQuickFilterCountsProvider', () {
    test('counts each quick filter', () async {
      final items = [
        // exported, fully translated, complete lang, no review, not outdated
        _pwd(
          project: _project(id: 'a', updatedAt: 100),
          languages: [_langInfo(total: 10, translated: 10)],
          lastPackExport: _export(exportedAt: 5000),
        ),
        // not exported, incomplete, needs review, has update
        _pwd(
          project: _project(id: 'b'),
          languages: [_langInfo(total: 10, translated: 3, needsReview: 2)],
          updateAnalysis: const ModUpdateAnalysis(
            newUnitsCount: 1,
            removedUnitsCount: 0,
            modifiedUnitsCount: 0,
            totalPackUnits: 1,
            totalProjectUnits: 0,
          ),
        ),
        // exported + outdated
        _pwd(
          project: _project(id: 'c', updatedAt: 10000),
          languages: [_langInfo(total: 10, translated: 4)],
          lastPackExport: _export(exportedAt: 500),
        ),
      ];
      final c = _withProjects(items);
      final counts = await c.read(projectQuickFilterCountsProvider.future);
      expect(counts[ProjectQuickFilter.needsUpdate], 1);
      expect(counts[ProjectQuickFilter.needsReview], 1);
      expect(counts[ProjectQuickFilter.incomplete], 2);
      expect(counts[ProjectQuickFilter.hasCompleteLanguage], 1);
      expect(counts[ProjectQuickFilter.exported], 2);
      expect(counts[ProjectQuickFilter.notExported], 1);
      expect(counts[ProjectQuickFilter.exportOutdated], 1);
    });
  });

  group('ProjectResyncNotifier.resync', () {
    late MockProjectRepository repo;
    late MockModUpdateAnalysisService analysisService;

    setUpAll(() {
      registerFallbackValue(_project());
    });

    setUp(() {
      repo = MockProjectRepository();
      analysisService = MockModUpdateAnalysisService();
    });

    ProviderContainer build() {
      return _container(
        overrides: [
          projectRepositoryProvider.overrideWithValue(repo),
          modUpdateAnalysisServiceProvider.overrideWithValue(analysisService),
        ],
      );
    }

    test('isResyncing is false initially', () {
      final c = build();
      expect(
        c.read(projectResyncProvider.notifier).isResyncing('p1'),
        isFalse,
      );
    });

    test('throws when project not found', () async {
      when(() => repo.getById(any())).thenAnswer(
        (_) async => const Err(TWMTDatabaseException('not found')),
      );
      final c = build();
      final notifier = c.read(projectResyncProvider.notifier);
      await expectLater(notifier.resync('p1'), throwsA(isA<Exception>()));
      // resyncing set cleaned up in finally
      expect(notifier.isResyncing('p1'), isFalse);
    });

    test('throws when sourceFilePath is null', () async {
      when(() => repo.getById(any())).thenAnswer(
        (_) async => Ok(_project(id: 'p1', sourceFilePath: null)),
      );
      final c = build();
      final notifier = c.read(projectResyncProvider.notifier);
      await expectLater(notifier.resync('p1'), throwsA(isA<Exception>()));
      expect(notifier.isResyncing('p1'), isFalse);
    });

    test('throws when source file does not exist', () async {
      when(() => repo.getById(any())).thenAnswer(
        (_) async => Ok(_project(
          id: 'p1',
          sourceFilePath: 'Z:/nonexistent/missing.pack',
        )),
      );
      final c = build();
      final notifier = c.read(projectResyncProvider.notifier);
      await expectLater(notifier.resync('p1'), throwsA(isA<Exception>()));
      expect(notifier.isResyncing('p1'), isFalse);
    });

    test('throws when analyzeChanges fails', () async {
      final tmpDir = Directory.systemTemp.createTempSync('resync_err');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final file = File('${tmpDir.path}/source.pack')..writeAsStringSync('x');

      when(() => repo.getById(any())).thenAnswer(
        (_) async => Ok(_project(id: 'p1', sourceFilePath: file.path)),
      );
      when(() => analysisService.analyzeChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer(
        (_) async => const Err(ServiceException('boom')),
      );

      final c = build();
      final notifier = c.read(projectResyncProvider.notifier);
      await expectLater(notifier.resync('p1'), throwsA(isA<Exception>()));
      expect(notifier.isResyncing('p1'), isFalse);
    });

    test('happy path with no pending changes', () async {
      final tmpDir = Directory.systemTemp.createTempSync('resync_ok');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final file = File('${tmpDir.path}/source.pack')..writeAsStringSync('x');

      when(() => repo.getById(any())).thenAnswer(
        (_) async => Ok(_project(id: 'p1', sourceFilePath: file.path)),
      );
      when(() => analysisService.analyzeChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer(
        (_) async => const Ok(ModUpdateAnalysis.empty),
      );

      final c = build();
      final notifier = c.read(projectResyncProvider.notifier);
      await notifier.resync('p1');
      expect(notifier.isResyncing('p1'), isFalse);
      // update should NOT be called since there were no pending changes
      verifyNever(() => repo.update(any()));
    });
  });
}
