# Publish-screen subscriber counts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display the number of Steam Workshop subscribers for each published translation mod on the Publish screen — both per row (new `SUBS` column to the left of `STATUS`) and as a cumulative total in the toolbar leading text.

**Architecture:** A new `keepAlive: true` Riverpod notifier holds a `Map<String, int>` cache of `publishedSteamId → subscribers`, populated once per app session by extending the existing `ModScanBootDialog` with a phase 2 that calls `IWorkshopApiService.getMultipleModInfo` for every published Workshop ID known to the DB. UI cells and the toolbar leading read directly from the cache; no DB schema changes.

**Tech Stack:** Flutter, Riverpod (with `riverpod_annotation` codegen), mocktail, flutter_test, intl (`NumberFormat`). Files live under `lib/features/steam_publish/` and `lib/features/bootstrap/`.

---

## Spec reference

This plan implements the spec at `docs/superpowers/specs/2026-04-25-publish-subscribers-display-design.md`.

## File structure

**New:**
- `lib/features/steam_publish/providers/published_subs_cache_provider.dart` — the cache notifier + the helper that batches Workshop API calls.
- `test/features/steam_publish/providers/published_subs_cache_provider_test.dart` — unit tests for the cache.
- `test/features/steam_publish/widgets/steam_subs_cell_test.dart` — widget tests for `SteamSubsCell`.

**Modified:**
- `lib/providers/shared/service_providers.dart` — register a `workshopApiServiceProvider` Riverpod provider (none exists today; the service is currently only reached via `ServiceLocator.get<IWorkshopApiService>()`).
- `lib/features/steam_publish/providers/steam_publish_providers.dart` — add `filteredPublishableItemsSubsTotalProvider`.
- `lib/features/steam_publish/widgets/steam_publish_list_cells.dart` — add the `SteamSubsCell` widget and a new column entry in `steamPublishColumns`.
- `lib/features/steam_publish/widgets/steam_publish_list.dart` — render `SteamSubsCell` in row builder + add the `'Subs'` header label.
- `lib/features/steam_publish/widgets/steam_publish_toolbar.dart` — extend `SteamPublishToolbarLeading` with a `subsTotal` parameter and append `· N subs` to `countLabel` when > 0.
- `lib/features/steam_publish/screens/steam_publish_screen.dart` — pass the cumulative subs total into `SteamPublishToolbarLeading`.
- `lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart` — convert the dialog to two-phase orchestration (mod scan, then subs refresh).
- `test/features/steam_publish/providers/steam_publish_providers_test.dart` — extend with tests for `filteredPublishableItemsSubsTotalProvider`.

No DB schema changes. No new migration. No changes to repositories, models, or `main.dart`.

## Reference data

Tests and implementation reference these constants. Keep them in sync.

| Concept | Value |
|---|---|
| New column index in `steamPublishColumns` | `3` (between title at `2` and status at the new `4`) |
| New column header label | `'Subs'` |
| Display format | `NumberFormat('#,###', 'en_US').format(n).replaceAll(',', ' ')` — e.g. `1 234` |
| Empty / cache-miss display | `'-'` (single hyphen, faint mono — matches `mods_list.dart` formatting) |
| Cell tooltip | `'Workshop subscribers — last refreshed at app start.'` |
| Dialog title — phase 1 | `'Scanning Workshop mods...'` (unchanged) |
| Dialog title — phase 2 | `'Refreshing subscriber counts...'` |
| TW:WH3 Steam app id (used by Workshop API) | `1142710` (int) |
| API batch limit | `100` (enforced by `WorkshopApiServiceImpl.getMultipleModInfo`) |
| Toolbar segment format | `'· N subs'` (only appended when `N > 0`) |

## Pre-flight

Run code generation before writing any test, and after each task that adds a `@riverpod`-annotated symbol:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The annotation `@Riverpod(keepAlive: true) class PublishedSubsCache extends _$PublishedSubsCache` requires the `_$PublishedSubsCache` base class to be generated; tests that import the provider will fail to compile until codegen has run.

---

## Task 1: Add a Riverpod provider for `IWorkshopApiService`

The cache provider needs to read the Workshop API service via Riverpod (so tests can override it). Today the service is only reachable through `ServiceLocator.get<IWorkshopApiService>()` — there is no `workshopApiServiceProvider`.

**Files:**
- Modify: `lib/providers/shared/service_providers.dart`

- [ ] **Step 1: Add the import**

In `lib/providers/shared/service_providers.dart`, locate the existing import block that already imports steam services. After the existing line:

```dart
import '../../services/steam/i_workshop_publish_service.dart';
```

add this line directly below:

```dart
import '../../services/steam/i_workshop_api_service.dart';
```

- [ ] **Step 2: Register the provider**

After the existing `workshopPublishService` provider block (around lines 176–177):

