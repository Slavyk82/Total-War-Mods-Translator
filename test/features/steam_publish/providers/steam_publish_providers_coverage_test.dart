// Coverage tests for steam_publish_providers.dart that exercise the parts not
// covered by the existing state-provider test: the PublishableItem getters, the
// real `publishableItems` provider body, the `filteredPublishableItems` filter
// + sort matrix, and the three count providers.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';

class _MockProjectRepo extends Mock implements ProjectRepository {}

class _MockCompilationRepo extends Mock implements CompilationRepository {}

class _MockExportHistoryRepo extends Mock implements ExportHistoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockGameInstallationRepo extends Mock
    implements GameInstallationRepository {}

/// Test double for [SelectedGame] returning a fixed value without settings.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

// --- builders -----------------------------------------------------------

Project _project({
  required String id,
  String? metadata,
  String? imageUrl,
  String? modSteamId,
  String? publishedSteamId,
  int? publishedAt,
  String name = 'Project',
}) {
  // Encode title/image into a metadata JSON so displayName/imageUrl resolve.
  final meta = metadata ??
      (imageUrl != null
          ? '{"mod_image_url":"$imageUrl","mod_title":"$name"}'
          : null);
  return Project(
    id: id,
    name: name,
    gameInstallationId: 'gi',
    createdAt: 0,
    updatedAt: 0,
    metadata: meta,
    modSteamId: modSteamId,
    publishedSteamId: publishedSteamId,
    publishedAt: publishedAt,
  );
}

ExportHistory _export({
  required String outputPath,
  int? fileSize,
  int entryCount = 5,
  int exportedAt = 1000,
  String languages = '["en","fr"]',
}) {
  return ExportHistory(
    id: 'eh',
    projectId: 'p',
    languages: languages,
    format: ExportFormat.pack,
    validatedOnly: false,
    outputPath: outputPath,
    fileSize: fileSize,
    entryCount: entryCount,
    exportedAt: exportedAt,
  );
}

Compilation _compilation({
  required String id,
  String name = 'Comp',
  String? lastOutputPath,
  int? lastGeneratedAt,
  String? languageId,
  String? publishedSteamId,
  int? publishedAt,
}) {
  return Compilation(
    id: id,
    name: name,
    prefix: 'pre_',
    packName: 'pack',
    gameInstallationId: 'gi',
    languageId: languageId,
    lastOutputPath: lastOutputPath,
    lastGeneratedAt: lastGeneratedAt,
    publishedSteamId: publishedSteamId,
    publishedAt: publishedAt,
    createdAt: 0,
    updatedAt: 0,
  );
}

const _gi = GameInstallation(
  id: 'gi-1',
  gameCode: 'wh3',
  gameName: 'Total War: WARHAMMER III',
  createdAt: 0,
  updatedAt: 0,
);

const _game = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/games/wh3',
);

ProjectPublishItem _pItem({
  ExportHistory? export,
  Project? project,
  List<String> langs = const ['en'],
}) =>
    ProjectPublishItem(
      export: export,
      project: project ?? _project(id: 'p'),
      languageCodes: langs,
    );

CompilationPublishItem _cItem({
  required Compilation compilation,
  String? languageCode,
  int projectCount = 2,
  int? fileSize,
}) =>
    CompilationPublishItem(
      compilation: compilation,
      languageCode: languageCode,
      projectCount: projectCount,
      fileSize: fileSize,
    );

