import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockWorkshopModRepository extends Mock implements WorkshopModRepository {}

class _MockCacheRepository extends Mock
    implements ModUpdateAnalysisCacheRepository {}

/// Fake DetectedMods AsyncNotifier that returns a fixed list synchronously.
class _FakeDetectedMods extends DetectedMods {
  _FakeDetectedMods(this._mods);
  final List<DetectedMod> _mods;
  @override
  Future<List<DetectedMod>> build() async => _mods;
}

DetectedMod _mod({
  required String workshopId,
  required String name,
  bool isHidden = false,
  bool isAlreadyImported = false,
  int? timeUpdated,
  int? localFileLastModified,
  int? subscribers,
}) {
  return DetectedMod(
    workshopId: workshopId,
    name: name,
    packFilePath: 'C:/mods/$workshopId.pack',
    isHidden: isHidden,
    isAlreadyImported: isAlreadyImported,
    timeUpdated: timeUpdated,
    localFileLastModified: localFileLastModified,
    metadata: subscribers == null
        ? null
        : ProjectMetadata(modSubscribers: subscribers),
  );
}

/// Build a container with detectedMods overridden to a fixed list + fake logger.
ProviderContainer _containerWithMods(
  List<DetectedMod> mods, {
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      loggingServiceProvider.overrideWithValue(FakeLogger()),
      detectedModsProvider.overrideWith(() => _FakeDetectedMods(mods)),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ModsSessionCache', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    final modA = _mod(workshopId: '1', name: 'Alpha');
    final modB = _mod(workshopId: '2', name: 'Beta');

    test('starts empty', () {
      expect(container.read(modsSessionCacheProvider), isEmpty);
    });

    test('cacheMods / hasCachedMods / getCachedMods', () {
      final notifier = container.read(modsSessionCacheProvider.notifier);
      expect(notifier.hasCachedMods('wh3'), isFalse);
      expect(notifier.getCachedMods('wh3'), isNull);

      notifier.cacheMods('wh3', [modA, modB]);
      expect(notifier.hasCachedMods('wh3'), isTrue);
      expect(notifier.getCachedMods('wh3'), hasLength(2));
    });

    test('clearCache removes one game', () {
      final notifier = container.read(modsSessionCacheProvider.notifier);
      notifier.cacheMods('wh3', [modA]);
      notifier.cacheMods('wh2', [modB]);
      notifier.clearCache('wh3');
      expect(notifier.hasCachedMods('wh3'), isFalse);
      expect(notifier.hasCachedMods('wh2'), isTrue);
    });

    test('clearAllCache empties everything', () {
      final notifier = container.read(modsSessionCacheProvider.notifier);
      notifier.cacheMods('wh3', [modA]);
      notifier.cacheMods('wh2', [modB]);
      notifier.clearAllCache();
      expect(container.read(modsSessionCacheProvider), isEmpty);
    });

    test('updateModInCache flips isHidden across games', () {
      final notifier = container.read(modsSessionCacheProvider.notifier);
      notifier.cacheMods('wh3', [modA, modB]);
      notifier.cacheMods('wh2', [modA]);
      notifier.updateModInCache('1', true);
      final wh3 = notifier.getCachedMods('wh3')!;
      expect(wh3.firstWhere((m) => m.workshopId == '1').isHidden, isTrue);
      expect(wh3.firstWhere((m) => m.workshopId == '2').isHidden, isFalse);
      expect(notifier.getCachedMods('wh2')!.first.isHidden, isTrue);
    });

    test('updateModImportedInCache marks imported', () {
      final notifier = container.read(modsSessionCacheProvider.notifier);
      notifier.cacheMods('wh3', [modA, modB]);
      notifier.updateModImportedInCache('2', 'proj-99');
      final updated =
          notifier.getCachedMods('wh3')!.firstWhere((m) => m.workshopId == '2');
      expect(updated.isAlreadyImported, isTrue);
      expect(updated.existingProjectId, 'proj-99');
    });
  });

  group('modsFilterFromUrlToken', () {
    test('maps known tokens', () {
      expect(modsFilterFromUrlToken('needs-update'), ModsFilter.needsUpdate);
      expect(modsFilterFromUrlToken('not-imported'), ModsFilter.notImported);
      expect(modsFilterFromUrlToken('all'), ModsFilter.all);
    });
    test('returns null for unknown/null', () {
      expect(modsFilterFromUrlToken('bogus'), isNull);
      expect(modsFilterFromUrlToken(null), isNull);
    });
  });

  group('simple notifier providers', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('ModsFilterState', () {
      expect(container.read(modsFilterStateProvider), ModsFilter.all);
      container
          .read(modsFilterStateProvider.notifier)
          .setFilter(ModsFilter.needsUpdate);
      expect(container.read(modsFilterStateProvider), ModsFilter.needsUpdate);
    });

    test('ModsSearchQuery', () {
      expect(container.read(modsSearchQueryProvider), '');
      container.read(modsSearchQueryProvider.notifier).setQuery('hello');
      expect(container.read(modsSearchQueryProvider), 'hello');
      container.read(modsSearchQueryProvider.notifier).clear();
      expect(container.read(modsSearchQueryProvider), '');
    });

    test('ShowHiddenMods', () {
      expect(container.read(showHiddenModsProvider), isFalse);
      container.read(showHiddenModsProvider.notifier).toggle();
      expect(container.read(showHiddenModsProvider), isTrue);
      container.read(showHiddenModsProvider.notifier).set(false);
      expect(container.read(showHiddenModsProvider), isFalse);
    });

    test('ModsLoadingState', () {
      expect(container.read(modsLoadingStateProvider), isFalse);
      container.read(modsLoadingStateProvider.notifier).setLoading(true);
      expect(container.read(modsLoadingStateProvider), isTrue);
    });

    test('ModsRefreshTrigger initial', () {
      expect(container.read(modsRefreshTriggerProvider), 0);
    });
  });

  group('ModsSort', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('default is name ascending', () {
      final s = container.read(modsSortProvider);
      expect(s.field, ModsSortField.name);
      expect(s.ascending, isTrue);
    });

    test('toggle same field flips direction', () {
      final notifier = container.read(modsSortProvider.notifier);
      notifier.toggle(ModsSortField.name);
      expect(container.read(modsSortProvider).ascending, isFalse);
    });

    test('toggle to numeric field defaults descending', () {
      final notifier = container.read(modsSortProvider.notifier);
      notifier.toggle(ModsSortField.subscribers);
      final s = container.read(modsSortProvider);
      expect(s.field, ModsSortField.subscribers);
      expect(s.ascending, isFalse);
    });

    test('toggle to name field defaults ascending', () {
      final notifier = container.read(modsSortProvider.notifier);
      notifier.toggle(ModsSortField.updated);
      notifier.toggle(ModsSortField.name);
      expect(container.read(modsSortProvider).field, ModsSortField.name);
      expect(container.read(modsSortProvider).ascending, isTrue);
    });

    test('reset restores name ascending', () {
      final notifier = container.read(modsSortProvider.notifier);
      notifier.toggle(ModsSortField.subscribers);
      notifier.reset();
      final s = container.read(modsSortProvider);
      expect(s.field, ModsSortField.name);
      expect(s.ascending, isTrue);
    });

    test('ModsSortState.copyWith', () {
      const base = ModsSortState(field: ModsSortField.name, ascending: true);
      final copied = base.copyWith(ascending: false);
      expect(copied.field, ModsSortField.name);
      expect(copied.ascending, isFalse);
      final copied2 = base.copyWith(field: ModsSortField.updated);
      expect(copied2.field, ModsSortField.updated);
      expect(copied2.ascending, isTrue);
    });
  });

  group('filteredMods', () {
    final mods = [
      _mod(workshopId: '100', name: 'Charlie', subscribers: 50),
      _mod(
        workshopId: '200',
        name: 'alpha',
        isAlreadyImported: true,
        subscribers: 300,
        timeUpdated: 2000,
        localFileLastModified: 1000, // needsDownload
      ),
      _mod(
        workshopId: '300',
        name: 'Bravo',
        subscribers: 10,
        timeUpdated: 1000,
        localFileLastModified: 5000, // upToDate
      ),
      _mod(workshopId: '400', name: 'Hidden Mod', isHidden: true),
    ];

    Future<List<DetectedMod>> read(ProviderContainer c) async {
      // detectedMods resolves async; pump until value present.
      c.listen(detectedModsProvider, (_, _) {});
      await c.read(detectedModsProvider.future);
      return c.read(filteredModsProvider);
    }

    test('hides hidden mods by default', () async {
      final c = _containerWithMods(mods);
      final result = await read(c);
      expect(result.map((m) => m.workshopId), isNot(contains('400')));
      expect(result, hasLength(3));
    });

    test('showHidden=true shows only hidden mods', () async {
      final c = _containerWithMods(mods);
      c.read(showHiddenModsProvider.notifier).set(true);
      final result = await read(c);
      expect(result.map((m) => m.workshopId), ['400']);
    });

    test('notImported filter', () async {
      final c = _containerWithMods(mods);
      c
          .read(modsFilterStateProvider.notifier)
          .setFilter(ModsFilter.notImported);
      final result = await read(c);
      expect(result.map((m) => m.workshopId), isNot(contains('200')));
    });

    test('needsUpdate filter keeps needsDownload/hasChanges', () async {
      final c = _containerWithMods(mods);
      c.read(modsFilterStateProvider.notifier).setFilter(ModsFilter.needsUpdate);
      final result = await read(c);
      expect(result.map((m) => m.workshopId), contains('200'));
      expect(result.map((m) => m.workshopId), isNot(contains('300')));
    });

    test('search by name', () async {
      final c = _containerWithMods(mods);
      c.read(modsSearchQueryProvider.notifier).setQuery('brav');
      final result = await read(c);
      expect(result.map((m) => m.name), ['Bravo']);
    });

    test('search by workshopId', () async {
      final c = _containerWithMods(mods);
      c.read(modsSearchQueryProvider.notifier).setQuery('100');
      final result = await read(c);
      expect(result.map((m) => m.workshopId), ['100']);
    });

    test('search no match returns empty', () async {
      final c = _containerWithMods(mods);
      c.read(modsSearchQueryProvider.notifier).setQuery('zzz-nomatch');
      final result = await read(c);
      expect(result, isEmpty);
    });

    test('sort by name ascending (default)', () async {
      final c = _containerWithMods(mods);
      final result = await read(c);
      expect(result.map((m) => m.name), ['alpha', 'Bravo', 'Charlie']);
    });

    test('sort by name descending', () async {
      final c = _containerWithMods(mods);
      c.read(modsSortProvider.notifier).toggle(ModsSortField.name);
      final result = await read(c);
      expect(result.map((m) => m.name), ['Charlie', 'Bravo', 'alpha']);
    });

    test('sort by subscribers ascending and descending', () async {
      final c = _containerWithMods(mods);
      c.read(modsSortProvider.notifier).toggle(ModsSortField.subscribers);
      // default for subscribers is descending
      final desc = await read(c);
      expect(desc.map((m) => m.workshopId), ['200', '100', '300']);
      c.read(modsSortProvider.notifier).toggle(ModsSortField.subscribers);
      final asc = c.read(filteredModsProvider);
      expect(asc.map((m) => m.workshopId), ['300', '100', '200']);
    });

    test('sort by updated ascending and descending', () async {
      final c = _containerWithMods(mods);
      c.read(modsSortProvider.notifier).toggle(ModsSortField.updated);
      final desc = await read(c);
      // descending: highest timeUpdated first; nulls treated as 0
      final ids = desc.map((m) => m.workshopId).toList();
      expect(ids.first, '200'); // timeUpdated 2000 highest
      c.read(modsSortProvider.notifier).toggle(ModsSortField.updated);
      final asc = c.read(filteredModsProvider);
      expect(asc.map((m) => m.workshopId).last, '200');
    });
  });

  group('loading / error providers', () {
    test('modsIsLoading true before resolution, false after', () async {
      final c = _containerWithMods([]);
      c.listen(modsIsLoadingProvider, (_, _) {});
      expect(c.read(modsIsLoadingProvider), isTrue);
      await c.read(detectedModsProvider.future);
      expect(c.read(modsIsLoadingProvider), isFalse);
    });

    test('modsError null when no error', () async {
      final c = _containerWithMods([]);
      await c.read(detectedModsProvider.future);
      expect(c.read(modsErrorProvider), isNull);
    });
  });

  group('count providers', () {
    final mods = [
      _mod(workshopId: '1', name: 'A'),
      _mod(workshopId: '2', name: 'B', isAlreadyImported: true),
      _mod(
        workshopId: '3',
        name: 'C',
        timeUpdated: 5000,
        localFileLastModified: 1000, // needsDownload
      ),
      _mod(workshopId: '4', name: 'D', isHidden: true),
    ];

    test('totalModsCount excludes hidden', () async {
      final c = _containerWithMods(mods);
      expect(await c.read(totalModsCountProvider.future), 3);
    });

    test('hiddenModsCount counts hidden', () async {
      final c = _containerWithMods(mods);
      expect(await c.read(hiddenModsCountProvider.future), 1);
    });

    test('notImportedModsCount respects hidden filter', () async {
      final c = _containerWithMods(mods);
      expect(await c.read(notImportedModsCountProvider.future), 2);
    });

    test('needsUpdateModsCount counts needs-update', () async {
      final c = _containerWithMods(mods);
      expect(await c.read(needsUpdateModsCountProvider.future), 1);
    });
  });

  group('projectsWithPendingChangesCount', () {
    late _MockProjectRepository projectRepo;
    late _MockWorkshopModRepository workshopRepo;
    late _MockCacheRepository cacheRepo;

    setUp(() {
      projectRepo = _MockProjectRepository();
      workshopRepo = _MockWorkshopModRepository();
      cacheRepo = _MockCacheRepository();
    });

    Project project({
      String id = 'p1',
      bool hasModUpdateImpact = false,
      String? sourceFilePath,
      String? modSteamId,
    }) =>
        Project(
          id: id,
          name: 'Proj',
          gameInstallationId: 'gi-1',
          createdAt: 0,
          updatedAt: 0,
          hasModUpdateImpact: hasModUpdateImpact,
          sourceFilePath: sourceFilePath,
          modSteamId: modSteamId,
        );

    ProviderContainer build(List<Project> projects) {
      return _containerWithMods([], extra: [
        projectRepositoryProvider.overrideWithValue(projectRepo),
        workshopModRepositoryProvider.overrideWithValue(workshopRepo),
        modUpdateAnalysisCacheRepositoryProvider
            .overrideWithValue(cacheRepo),
      ]);
    }

    Future<int> count(ProviderContainer c) async {
      c.listen(projectsWithPendingChangesCountProvider, (_, _) {});
      return c.read(projectsWithPendingChangesCountProvider.future);
    }

    test('returns 0 when getAll errors', () async {
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Err(TWMTDatabaseException('boom')),
      );
      final c = build([]);
      expect(await count(c), 0);
    });

    test('counts hasModUpdateImpact projects', () async {
      final projects = [
        project(id: 'a', hasModUpdateImpact: true),
        project(id: 'b', hasModUpdateImpact: true),
        project(id: 'c'), // no impact, no source/steam -> skipped
      ];
      when(() => projectRepo.getAll())
          .thenAnswer((_) async => Ok(projects));
      final c = build(projects);
      expect(await count(c), 2);
    });

    test('skips projects without source/steam ids', () async {
      final projects = [project(id: 'x')];
      when(() => projectRepo.getAll())
          .thenAnswer((_) async => Ok(projects));
      final c = build(projects);
      expect(await count(c), 0);
    });
  });
}