```dart
@Riverpod(keepAlive: true)
IWorkshopPublishService workshopPublishService(Ref ref) =>
    ServiceLocator.get<IWorkshopPublishService>();
```

append (still at top level, not inside any class):

```dart
@Riverpod(keepAlive: true)
IWorkshopApiService workshopApiService(Ref ref) =>
    ServiceLocator.get<IWorkshopApiService>();
```

- [ ] **Step 3: Run code generation**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: succeeds. `service_providers.g.dart` is regenerated and now exposes `workshopApiServiceProvider`.

- [ ] **Step 4: Smoke check the build**

Run: `flutter analyze lib/providers/shared/service_providers.dart`

Expected: no errors. (Warnings unrelated to this change are acceptable.)

- [ ] **Step 5: Commit**

```bash
git add lib/providers/shared/service_providers.dart lib/providers/shared/service_providers.g.dart
git commit -m "chore: expose IWorkshopApiService as a Riverpod provider"
```

---

## Task 2: Cache provider — initial empty state

Create the keepAlive notifier and lock its initial state with a test.

**Files:**
- Create: `lib/features/steam_publish/providers/published_subs_cache_provider.dart`
- Create: `test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

- [ ] **Step 1: Write the provider scaffold**

Create `lib/features/steam_publish/providers/published_subs_cache_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_subs_cache_provider.g.dart';

/// Session-level cache of Workshop subscriber counts for translation mods
/// the user has published from this app.
///
/// Keys are `publishedSteamId` strings (Workshop item ids of *published
/// translation mods*, distinct from the original game mods). Values are
/// the subscriber counts last fetched from the Steam Workshop API.
///
/// The cache is populated once per app session by `refreshFromWorkshop`,
/// invoked from the boot-time `ModScanBootDialog` after the mod scan
/// completes. It is `keepAlive: true` so revisiting the Publish screen
/// does not retrigger the fetch.
@Riverpod(keepAlive: true)
class PublishedSubsCache extends _$PublishedSubsCache {
  @override
  Map<String, int> build() => const {};

  /// Replace the cache wholesale with the result of a fresh Workshop API
  /// query. On error, the prior state is left untouched.
  Future<void> refreshFromWorkshop() async {
    // Filled in by Task 3.
  }
}
```

- [ ] **Step 2: Run code generation**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: `published_subs_cache_provider.g.dart` is created.

- [ ] **Step 3: Write the failing test**

Create `test/features/steam_publish/providers/published_subs_cache_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';

void main() {
  group('publishedSubsCacheProvider', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(publishedSubsCacheProvider), isEmpty);
    });
  });
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