void main() {
  // ----------------------------------------------------------------------
  group('ProjectPublishItem getters', () {
    test('exposes export/project fields when pack exists on disk', () {
      final dir = Directory.systemTemp.createTempSync('twmt_pi');
      addTearDown(() => dir.deleteSync(recursive: true));
      final packPath = '${dir.path}${Platform.pathSeparator}mod.pack';
      File(packPath).writeAsStringSync('PACK');

      final item = _pItem(
        export: _export(
          outputPath: packPath,
          fileSize: 2048,
          entryCount: 7,
          languages: '["en","de"]',
        ),
        project: _project(
          id: 'p1',
          name: 'My Mod',
          imageUrl: 'http://img/x.png',
          modSteamId: '999',
          publishedSteamId: '555',
          publishedAt: 1700000000,
        ),
      );

      expect(item.displayName, 'My Mod');
      expect(item.imageUrl, 'http://img/x.png');
      expect(item.outputPath, packPath);
      expect(item.publishedSteamId, '555');
      expect(item.publishedAt, 1700000000);
      expect(item.isCompilation, isFalse);
      expect(item.hasPack, isTrue);
      expect(item.itemId, 'p1');
      expect(item.exportedAt, 1000);
      expect(item.steamWorkshopId, '999');
      expect(item.isFromSteamWorkshop, isTrue);
      expect(item.languagesList, ['en', 'de']);
      expect(item.entryCount, 7);
      expect(item.fileSizeFormatted, '2.0 KB');
    });

    test('falls back when export is null and no pack on disk', () {
      final item = _pItem(
        export: null,
        project: _project(id: 'p2', name: 'NoExport'),
        langs: const ['it'],
      );

      expect(item.outputPath, '');
      expect(item.hasPack, isFalse);
      expect(item.exportedAt, 0);
      expect(item.languagesList, ['it']); // falls back to languageCodes
      expect(item.entryCount, 0);
      expect(item.fileSizeFormatted, '');
      expect(item.isFromSteamWorkshop, isFalse);
      expect(item.steamWorkshopId, isNull);
    });

    test('hasPack is false when export path points to missing file', () {
      final item = _pItem(
        export: _export(outputPath: 'Z:/does/not/exist.pack'),
        project: _project(id: 'p3'),
      );
      expect(item.hasPack, isFalse);
    });
  });

  // ----------------------------------------------------------------------
  group('CompilationPublishItem getters', () {
    test('exposes compilation fields and hasPack with real file', () {
      final dir = Directory.systemTemp.createTempSync('twmt_ci');
      addTearDown(() => dir.deleteSync(recursive: true));
      final packPath = '${dir.path}${Platform.pathSeparator}comp.pack';
      File(packPath).writeAsStringSync('PACK');

      final item = _cItem(
        compilation: _compilation(
          id: 'c1',
          name: 'Big Comp',
          lastOutputPath: packPath,
          lastGeneratedAt: 1234,
          publishedSteamId: '777',
          publishedAt: 1690000000,
        ),
        languageCode: 'fr',
        fileSize: 500,
      );

      expect(item.displayName, 'Big Comp');
      expect(item.imageUrl, isNull);
      expect(item.outputPath, packPath);
      expect(item.publishedSteamId, '777');
      expect(item.publishedAt, 1690000000);
      expect(item.isCompilation, isTrue);
      expect(item.hasPack, isTrue);
      expect(item.itemId, 'c1');
      expect(item.exportedAt, 1234);
    });

    test('hasPack false when never generated or missing file', () {
      final notGenerated = _cItem(
        compilation: _compilation(id: 'c2', lastGeneratedAt: null),
      );
      expect(notGenerated.hasPack, isFalse);
      expect(notGenerated.exportedAt, 0);
      expect(notGenerated.outputPath, '');

      final missingFile = _cItem(
        compilation: _compilation(
          id: 'c3',
          lastGeneratedAt: 10,
          lastOutputPath: 'Z:/missing.pack',
        ),
      );
      expect(missingFile.hasPack, isFalse);
    });

    test('fileSizeFormatted covers every size branch', () {
      Compilation c() => _compilation(id: 'c');
      expect(_cItem(compilation: c(), fileSize: null).fileSizeFormatted,
          'Unknown');
      expect(_cItem(compilation: c(), fileSize: 512).fileSizeFormatted, '512 B');
      expect(
          _cItem(compilation: c(), fileSize: 2048).fileSizeFormatted, '2.0 KB');
      expect(
        _cItem(compilation: c(), fileSize: 3 * 1024 * 1024).fileSizeFormatted,
        '3.0 MB',
      );
    });
  });

  // ----------------------------------------------------------------------
  group('publishableItems provider (real body)', () {
    late _MockProjectRepo projectRepo;
    late _MockCompilationRepo compilationRepo;
    late _MockExportHistoryRepo exportRepo;
    late _MockLanguageRepo languageRepo;
    late _MockProjectLanguageRepo projectLanguageRepo;
    late _MockGameInstallationRepo gameInstallationRepo;

    setUp(() {
      projectRepo = _MockProjectRepo();
      compilationRepo = _MockCompilationRepo();
      exportRepo = _MockExportHistoryRepo();
      languageRepo = _MockLanguageRepo();
      projectLanguageRepo = _MockProjectLanguageRepo();
      gameInstallationRepo = _MockGameInstallationRepo();
    });

    baseOverrides(ConfiguredGame? game) => [
          projectRepositoryProvider.overrideWithValue(projectRepo),
          compilationRepositoryProvider.overrideWithValue(compilationRepo),
          exportHistoryRepositoryProvider.overrideWithValue(exportRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          gameInstallationRepositoryProvider
              .overrideWithValue(gameInstallationRepo),
          selectedGameProvider.overrideWith(() => _FakeSelectedGame(game)),
        ];

    test('resolves installation, builds project + compilation items', () async {
      final dir = Directory.systemTemp.createTempSync('twmt_pub');
      addTearDown(() => dir.deleteSync(recursive: true));
      final packPath = '${dir.path}${Platform.pathSeparator}c.pack';
      File(packPath).writeAsStringSync('DATA-1234'); // 9 bytes

      when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_gi),
      );

      final project = _project(id: 'p-a', name: 'Alpha');
      when(() => projectRepo.getByGameInstallation('gi-1')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([project]),
      );
      when(() => exportRepo.getLastPackExportByProject('p-a'))
          .thenAnswer((_) async => _export(outputPath: 'x.pack'));

      // Project languages -> resolve a language code.
      when(() => projectLanguageRepo.getByProject('p-a')).thenAnswer(
        (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([
          const ProjectLanguage(
            id: 'pl1',
            projectId: 'p-a',
            languageId: 'lang-en',
            createdAt: 0,
            updatedAt: 0,
          ),
        ]),
      );
      when(() => languageRepo.getById('lang-en')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          const Language(
            id: 'lang-en',
            code: 'en',
            name: 'English',
            nativeName: 'English',
          ),
        ),
      );

      final comp = _compilation(
        id: 'c-a',
        lastOutputPath: packPath,
        lastGeneratedAt: 50,
        languageId: 'lang-fr',
      );
      when(() => compilationRepo.getByGameInstallation('gi-1')).thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>([comp]),
      );
      when(() => languageRepo.getById('lang-fr')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          const Language(
            id: 'lang-fr',
            code: 'fr',
            name: 'French',
            nativeName: 'Francais',
          ),
        ),
      );
      when(() => compilationRepo.getProjectIds('c-a')).thenAnswer(
        (_) async =>
            Ok<List<String>, TWMTDatabaseException>(['p1', 'p2', 'p3']),
      );

      final container = ProviderContainer(overrides: baseOverrides(_game));
      addTearDown(container.dispose);

      final items = await container.read(publishableItemsProvider.future);
      expect(items, hasLength(2));

      final pItem = items.whereType<ProjectPublishItem>().single;
      expect(pItem.project.id, 'p-a');
      expect(pItem.languageCodes, ['en']);

      final cItem = items.whereType<CompilationPublishItem>().single;
      expect(cItem.languageCode, 'fr');
      expect(cItem.projectCount, 3);
      expect(cItem.fileSize, 9); // lengthSync() of the real temp pack
    });

    test('no selected game -> getAll paths, error results yield no items',
        () async {
      // projectRepo.getAll returns Err; compilationRepo.getAll returns Err.
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Err<List<Project>, TWMTDatabaseException>(
          const TWMTDatabaseException('boom'),
        ),
      );
      when(() => compilationRepo.getAll()).thenAnswer(
        (_) async => Err<List<Compilation>, TWMTDatabaseException>(
          const TWMTDatabaseException('boom'),
        ),
      );

      final container = ProviderContainer(overrides: baseOverrides(null));
      addTearDown(container.dispose);

      final items = await container.read(publishableItemsProvider.future);
      expect(items, isEmpty);
      verify(() => projectRepo.getAll()).called(1);
      verify(() => compilationRepo.getAll()).called(1);
    });

    test('no game + getAll ok, project-language Err, compilation no lang/pack',
        () async {
      final project = _project(id: 'p-b', name: 'Beta');
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([project]),
      );
      when(() => exportRepo.getLastPackExportByProject('p-b'))
          .thenAnswer((_) async => null);
      // project-language lookup fails -> langCodes stays empty (covers !isOk).
      when(() => projectLanguageRepo.getByProject('p-b')).thenAnswer(
        (_) async => Err<List<ProjectLanguage>, TWMTDatabaseException>(
          const TWMTDatabaseException('pl down'),
        ),
      );

      // Compilation with no languageId and never generated -> no file branch,
      // and getProjectIds returns Err -> projectCount falls back to 0.
      final comp = _compilation(id: 'c-b', lastGeneratedAt: null);
      when(() => compilationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>([comp]),
      );
      when(() => compilationRepo.getProjectIds('c-b')).thenAnswer(
        (_) async => Err<List<String>, TWMTDatabaseException>(
          const TWMTDatabaseException('no ids'),
        ),
      );

      final container = ProviderContainer(overrides: baseOverrides(null));
      addTearDown(container.dispose);

      final items = await container.read(publishableItemsProvider.future);
      expect(items, hasLength(2));
      final pItem = items.whereType<ProjectPublishItem>().single;
      expect(pItem.languageCodes, isEmpty);
      expect(pItem.export, isNull);
      final cItem = items.whereType<CompilationPublishItem>().single;
      expect(cItem.languageCode, isNull);
      expect(cItem.projectCount, 0);
      expect(cItem.fileSize, isNull);
    });

    test('game selected but installation lookup fails -> getAll fallback',
        () async {
      when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Err<GameInstallation, TWMTDatabaseException>(
          const TWMTDatabaseException('no install'),
        ),
      );
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>(const []),
      );
      when(() => compilationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(const []),
      );

      final container = ProviderContainer(overrides: baseOverrides(_game));
      addTearDown(container.dispose);

      final items = await container.read(publishableItemsProvider.future);
      expect(items, isEmpty);
      verify(() => projectRepo.getAll()).called(1);
      verify(() => compilationRepo.getAll()).called(1);
    });

    test('language lookup Err leaves project lang codes empty', () async {
      final project = _project(id: 'p-c');
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([project]),
      );
      when(() => exportRepo.getLastPackExportByProject('p-c'))
          .thenAnswer((_) async => null);
      when(() => projectLanguageRepo.getByProject('p-c')).thenAnswer(
        (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([
          const ProjectLanguage(
            id: 'pl',
            projectId: 'p-c',
            languageId: 'lang-x',
            createdAt: 0,
            updatedAt: 0,
          ),
        ]),
      );
      when(() => languageRepo.getById('lang-x')).thenAnswer(
        (_) async => Err<Language, TWMTDatabaseException>(
          const TWMTDatabaseException('no lang'),
        ),
      );
      when(() => compilationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(const []),
      );

      final container = ProviderContainer(overrides: baseOverrides(null));
      addTearDown(container.dispose);

      final items = await container.read(publishableItemsProvider.future);
      final pItem = items.whereType<ProjectPublishItem>().single;
      expect(pItem.languageCodes, isEmpty);
    });
  });

  // ----------------------------------------------------------------------
  group('filteredPublishableItems + counts', () {
    // Build a list with a stable mix of items for filter/sort tests.
    // - outdated: exported after publish
    // - published not outdated
    // - unpublished with pack
    // - compilation, no pack
    List<PublishableItem> sample() {
      final dir = Directory.systemTemp.createTempSync('twmt_filt');
      addTearDown(() => dir.deleteSync(recursive: true));
      final packPath = '${dir.path}${Platform.pathSeparator}real.pack';
      File(packPath).writeAsStringSync('PACK');

      final outdated = _pItem(
        export: _export(outputPath: packPath, exportedAt: 2000),
        project: _project(
          id: 'p-out',
          name: 'Zeta',
          publishedSteamId: '1',
          publishedAt: 1000, // exportedAt(2000) > publishedAt -> outdated
        ),
      );
      final upToDate = _pItem(
        export: _export(outputPath: packPath, exportedAt: 500),
        project: _project(
          id: 'p-pub',
          name: 'Alpha',
          publishedSteamId: '2',
          publishedAt: 3000, // not outdated
        ),
      );
      final unpublished = _pItem(
        export: _export(outputPath: packPath, exportedAt: 1500),
        project: _project(id: 'p-unp', name: 'Mike'),
      );
      // Compilation never generated -> no pack, exportedAt 0, unpublished.
      final comp = _cItem(
        compilation: _compilation(id: 'c-x', name: 'Beta', lastGeneratedAt: null),
      );
      return [outdated, upToDate, unpublished, comp];
    }

    ProviderContainer make({
      required List<PublishableItem> items,
      SteamPublishDisplayFilter filter = SteamPublishDisplayFilter.all,
      String query = '',
      SteamPublishSortMode sort = SteamPublishSortMode.exportDate,
      bool ascending = false,
    }) {
      final c = ProviderContainer(
        overrides: [
          publishableItemsProvider.overrideWith((ref) async => items),
        ],
      );
      addTearDown(c.dispose);
      c.read(steamPublishDisplayFilterProvider.notifier).state = filter;
      c.read(steamPublishSearchQueryProvider.notifier).state = query;
      c.read(steamPublishSortModeProvider.notifier).state = sort;
      c.read(steamPublishSortAscendingProvider.notifier).state = ascending;
      // Ensure upstream future resolves before reading the sync provider.
      return c;
    }

    Future<List<PublishableItem>> readFiltered(ProviderContainer c) async {
      await c.read(publishableItemsProvider.future);
      return c.read(filteredPublishableItemsProvider);
    }

    test('empty upstream -> empty filtered list', () async {
      final c = make(items: const []);
      expect(await readFiltered(c), isEmpty);
    });

    test('filter: all returns everything', () async {
      final c = make(items: sample());
      expect(await readFiltered(c), hasLength(4));
    });

    test('filter: outdated', () async {
      final c = make(
        items: sample(),
        filter: SteamPublishDisplayFilter.outdated,
      );
      final r = await readFiltered(c);
      expect(r, hasLength(1));
      expect(r.single.displayName, 'Zeta');
    });

    test('filter: noPackGenerated', () async {
      final c = make(
        items: sample(),
        filter: SteamPublishDisplayFilter.noPackGenerated,
      );
      final r = await readFiltered(c);
      expect(r, hasLength(1));
      expect(r.single.isCompilation, isTrue);
    });

    test('filter: compilations', () async {
      final c = make(
        items: sample(),
        filter: SteamPublishDisplayFilter.compilations,
      );
      final r = await readFiltered(c);
      expect(r, hasLength(1));
      expect(r.single.displayName, 'Beta');
    });

    test('search query filters by display name', () async {
      final c = make(items: sample(), query: 'alph');
      final r = await readFiltered(c);
      expect(r, hasLength(1));
      expect(r.single.displayName, 'Alpha');
    });

    test('sort: exportDate descending (default) puts no-pack last', () async {
      final c = make(items: sample());
      final r = await readFiltered(c);
      // exportedAt: Zeta 2000, Mike 1500, Alpha 500, Beta(comp) 0 last.
      expect(r.map((e) => e.displayName).toList(),
          ['Zeta', 'Mike', 'Alpha', 'Beta']);
    });

    test('sort: exportDate ascending keeps no-pack last', () async {
      final c = make(items: sample(), ascending: true);
      final r = await readFiltered(c);
      // Ascending by exportedAt, exportedAt==0 still pinned to end.
      expect(r.last.displayName, 'Beta');
      expect(r.first.displayName, 'Alpha');
    });

    test('sort: name ascending and descending', () async {
      final asc = make(
        items: sample(),
        sort: SteamPublishSortMode.name,
        ascending: true,
      );
      expect(
        (await readFiltered(asc)).map((e) => e.displayName).toList(),
        ['Alpha', 'Beta', 'Mike', 'Zeta'],
      );

      final desc = make(
        items: sample(),
        sort: SteamPublishSortMode.name,
        ascending: false,
      );
      expect(
        (await readFiltered(desc)).map((e) => e.displayName).toList(),
        ['Zeta', 'Mike', 'Beta', 'Alpha'],
      );
    });

    test('sort: publishDate puts unpublished at end both directions', () async {
      final asc = make(
        items: sample(),
        sort: SteamPublishSortMode.publishDate,
        ascending: true,
      );
      final rAsc = await readFiltered(asc);
      // Published: Alpha(3000), Zeta(1000). Unpublished: Mike, Beta at the end.
      final pubNames = rAsc.take(2).map((e) => e.displayName).toList();
      expect(pubNames, ['Zeta', 'Alpha']); // ascending by publishedAt
      final tail = rAsc.skip(2).map((e) => e.displayName).toSet();
      expect(tail, {'Mike', 'Beta'});

      final desc = make(
        items: sample(),
        sort: SteamPublishSortMode.publishDate,
        ascending: false,
      );
      final rDesc = await readFiltered(desc);
      expect(rDesc.take(2).map((e) => e.displayName).toList(),
          ['Alpha', 'Zeta']);
      expect(
          rDesc.skip(2).map((e) => e.displayName).toSet(), {'Mike', 'Beta'});
    });

    test('sort: exportDate tie-break by name when both have no pack', () async {
      // Two never-generated compilations -> both exportedAt == 0, so the
      // sort comparator falls into the displayName tie-break branch.
      final a = _cItem(
        compilation: _compilation(id: 'c-a', name: 'Bravo', lastGeneratedAt: null),
      );
      final b = _cItem(
        compilation: _compilation(id: 'c-b', name: 'Alpha', lastGeneratedAt: null),
      );
      final c = make(items: [a, b]); // exportDate descending default
      final r = await readFiltered(c);
      // Tie-break compares names ascending regardless of direction.
      expect(r.map((e) => e.displayName).toList(), ['Alpha', 'Bravo']);
    });

    test('sort: publishDate tie-break by exportedAt for equal publish times',
        () async {
      final dir = Directory.systemTemp.createTempSync('twmt_tie');
      addTearDown(() => dir.deleteSync(recursive: true));
      final packPath = '${dir.path}${Platform.pathSeparator}t.pack';
      File(packPath).writeAsStringSync('PACK');

      // Same publishedAt -> comparator falls through to exportedAt tie-break.
      final early = _pItem(
        export: _export(outputPath: packPath, exportedAt: 100),
        project: _project(
          id: 'p-e',
          name: 'Early',
          publishedSteamId: '1',
          publishedAt: 5000,
        ),
      );
      final late = _pItem(
        export: _export(outputPath: packPath, exportedAt: 900),
        project: _project(
          id: 'p-l',
          name: 'Late',
          publishedSteamId: '2',
          publishedAt: 5000,
        ),
      );
      final c = make(
        items: [late, early],
        sort: SteamPublishSortMode.publishDate,
        ascending: true,
      );
      final r = await readFiltered(c);
      // Equal publishedAt -> ordered by exportedAt ascending.
      expect(r.map((e) => e.displayName).toList(), ['Early', 'Late']);
    });

    test('counts: outdated / noPack / compilations', () async {
      final c = make(items: sample());
      await c.read(publishableItemsProvider.future);
      expect(c.read(outdatedPublishableItemsCountProvider), 1);
      expect(c.read(noPackPublishableItemsCountProvider), 1);
      expect(c.read(compilationsPublishableItemsCountProvider), 1);
    });

    test('counts are 0 when upstream still loading (no asData)', () {
      // Never resolve the upstream future; counts read const empty list.
      final c = ProviderContainer(
        overrides: [
          publishableItemsProvider.overrideWith(
            (ref) => Completer<List<PublishableItem>>().future,
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(outdatedPublishableItemsCountProvider), 0);
      expect(c.read(noPackPublishableItemsCountProvider), 0);
      expect(c.read(compilationsPublishableItemsCountProvider), 0);
      expect(c.read(filteredPublishableItemsProvider), isEmpty);
    });
  });
}
