import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_scan_result.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/projects_data_providers.dart'
    show
        ProjectWithDetails,
        ProjectsWithDetailsNotifier,
        projectsWithDetailsProvider,
        translationStatsVersionProvider;
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart'
    show modsSessionCacheProvider;
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/mods/game_installation_sync_service.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../helpers/mock_providers.dart';

// ---------------------------------------------------------------------------
// Mocks / fakes
// ---------------------------------------------------------------------------

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockGameInstallationSyncService extends Mock
    implements GameInstallationSyncService {}

class MockWorkshopScannerService extends Mock
    implements WorkshopScannerService {}

/// No-op logger so the [DetectedMods] build()/mutators don't crash on the
/// `debug(...)` calls and don't reach `ServiceLocator`.
class _FakeLogger extends Fake implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}
  @override
  void info(String message, [dynamic data]) {}
  @override
  void warning(String message, [dynamic data]) {}
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
  @override
  Stream<LogEntry> get logStream => const Stream.empty();
  @override
  List<LogEntry> get recentLogs => const [];
}

/// Fake [SelectedGame] AsyncNotifier returning a fixed value. `selectedGame`
/// is a codegen AsyncNotifier, so it must be overridden with a notifier
/// factory rather than a closure.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);
  final ConfiguredGame? _value;
  @override
  Future<ConfiguredGame?> build() async => _value;
}

/// Fake [ProjectsWithDetailsNotifier] so the `translationStatsChanged` branch's
/// `ref.invalidate(projectsWithDetailsProvider)` has a harmless target if it is
/// ever listened (the provider hits ServiceLocator in its real build()).
class _FakeProjectsWithDetails extends ProjectsWithDetailsNotifier {
  @override
  Future<List<ProjectWithDetails>> build() async => const [];
}

const _wh3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/wh3',
);