Expected: PASS. (The scaffold already returns an empty map, so this test passes immediately. It locks the initial state so Task 3 cannot accidentally regress it.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/providers/published_subs_cache_provider.dart \
        lib/features/steam_publish/providers/published_subs_cache_provider.g.dart \
        test/features/steam_publish/providers/published_subs_cache_provider_test.dart
git commit -m "feat(steam_publish): add session cache for published-mod subscriber counts"
```

---

## Task 3: Cache provider — `refreshFromWorkshop` happy path

Implement the fetch logic for the simple case: a handful of published ids, single batched API call, success.

**Files:**
- Modify: `lib/features/steam_publish/providers/published_subs_cache_provider.dart`
- Modify: `test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

- [ ] **Step 1: Add a failing test**

Append to the existing test file (inside `main()`):

```dart
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';
```

> Place these imports at the top of the file alongside the existing ones. Mocktail and the new domain types are needed for the new tests.

Add these mock classes at top-level (above `main()`):

```dart
class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockCompilationRepository extends Mock implements CompilationRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockWorkshopApiService extends Mock implements IWorkshopApiService {}

class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);
  final ConfiguredGame? _value;
  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _gameWh3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/games/wh3',
);

GameInstallation _installation({String id = 'install-wh3'}) =>
    GameInstallation(
      id: id,
      gameCode: 'wh3',
      gameName: 'WH3',
      createdAt: 0,
      updatedAt: 0,
    );

Project _project({
  required String id,
  String? publishedSteamId,
}) =>
    Project(
      id: id,
      name: id,
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
    );

Compilation _compilation({
  required String id,
  String? publishedSteamId,
}) =>
    Compilation(
      id: id,
      name: 'C-$id',
      prefix: '!',
      packName: 'pack-$id',
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
    );

WorkshopModInfo _modInfo({
  required String id,
  required int subs,
}) =>
    WorkshopModInfo(
      workshopId: id,
      title: 'Mod $id',
      workshopUrl: 'https://example/$id',
      subscriptions: subs,
      appId: 1142710,
    );

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required CompilationRepository compilationRepo,
  required GameInstallationRepository gameInstallationRepo,
  required IWorkshopApiService workshopApi,
  ConfiguredGame? selectedGame = _gameWh3,
}) {
  final container = ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWithValue(projectRepo),
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
      workshopApiServiceProvider.overrideWithValue(workshopApi),
      selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
    ],
  );
  return container;
}
```

> The `Project` and `Compilation` constructors require any other mandatory fields; if the analyzer flags missing required parameters, copy the missing fields from the corresponding factories in `test/features/home/providers/workflow_providers_test.dart`.

Inside `main()`, after the existing `'starts empty'` test, append:

```dart
    test('refreshFromWorkshop populates cache with subscriber counts from API',
        () async {
      final projectRepo = _MockProjectRepository();
      final compilationRepo = _MockCompilationRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final workshopApi = _MockWorkshopApiService();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'p1', publishedSteamId: '111'),
          _project(id: 'p2', publishedSteamId: '222'),
          _project(id: 'p3'), // unpublished — must not be queried
        ]),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>([
          _compilation(id: 'c1', publishedSteamId: '333'),
        ]),
      );
      when(() => workshopApi.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'),
            appId: any(named: 'appId'),
          )).thenAnswer(
        (_) async => Ok<List<WorkshopModInfo>, SteamServiceException>([
          _modInfo(id: '111', subs: 1234),
          _modInfo(id: '222', subs: 50),
          _modInfo(id: '333', subs: 9999),
        ]),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        compilationRepo: compilationRepo,
        gameInstallationRepo: gameInstallRepo,
        workshopApi: workshopApi,
      );
      addTearDown(container.dispose);

      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();

      final state = container.read(publishedSubsCacheProvider);
      expect(state, {'111': 1234, '222': 50, '333': 9999});

      final captured = verify(() => workshopApi.getMultipleModInfo(
            workshopIds: captureAny(named: 'workshopIds'),
            appId: 1142710,
          )).captured.single as List<String>;
      expect(captured.toSet(), {'111', '222', '333'});
    });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart --plain-name "populates cache"`

Expected: FAIL — `state` is `{}` because `refreshFromWorkshop` is still a no-op.

- [ ] **Step 3: Implement `refreshFromWorkshop`**

Edit `lib/features/steam_publish/providers/published_subs_cache_provider.dart`. Add these imports at the top:

```dart
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/steam/models/game_definitions.dart';
```

Replace the placeholder `refreshFromWorkshop` body with:

```dart
  Future<void> refreshFromWorkshop() async {
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) return;

    final game = getGameByCode(selectedGame.code);
    if (game == null) return;
    final appId = int.tryParse(game.steamAppId);
    if (appId == null) return;

    final installRepo = ref.read(gameInstallationRepositoryProvider);
    final installResult = await installRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return;
    final installationId = installResult.value.id;

    final ids = <String>{};

    final projectRepo = ref.read(projectRepositoryProvider);
    final projectsResult =
        await projectRepo.getByGameInstallation(installationId);
    if (projectsResult.isOk) {
      for (final p in projectsResult.value) {
        final id = p.publishedSteamId;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }

    final compilationRepo = ref.read(compilationRepositoryProvider);
    final compsResult =
        await compilationRepo.getByGameInstallation(installationId);
    if (compsResult.isOk) {
      for (final c in compsResult.value) {
        final id = c.publishedSteamId;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }

    if (ids.isEmpty) {
      state = const {};
      return;
    }

    final api = ref.read(workshopApiServiceProvider);
    final result = await api.getMultipleModInfo(
      workshopIds: ids.toList(),
      appId: appId,
    );
    if (result.isErr) return;

    final next = <String, int>{};
    for (final info in result.value) {
      final subs = info.subscriptions;
      if (subs != null) next[info.workshopId] = subs;
    }
    state = next;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart --plain-name "populates cache"`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/providers/published_subs_cache_provider.dart \
        test/features/steam_publish/providers/published_subs_cache_provider_test.dart
git commit -m "feat(steam_publish): fetch and cache subscriber counts from Workshop API"
```

---

## Task 4: Cache provider — failure leaves state untouched

A network or rate-limit error must not wipe an already-populated cache.

**Files:**
- Modify: `test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

- [ ] **Step 1: Add a failing test**

The notifier's `state` setter is `@protected` in Riverpod 2.x with `@Riverpod`-annotated `Notifier` subclasses, so we cannot pre-seed the cache by direct assignment. Instead, this test runs `refreshFromWorkshop` twice — the first call succeeds and populates the cache, the second call fails — and asserts that the second (failing) call leaves the state from the first call intact.

Append after the previous test:

```dart
    test('refreshFromWorkshop leaves prior state untouched on API failure',
        () async {
      final projectRepo = _MockProjectRepository();
      final compilationRepo = _MockCompilationRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final workshopApi = _MockWorkshopApiService();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'p1', publishedSteamId: '111'),
        ]),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(const []),
      );

      var callCount = 0;
      when(() => workshopApi.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'),
            appId: any(named: 'appId'),
          )).thenAnswer((_) async {
        callCount += 1;
        if (callCount == 1) {
          return Ok<List<WorkshopModInfo>, SteamServiceException>([
            _modInfo(id: '111', subs: 999),
          ]);
        }
        return Err<List<WorkshopModInfo>, SteamServiceException>(
          const WorkshopApiException('boom'),
        );
      });

      final container = _makeContainer(
        projectRepo: projectRepo,
        compilationRepo: compilationRepo,
        gameInstallationRepo: gameInstallRepo,
        workshopApi: workshopApi,
      );
      addTearDown(container.dispose);

      // First call — succeeds, populates cache.
      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
      expect(container.read(publishedSubsCacheProvider), {'111': 999});

      // Second call — API fails. Cache must not be cleared.
      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
      expect(container.read(publishedSubsCacheProvider), {'111': 999});
    });
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart --plain-name "untouched on API failure"`

Expected: PASS already, because the implementation in Task 3 contains `if (result.isErr) return;` before mutating `state`. This test locks that behaviour.

If it fails: review Task 3 step 3 — the `if (result.isErr) return;` guard must come before the `state = next;` assignment.

- [ ] **Step 3: Commit**

```bash
git add test/features/steam_publish/providers/published_subs_cache_provider_test.dart
git commit -m "test(steam_publish): pin failure-resilience of subscriber cache"
```

---

## Task 5: Cache provider — chunk >100 IDs into multiple API calls

`WorkshopApiServiceImpl.getMultipleModInfo` rejects requests with >100 ids. Users with many published translations need batching.

**Files:**
- Modify: `lib/features/steam_publish/providers/published_subs_cache_provider.dart`
- Modify: `test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

- [ ] **Step 1: Add a failing test**

Append after the previous test:

```dart
    test('refreshFromWorkshop splits >100 ids into multiple API calls',
        () async {
      final projectRepo = _MockProjectRepository();
      final compilationRepo = _MockCompilationRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final workshopApi = _MockWorkshopApiService();

      // 150 published projects → must split into 100 + 50.
      final projects = List<Project>.generate(
        150,
        (i) => _project(id: 'p$i', publishedSteamId: '${1000 + i}'),
      );

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>(projects),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(const []),
      );
      when(() => workshopApi.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'),
            appId: any(named: 'appId'),
          )).thenAnswer((invocation) async {
        final ids = invocation.namedArguments[#workshopIds] as List<String>;
        return Ok<List<WorkshopModInfo>, SteamServiceException>(
          [for (final id in ids) _modInfo(id: id, subs: 1)],
        );
      });

      final container = _makeContainer(
        projectRepo: projectRepo,
        compilationRepo: compilationRepo,
        gameInstallationRepo: gameInstallRepo,
        workshopApi: workshopApi,
      );
      addTearDown(container.dispose);

      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();

      // Two API calls expected: one of size 100, one of size 50.
      final calls = verify(() => workshopApi.getMultipleModInfo(
            workshopIds: captureAny(named: 'workshopIds'),
            appId: 1142710,
          )).captured;
      expect(calls.length, 2);
      final sizes = calls
          .map((e) => (e as List<String>).length)
          .toList()
        ..sort();
      expect(sizes, [50, 100]);

      // Cache holds all 150 entries.
      expect(container.read(publishedSubsCacheProvider).length, 150);
    });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart --plain-name "splits >100 ids"`

Expected: FAIL — the current implementation issues a single call with 150 ids; depending on mocktail behaviour the call goes through but `calls.length == 1`.

- [ ] **Step 3: Implement chunking**

In `published_subs_cache_provider.dart`, replace the body that runs after `if (ids.isEmpty)`:

```dart
    if (ids.isEmpty) {
      state = const {};
      return;
    }

    final api = ref.read(workshopApiServiceProvider);
    final next = <String, int>{};
    final idList = ids.toList();
    const chunkSize = 100;
    for (var i = 0; i < idList.length; i += chunkSize) {
      final end = (i + chunkSize) > idList.length ? idList.length : i + chunkSize;
      final chunk = idList.sublist(i, end);
      final result = await api.getMultipleModInfo(
        workshopIds: chunk,
        appId: appId,
      );
      if (result.isErr) return; // leave prior state untouched
      for (final info in result.value) {
        final subs = info.subscriptions;
        if (subs != null) next[info.workshopId] = subs;
      }
    }
    state = next;
```

- [ ] **Step 4: Run all cache provider tests**

Run: `flutter test test/features/steam_publish/providers/published_subs_cache_provider_test.dart`

Expected: all four tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/providers/published_subs_cache_provider.dart \
        test/features/steam_publish/providers/published_subs_cache_provider_test.dart
git commit -m "feat(steam_publish): chunk subscriber-count fetches at 100 ids per request"
```

---

## Task 6: Cumulative subs total provider

A derived provider that sums subscribers across the currently filtered list.

**Files:**
- Modify: `lib/features/steam_publish/providers/steam_publish_providers.dart`
- Modify: `test/features/steam_publish/providers/steam_publish_providers_test.dart`

- [ ] **Step 1: Write the failing test**

Add these imports at the top of `test/features/steam_publish/providers/steam_publish_providers_test.dart`:

```dart
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/domain/project.dart';
```

Add this test-helper `Notifier` subclass at top-level (above `main()`). It pre-seeds `build()` so the test does not need to mutate the `state` setter directly (which is `@protected` on `@Riverpod`-generated `Notifier` subclasses):

```dart
class _StubSubsCache extends PublishedSubsCache {
  _StubSubsCache(this._initial);
  final Map<String, int> _initial;

  @override
  Map<String, int> build() => _initial;
}

PublishableItem _stubItem({required String? publishedSteamId}) {
  return ProjectPublishItem(
    export: null,
    project: Project(
      id: 'p-${publishedSteamId ?? "none"}',
      name: 'P',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
    ),
    languageCodes: const ['en'],
  );
}
```