void main() {
  setUpAll(() {
    registerFallbackValue(createMockDetectedMod());
    registerFallbackValue('');
  });

  // -------------------------------------------------------------------------
  // allProjects
  // -------------------------------------------------------------------------
  group('allProjects', () {
    late MockProjectRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = MockProjectRepository();
      container = ProviderContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
      ]);
    });

    tearDown(() => container.dispose());

    test('returns the repository list on Ok', () async {
      final projects = [
        createMockProject(id: 'p1'),
        createMockProject(id: 'p2'),
      ];
      when(() => repo.getAll()).thenAnswer(
          (_) async => Ok<List<Project>, TWMTDatabaseException>(projects));

      final result = await container.read(allProjectsProvider.future);

      expect(result, hasLength(2));
      expect(result.map((p) => p.id), ['p1', 'p2']);
      verify(() => repo.getAll()).called(1);
    });

    test('returns an empty list on Err (swallows the error)', () async {
      when(() => repo.getAll()).thenAnswer((_) async =>
          Err<List<Project>, TWMTDatabaseException>(
              const TWMTDatabaseException('boom')));

      final result = await container.read(allProjectsProvider.future);

      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // modUpdateAvailable (FutureProvider.family)
  // -------------------------------------------------------------------------
  group('modUpdateAvailable', () {
    late MockProjectRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = MockProjectRepository();
      container = ProviderContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
      ]);
    });

    tearDown(() => container.dispose());

    test('true when the project has a non-null sourceModUpdated', () async {
      final project =
          createMockProject(id: 'p1').copyWith(sourceModUpdated: 123456);
      when(() => repo.getById('p1')).thenAnswer(
          (_) async => Ok<Project, TWMTDatabaseException>(project));

      final result = await container.read(modUpdateAvailableProvider('p1').future);

      expect(result, isTrue);
      verify(() => repo.getById('p1')).called(1);
    });

    test('false when sourceModUpdated is null', () async {
      // createMockProject never sets sourceModUpdated, so it stays null.
      final project = createMockProject(id: 'p2');
      when(() => repo.getById('p2')).thenAnswer(
          (_) async => Ok<Project, TWMTDatabaseException>(project));

      final result = await container.read(modUpdateAvailableProvider('p2').future);

      expect(result, isFalse);
    });

    test('false when getById returns Err', () async {
      when(() => repo.getById('missing')).thenAnswer((_) async =>
          Err<Project, TWMTDatabaseException>(
              const TWMTDatabaseException('not found')));

      final result =
          await container.read(modUpdateAvailableProvider('missing').future);

      expect(result, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // modsWithUpdates
  // -------------------------------------------------------------------------
  group('modsWithUpdates', () {
    late MockProjectRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = MockProjectRepository();
      container = ProviderContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
      ]);
    });

    tearDown(() => container.dispose());

    test('keeps only projects with both modSteamId and sourceModUpdated set',
        () async {
      final withUpdate = createMockProject(id: 'has', modSteamId: '111')
          .copyWith(sourceModUpdated: 999);
      // Has steam id but no sourceModUpdated -> excluded.
      final noUpdate = createMockProject(id: 'no-upd', modSteamId: '222');
      // sourceModUpdated set but modSteamId null -> excluded. Built via the
      // constructor: createMockProject defaults modSteamId to '12345' (and
      // copyWith can't set it back to null), so the factory can't express this.
      const noSteam = Project(
        id: 'no-steam',
        name: 'No Steam',
        gameInstallationId: 'g',
        createdAt: 0,
        updatedAt: 0,
        sourceModUpdated: 777,
      );

      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>(
              [withUpdate, noUpdate, noSteam]));

      final result = await container.read(modsWithUpdatesProvider.future);

      expect(result, hasLength(1));
      expect(result.single.id, 'has');
    });

    test('returns empty when no project qualifies', () async {
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>(
              [createMockProject(id: 'p1')]));

      final result = await container.read(modsWithUpdatesProvider.future);

      expect(result, isEmpty);
    });

    test('returns empty when allProjects errors (empty list propagates)',
        () async {
      when(() => repo.getAll()).thenAnswer((_) async =>
          Err<List<Project>, TWMTDatabaseException>(
              const TWMTDatabaseException('boom')));

      final result = await container.read(modsWithUpdatesProvider.future);

      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // UpdateBannerVisible notifier (build + dismiss + reset)
  //
  // Reads modsWithUpdatesProvider (driven via the project repo mock) and
  // SharedPreferences directly (mocked via setMockInitialValues).
  // -------------------------------------------------------------------------
  group('UpdateBannerVisible', () {
    late MockProjectRepository repo;

    const prefsKey = 'update_banner_dismissed_timestamp';

    Project projectWithUpdate(String id) =>
        createMockProject(id: id, modSteamId: '111')
            .copyWith(sourceModUpdated: 999);

    setUp(() {
      repo = MockProjectRepository();
    });

    ProviderContainer makeContainer() => ProviderContainer(overrides: [
          projectRepositoryProvider.overrideWithValue(repo),
        ]);

    test('build() returns false when there are no updates', () async {
      SharedPreferences.setMockInitialValues({});
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>(
              [createMockProject(id: 'p1')])); // no sourceModUpdated
      final container = makeContainer();
      addTearDown(container.dispose);

      final visible =
          await container.read(updateBannerVisibleProvider.future);

      expect(visible, isFalse);
    });

    test('build() returns true when updates exist and never dismissed',
        () async {
      SharedPreferences.setMockInitialValues({}); // dismissedTimestamp == 0
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>([projectWithUpdate('p1')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      final visible =
          await container.read(updateBannerVisibleProvider.future);

      expect(visible, isTrue);
    });

    test('build() returns false when dismissed less than 24h ago', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Dismissed 1 hour ago -> still hidden.
      SharedPreferences.setMockInitialValues({prefsKey: nowSec - 3600});
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>([projectWithUpdate('p1')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      final visible =
          await container.read(updateBannerVisibleProvider.future);

      expect(visible, isFalse);
    });

    test('build() returns true when dismissed more than 24h ago', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Dismissed 48 hours ago -> show again.
      SharedPreferences.setMockInitialValues(
          {prefsKey: nowSec - (48 * 3600)});
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>([projectWithUpdate('p1')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      final visible =
          await container.read(updateBannerVisibleProvider.future);

      expect(visible, isTrue);
    });

    test('dismiss() persists a timestamp and hides the banner', () async {
      SharedPreferences.setMockInitialValues({});
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>([projectWithUpdate('p1')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      // Keep the provider alive across the self-invalidation in dismiss().
      container.listen(updateBannerVisibleProvider, (_, _) {});
      expect(await container.read(updateBannerVisibleProvider.future), isTrue);

      await container.read(updateBannerVisibleProvider.notifier).dismiss();
      await pumpEventQueue();

      // A dismissal timestamp is now stored (non-zero).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(prefsKey), isNotNull);
      expect(prefs.getInt(prefsKey), greaterThan(0));

      // After self-invalidation the banner is hidden (just-dismissed < 24h).
      expect(await container.read(updateBannerVisibleProvider.future), isFalse);
    });

    test('reset() clears the dismissal timestamp', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      SharedPreferences.setMockInitialValues({prefsKey: nowSec});
      when(() => repo.getAll()).thenAnswer((_) async =>
          Ok<List<Project>, TWMTDatabaseException>([projectWithUpdate('p1')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      container.listen(updateBannerVisibleProvider, (_, _) {});
      // Initially dismissed just now -> hidden.
      expect(await container.read(updateBannerVisibleProvider.future), isFalse);

      await container.read(updateBannerVisibleProvider.notifier).reset();
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(prefsKey), isNull);

      // With the timestamp cleared, the banner shows again.
      expect(await container.read(updateBannerVisibleProvider.future), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // DetectedMods notifier
  // -------------------------------------------------------------------------
  group('DetectedMods', () {
    late MockGameInstallationSyncService syncService;
    late MockWorkshopScannerService scanner;

    setUp(() {
      syncService = MockGameInstallationSyncService();
      scanner = MockWorkshopScannerService();
    });

    /// Builds a container wired with the leaf providers DetectedMods reads.
    /// [selectedGame] controls the SelectedGame async value.
    ProviderContainer makeContainer({ConfiguredGame? selectedGame = _wh3}) {
      return ProviderContainer(overrides: [
        loggingServiceProvider.overrideWithValue(_FakeLogger()),
        gameInstallationSyncServiceProvider.overrideWithValue(syncService),
        workshopScannerServiceProvider.overrideWithValue(scanner),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
        projectsWithDetailsProvider.overrideWith(_FakeProjectsWithDetails.new),
      ]);
    }

    test('returns empty list when no game is selected', () async {
      final container = makeContainer(selectedGame: null);
      addTearDown(container.dispose);

      final mods = await container.read(detectedModsProvider.future);

      expect(mods, isEmpty);
      verifyNever(() => syncService.syncGame(any()));
    });

    test('cache-hit path returns cached mods without scanning', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // Pre-seed the (real) session cache for wh3.
      final cached = [
        createMockDetectedMod(workshopId: 'c1'),
        createMockDetectedMod(workshopId: 'c2'),
      ];
      container
          .read(modsSessionCacheProvider.notifier)
          .cacheMods('wh3', cached);

      final mods = await container.read(detectedModsProvider.future);

      expect(mods.map((m) => m.workshopId), ['c1', 'c2']);
      // Cache hit short-circuits before sync/scan.
      verifyNever(() => syncService.syncGame(any()));
      verifyNever(() => scanner.scanMods(any()));
    });

    test('scan path syncs, scans and caches the detected mods', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final scanned = [
        createMockDetectedMod(workshopId: 's1'),
        createMockDetectedMod(workshopId: 's2'),
      ];
      when(() => syncService.syncGame('wh3'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));
      when(() => scanner.scanMods('wh3')).thenAnswer((_) async =>
          Ok<ModScanResult, ServiceException>(
              ModScanResult(mods: scanned)));

      final mods = await container.read(detectedModsProvider.future);

      expect(mods.map((m) => m.workshopId), ['s1', 's2']);
      // The session cache was populated for the game.
      final cache = container.read(modsSessionCacheProvider);
      expect(cache['wh3']?.map((m) => m.workshopId), ['s1', 's2']);
      verify(() => syncService.syncGame('wh3')).called(1);
      verify(() => scanner.scanMods('wh3')).called(1);
    });

    test('returns empty list when sync fails (no scan attempted)', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      when(() => syncService.syncGame('wh3')).thenAnswer((_) async =>
          Err<void, ServiceException>(const ServiceException('sync failed')));

      final mods = await container.read(detectedModsProvider.future);

      expect(mods, isEmpty);
      verify(() => syncService.syncGame('wh3')).called(1);
      verifyNever(() => scanner.scanMods(any()));
    });

    test('scan error returns empty list for a non-RPFM error', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      when(() => syncService.syncGame('wh3'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));
      when(() => scanner.scanMods('wh3')).thenAnswer((_) async =>
          Err<ModScanResult, ServiceException>(
              const ServiceException('scan failed')));

      final mods = await container.read(detectedModsProvider.future);

      expect(mods, isEmpty);
    });

    test('scan error rethrows RpfmNotFoundException', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      when(() => syncService.syncGame('wh3'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));
      when(() => scanner.scanMods('wh3')).thenAnswer((_) async =>
          Err<ModScanResult, ServiceException>(
              const RpfmNotFoundException('rpfm missing')));

      // The family/provider errors on first microtask; reading `.future`
      // directly would hang, so listen + pump and assert via hasError.
      container.listen(detectedModsProvider, (_, _) {});
      await pumpEventQueue();

      final state = container.read(detectedModsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<RpfmNotFoundException>());
    });

    test('translationStatsChanged path increments the stats version', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      expect(container.read(translationStatsVersionProvider), 0);

      when(() => syncService.syncGame('wh3'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));
      when(() => scanner.scanMods('wh3')).thenAnswer((_) async =>
          Ok<ModScanResult, ServiceException>(ModScanResult(
            mods: [createMockDetectedMod(workshopId: 's1')],
            translationStatsChanged: true,
          )));

      await container.read(detectedModsProvider.future);

      expect(container.read(translationStatsVersionProvider), 1);
    });

    test('updateModHidden flips the flag in state and session cache', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // Seed the cache so build() takes the cache-hit path with known mods.
      container.read(modsSessionCacheProvider.notifier).cacheMods('wh3', [
        createMockDetectedMod(workshopId: 'm1', isHidden: false),
        createMockDetectedMod(workshopId: 'm2', isHidden: false),
      ]);
      await container.read(detectedModsProvider.future);

      container
          .read(detectedModsProvider.notifier)
          .updateModHidden('m1', true);

      final state = await container.read(detectedModsProvider.future);
      final m1 = state.firstWhere((m) => m.workshopId == 'm1');
      final m2 = state.firstWhere((m) => m.workshopId == 'm2');
      expect(m1.isHidden, isTrue);
      expect(m2.isHidden, isFalse);

      // Session cache mirrors the change.
      final cached = container.read(modsSessionCacheProvider)['wh3']!;
      expect(cached.firstWhere((m) => m.workshopId == 'm1').isHidden, isTrue);
    });

    test('updateModImported marks the mod imported in state and cache',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(modsSessionCacheProvider.notifier).cacheMods('wh3', [
        createMockDetectedMod(workshopId: 'm1', isAlreadyImported: false),
      ]);
      await container.read(detectedModsProvider.future);

      container
          .read(detectedModsProvider.notifier)
          .updateModImported('m1', 'proj-99');

      final state = await container.read(detectedModsProvider.future);
      final m1 = state.firstWhere((m) => m.workshopId == 'm1');
      expect(m1.isAlreadyImported, isTrue);
      expect(m1.existingProjectId, 'proj-99');

      final cached = container.read(modsSessionCacheProvider)['wh3']!;
      final cachedM1 = cached.firstWhere((m) => m.workshopId == 'm1');
      expect(cachedM1.isAlreadyImported, isTrue);
      expect(cachedM1.existingProjectId, 'proj-99');
    });
  });
}