Inside the existing `main()` block (before the closing `}` of `main`), append a new `group`:

```dart
  group('filteredPublishableItemsSubsTotalProvider', () {
    test('sums cache values across filtered items, ignoring missing ids', () {
      final container = ProviderContainer(
        overrides: [
          // Stub the upstream filtered-items list. Each item exposes the
          // `publishedSteamId` we care about; other fields are irrelevant.
          filteredPublishableItemsProvider.overrideWith((ref) => [
                _stubItem(publishedSteamId: '111'),
                _stubItem(publishedSteamId: '222'),
                _stubItem(publishedSteamId: '333'), // not in cache
                _stubItem(publishedSteamId: null), // unpublished
              ]),
          publishedSubsCacheProvider.overrideWith(
            () => _StubSubsCache(const {'111': 100, '222': 50}),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(filteredPublishableItemsSubsTotalProvider),
        150,
      );
    });

    test('returns 0 when cache is empty', () {
      final container = ProviderContainer(
        overrides: [
          filteredPublishableItemsProvider.overrideWith((ref) => [
                _stubItem(publishedSteamId: '111'),
              ]),
          publishedSubsCacheProvider.overrideWith(
            () => _StubSubsCache(const {}),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(filteredPublishableItemsSubsTotalProvider), 0);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/providers/steam_publish_providers_test.dart --plain-name "filteredPublishableItemsSubsTotalProvider"`

Expected: FAIL — `filteredPublishableItemsSubsTotalProvider` is not defined.

- [ ] **Step 3: Implement the provider**

In `lib/features/steam_publish/providers/steam_publish_providers.dart`, add this import at the top:

```dart
import 'published_subs_cache_provider.dart';
```

At the very bottom of the file (after `noPackPublishableItemsCount`), append:

```dart
/// Sum of subscriber counts across the currently filtered publishable items,
/// resolved against the session-level [publishedSubsCacheProvider]. Items
/// without a `publishedSteamId` or absent from the cache contribute 0.
@riverpod
int filteredPublishableItemsSubsTotal(Ref ref) {
  final items = ref.watch(filteredPublishableItemsProvider);
  final cache = ref.watch(publishedSubsCacheProvider);
  if (items.isEmpty || cache.isEmpty) return 0;
  var sum = 0;
  for (final item in items) {
    final id = item.publishedSteamId;
    if (id == null || id.isEmpty) continue;
    sum += cache[id] ?? 0;
  }
  return sum;
}
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/providers/steam_publish_providers_test.dart`

Expected: all tests PASS (existing + the two new ones).

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/providers/steam_publish_providers.dart \
        lib/features/steam_publish/providers/steam_publish_providers.g.dart \
        test/features/steam_publish/providers/steam_publish_providers_test.dart
git commit -m "feat(steam_publish): derive cumulative subs total across filtered items"
```

---

## Task 7: `SteamSubsCell` widget

Render the subscriber count for a single row.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`
- Create: `test/features/steam_publish/widgets/steam_subs_cell_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/steam_publish/widgets/steam_subs_cell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_list_cells.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectPublishItem _project({String? publishedSteamId}) => ProjectPublishItem(
      export: null,
      project: Project(
        id: 'p1',
        name: 'P1',
        gameInstallationId: 'g',
        createdAt: 0,
        updatedAt: 0,
        publishedSteamId: publishedSteamId,
        publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
      ),
      languageCodes: const ['en'],
    );

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('SteamSubsCell shows "-" when item is unpublished',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      SteamSubsCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('SteamSubsCell shows "-" when published but cache has no entry',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      SteamSubsCell(item: _project(publishedSteamId: '999')),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('SteamSubsCell formats the count with non-breaking spaces',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        publishedSubsCacheProvider.overrideWith(
          () => _StubCache({'42': 1234}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SteamSubsCell(item: _project(publishedSteamId: '42')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 234'), findsOneWidget);
  });
}

class _StubCache extends PublishedSubsCache {
  _StubCache(this._initial);
  final Map<String, int> _initial;

  @override
  Map<String, int> build() => _initial;
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/widgets/steam_subs_cell_test.dart`

Expected: FAIL — `SteamSubsCell` is not defined.

- [ ] **Step 3: Add the cell widget**

In `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`, add these imports near the top alongside the existing ones:

```dart
import 'package:intl/intl.dart';
import '../providers/published_subs_cache_provider.dart';
```

> `intl` is already a transitive dependency (used in `mods_list.dart:392`); no `pubspec.yaml` change needed.

Append this widget at the end of the file:

```dart
// =============================================================================
// Subs cell
// =============================================================================

/// Renders the Workshop subscriber count for the published translation mod.
/// Reads from [publishedSubsCacheProvider]; shows `-` for unpublished items
/// and for cache misses (e.g. before the boot-time refresh has resolved, or
/// when the API skipped the id).
class SteamSubsCell extends ConsumerWidget {
  final PublishableItem item;

  const SteamSubsCell({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final id = item.publishedSteamId;
    final cache = ref.watch(publishedSubsCacheProvider);

    final int? subs = (id != null && id.isNotEmpty) ? cache[id] : null;

    final String label = subs == null
        ? '-'
        : NumberFormat('#,###', 'en_US').format(subs).replaceAll(',', ' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message:
            'Workshop subscribers — last refreshed at app start.',
        waitDuration: const Duration(milliseconds: 400),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: subs == null ? tokens.textFaint : tokens.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/widgets/steam_subs_cell_test.dart`

Expected: all three tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_list_cells.dart \
        test/features/steam_publish/widgets/steam_subs_cell_test.dart
git commit -m "feat(steam_publish): add SteamSubsCell rendering subscriber counts"
```

---

## Task 8: Wire the SUBS column into the list

Insert the new column at index 3 (left of STATUS), update the row builder and header.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`
- Modify: `lib/features/steam_publish/widgets/steam_publish_list.dart`

- [ ] **Step 1: Update the column list**

In `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`, locate `steamPublishColumns` (around lines 26–33) and replace the entire list:

```dart
const List<ListRowColumn> steamPublishColumns = [
  ListRowColumn.fixed(40),  // checkbox
  ListRowColumn.fixed(80),  // cover
  ListRowColumn.flex(3),    // title + filename
  ListRowColumn.fixed(100), // subs (new)
  ListRowColumn.fixed(160), // status
  ListRowColumn.fixed(180), // last published — fits "Outdated · 12 months"
  ListRowColumn.fixed(180), // action
];
```

- [ ] **Step 2: Insert the cell into the row builder**

In `lib/features/steam_publish/widgets/steam_publish_list.dart`, locate the `children: [...]` list inside `ListRow` (around lines 43–53) and insert `SteamSubsCell(item: item),` between `SteamTitleBlock` and `SteamStateCell`:

```dart
              children: [
                SteamSelectionCheckbox(
                  selected: selected,
                  onToggle: () => _toggleSelection(ref, item.itemId),
                ),
                SteamCoverCell(item: item),
                SteamTitleBlock(item: item),
                SteamSubsCell(item: item),
                SteamStateCell(item: item),
                SteamLastPublishedCell(item: item),
                SteamActionCell(item: item),
              ],
```

- [ ] **Step 3: Update the header labels**

In the same file, locate `_SteamPublishListHeader.build` (around lines 76–91) and update the `labels:` list to include `'Subs'` between `'Pack'` and `'Status'`:

```dart
    return ListRowHeader(
      columns: steamPublishColumns,
      labels: const [
        '',
        '',
        'Pack',
        'Subs',
        'Status',
        'Last published',
        '',
      ],
    );
```

- [ ] **Step 4: Smoke check the file builds**

Run: `flutter analyze lib/features/steam_publish/widgets/steam_publish_list.dart lib/features/steam_publish/widgets/steam_publish_list_cells.dart`

Expected: no errors.

- [ ] **Step 5: Run the full Steam Publish test suite**

Run: `flutter test test/features/steam_publish/`

Expected: all tests PASS. (Pre-existing tests use `steamPublishColumns` only by reference; the new column does not break them.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_list.dart \
        lib/features/steam_publish/widgets/steam_publish_list_cells.dart
git commit -m "feat(steam_publish): add Subs column between Pack and Status"
```

---

## Task 9: Toolbar leading — append `· N subs`

Show the cumulative total in `SteamPublishToolbarLeading`, but only when > 0.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_toolbar.dart`
- Modify: `lib/features/steam_publish/screens/steam_publish_screen.dart`

- [ ] **Step 1: Extend `SteamPublishToolbarLeading`**

In `lib/features/steam_publish/widgets/steam_publish_toolbar.dart`, locate `class SteamPublishToolbarLeading` (around lines 161–189). Add a `subsTotal` field, a constructor parameter, and update `countLabel` construction:

```dart
class SteamPublishToolbarLeading extends StatelessWidget {
  final int totalItems;
  final int filteredItems;
  final int selectedCount;
  final bool searchActive;
  final int subsTotal;

  const SteamPublishToolbarLeading({
    super.key,
    required this.totalItems,
    required this.filteredItems,
    required this.selectedCount,
    required this.searchActive,
    this.subsTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    final packLabel = totalItems == 1 ? 'pack' : 'packs';
    final base = searchActive
        ? '$filteredItems / $totalItems $packLabel'
        : '$totalItems $packLabel';
    final selectedSegment =
        selectedCount > 0 ? ' · $selectedCount selected' : '';
    final subsSegment = subsTotal > 0
        ? ' · ${NumberFormat('#,###', 'en_US').format(subsTotal).replaceAll(',', ' ')} subs'
        : '';
    return ListToolbarLeading(
      icon: FluentIcons.cloud_arrow_up_24_regular,
      title: 'Publish on Steam',
      countLabel: '$base$selectedSegment$subsSegment',
    );
  }
}
```

Add at the top of the file alongside the existing imports:

```dart
import 'package:intl/intl.dart';
```

- [ ] **Step 2: Pass the value from the screen**

In `lib/features/steam_publish/screens/steam_publish_screen.dart`, locate `build()` (around lines 58–85). Add a watch on the new total provider near the top of `build`:

```dart
    final subsTotal = ref.watch(filteredPublishableItemsSubsTotalProvider);
```

(Place it just after the existing `final outdatedCount = ...` and `final noPackCount = ...` lines.)

Then update the `SteamPublishToolbarLeading(...)` invocation inside `HomeBackToolbar.leading` (around lines 79–84) to pass it:

```dart
            leading: SteamPublishToolbarLeading(
              totalItems: allItems.length,
              filteredItems: filteredItems.length,
              selectedCount: selection.length,
              searchActive: searchQuery.isNotEmpty,
              subsTotal: subsTotal,
            ),
```

- [ ] **Step 3: Smoke check both files compile**

Run: `flutter analyze lib/features/steam_publish/widgets/steam_publish_toolbar.dart lib/features/steam_publish/screens/steam_publish_screen.dart`

Expected: no errors.

- [ ] **Step 4: Run the full Steam Publish test suite**

Run: `flutter test test/features/steam_publish/`

Expected: PASS. The default value `subsTotal = 0` keeps existing tests valid (the segment is only appended when > 0).

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_toolbar.dart \
        lib/features/steam_publish/screens/steam_publish_screen.dart
git commit -m "feat(steam_publish): show cumulative subscriber total in toolbar leading"
```

---

## Task 10: Boot dialog — phase-2 orchestration

Hold the dialog open through the subs refresh, change its title from "Scanning Workshop mods..." to "Refreshing subscriber counts..." between phases.

**Files:**
- Modify: `lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart`

- [ ] **Step 1: Convert the dialog to two-phase orchestration**

Replace the entire body of `_ModScanBootDialogState` in `lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart`:

```dart
class _ModScanBootDialogState extends ConsumerState<ModScanBootDialog> {
  bool _closed = false;
  String _title = 'Scanning Workshop mods...';
  bool _phaseTwoStarted = false;

  void _closeIfMounted() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _runPhaseTwo() async {
    if (_phaseTwoStarted) return;
    _phaseTwoStarted = true;
    if (!mounted) return;
    setState(() {
      _title = 'Refreshing subscriber counts...';
    });
    try {
      await ref
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
    } catch (_) {
      // Subscriber refresh is best-effort. Log path is inside the API service.
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _closeIfMounted());
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1: subscribe to the mods scan. Once it resolves, kick off phase 2
    // (subscriber refresh) without closing the dialog. Phase 2 closes the
    // dialog when it resolves.
    ref.listen<AsyncValue<List<DetectedMod>>>(detectedModsProvider,
        (prev, next) {
      if ((next.hasValue && !next.isLoading) || next.hasError) {
        unawaited(_runPhaseTwo());
      }
    });

    final scanLogStream = ref.watch(scanLogStreamProvider);

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ScanTerminalWidget(
          logStream: scanLogStream,
          title: _title,
        ),
      ),
    );
  }
}
```

Add these imports at the top of the file alongside the existing ones:

```dart
import 'dart:async';

import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
```

- [ ] **Step 2: Smoke check the file compiles**

Run: `flutter analyze lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart`

Expected: no errors.

- [ ] **Step 3: Manual verification**

Run: `flutter run -d windows` (per `CLAUDE.md` build instructions).

Expected behaviour:
1. Boot dialog opens with the terminal stream and the title `Scanning Workshop mods...`.
2. When the mod scan finishes, the title flips to `Refreshing subscriber counts...` while the terminal stays visible (with its final scan logs).
3. Within ~1 s (single batched API call for typical user counts), the dialog closes and the user lands on Home.
4. Open the Publish screen and confirm:
   - The new `Subs` column header appears between `Pack` and `Status`.
   - Rows for projects/compilations with a `publishedSteamId` show a number (formatted `1 234`) or `-` if the API did not return that id.
   - The toolbar leading now reads, for example, `12 packs · 4 567 subs` (or just `12 packs` if no subs were fetched).

If an integration test for `ModScanBootDialog` exists and breaks, update it to assert that after `detectedModsProvider` resolves, the dialog title transitions to the phase-2 string before closing. (At plan-write time no such test exists, so this is a no-op for current tests.)

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`

Expected: all tests PASS. No new test is added in this task because the dialog has no isolated unit-test harness in the repo today; the manual verification in step 3 covers the integration. If you want regression coverage, add a widget test under `test/features/bootstrap/` that mounts the dialog with an overridden `detectedModsProvider` resolving immediately to `[]`, and verify the title transitions then closes — but this is optional and not required by the spec.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart
git commit -m "feat(bootstrap): refresh published-mod subscriber counts after mod scan"
```

---

## Task 11: Verification & wrap-up

A final pass to make sure everything composes.

- [ ] **Step 1: Re-run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: clean — no further changes to `*.g.dart` files. If any `.g.dart` files changed, commit them as part of the verification commit below.

- [ ] **Step 2: Run analyzer over the touched directories**

Run: `flutter analyze lib/features/steam_publish/ lib/features/bootstrap/ lib/providers/shared/`

Expected: no errors. (Pre-existing warnings unrelated to this work are acceptable.)

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`

Expected: all tests PASS.

- [ ] **Step 4: Manual verification (golden path)**

If not already done in Task 10 step 3, run `flutter run -d windows` and walk through:
- Boot dialog two-phase title transition.
- Publish screen `Subs` column populated for at least one published item.
- Toolbar leading shows `· N subs` segment.
- Filter the list (e.g. switch to `Outdated`) and confirm the cumulative subs total updates to reflect only the filtered rows.
- Click the toolbar Refresh button and confirm rows still show their subs (the cache survives `ref.invalidate(publishableItemsProvider)` because it lives on a separate provider).

- [ ] **Step 5: Edge case — no published items**

In a fresh app session with a game that has zero published translation mods, confirm:
- The boot dialog phase 2 still runs (title flip to `Refreshing subscriber counts...` is visible briefly, then the dialog closes).
- The Publish screen shows `-` in every row's `Subs` column.
- The toolbar leading does NOT show a `· N subs` segment (because the sum is 0).

- [ ] **Step 6: Edge case — offline / API failure**

Disconnect the network, restart the app, and confirm:
- The boot dialog still progresses to phase 2 and then closes (it does not hang).
- The Publish screen renders `-` in every row.
- The toolbar leading shows no `· N subs` segment.

- [ ] **Step 7: Final commit (if any uncommitted artefacts)**

```bash
git status
```

If `git status` shows uncommitted generated `.g.dart` files or formatter-only changes, commit them:

```bash
git add -- '*.g.dart'
git commit -m "chore: regenerate riverpod sources for published-subs feature"
```

If `git status` is clean, skip this step.

---

## Spec coverage map

| Spec section | Task(s) |
|---|---|
| §1 In-memory cache provider — initial empty state | Task 2 |
| §1 In-memory cache provider — `refreshFromWorkshop` happy path | Task 3 |
| §1 In-memory cache provider — failure resilience | Task 4 |
| §2 Service helper (chunking ≤100 ids) | Task 5 |
| §3 Bootstrap integration (two-phase dialog) | Task 10 |
| §4 SUBS column (left of STATUS) | Tasks 7–8 |
| §5 Toolbar leading cumulative total | Tasks 6 + 9 |
| §6 Refresh button behaviour (no-op for subs) | No code change required (existing behaviour is correct) |
| Error handling matrix | Tasks 4, 10, 11 (manual offline check) |
| Testing requirements | Tasks 2–7 (unit + widget tests); Task 10 (manual integration); Task 11 (final pass) |
| Workshop API service Riverpod wiring (prerequisite) | Task 1 |
