# Dependency Injection Strategy

This app uses a deliberately hybrid DI setup: **GetIt** for the infrastructure
layer and **Riverpod** for the application layer, with a thin set of bridge
files exposing every GetIt-registered dependency to Riverpod consumers. UI
code only ever talks to Riverpod.

## Two layers, two tools

### Infrastructure layer (GetIt via `ServiceLocator`)

- `DatabaseService` — singleton tied to the `dart:io` lifecycle.
- Repositories — hold a DB reference and need app-wide singleton lifetime.
- Core services instantiated at app startup, before the `ProviderScope` wraps
  the widget tree (e.g. `SteamCmdManager`, `RpfmService`, settings/migrations).

These are wired up in `lib/services/service_locator.dart` during `main()`.

### Application layer (Riverpod)

- All UI providers under `lib/features/**` and `lib/widgets/**`.
- All business-logic orchestration that composes repositories or services.
- New services default to Riverpod unless they must exist *before* the
  `ProviderScope` is mounted.

## The bridge

Three files under `lib/providers/shared/` expose every GetIt-registered
dependency as a Riverpod provider. UI code must **never** call
`ServiceLocator` directly; it always goes through these bridge providers.

| File | Purpose |
| --- | --- |
| `lib/providers/shared/repository_providers.dart` | Exposes the 8 core repositories (Project, ProjectLanguage, Language, GameInstallation, Compilation, TranslationVersion, TranslationUnit, WorkshopMod) plus a few shared async queries (`allLanguages`, `activeLanguages`, `allGameInstallations`). |
| `lib/providers/shared/service_providers.dart` | Exposes ~37 services and the remaining repositories (Glossary, ExportHistory, ModUpdateAnalysisCache, TranslationVersionHistory, TranslationMemory, TranslationBatchUnit, TranslationBatch, ModVersion, LlmProviderModel). |
| `lib/providers/shared/logging_providers.dart` | Hand-written `Provider<ILoggingService>` for the logger. Hand-written rather than codegen'd because it's the bootstrap dependency that tests most often override. |

The pattern in both codegen'd files is uniform:

```dart
@Riverpod(keepAlive: true)
ProjectRepository projectRepository(Ref ref) =>
    ServiceLocator.get<ProjectRepository>();
```

`keepAlive: true` is correct here: the underlying GetIt instance lives for
the whole app, so there is nothing to dispose with the provider.

### Adding a new bridge provider

Default to `@Riverpod(keepAlive: true)` codegen in `service_providers.dart`
or `repository_providers.dart`. Reach for a hand-written
`Provider<T>((ref) => ...)` (like `loggingServiceProvider`) only when the
provider must be constructible before Riverpod code generation has run — in
practice, that's the logger and a handful of test-overridden bootstrap
dependencies.

## Naming convention

Riverpod codegen turns the function name into `<name>Provider`. For
interface-typed services we **drop the leading `I`** so the symbol reads
naturally:

| Dart type | Riverpod symbol |
| --- | --- |
| `IGlossaryService` | `glossaryServiceProvider` |
| `IFileService` | `fileServiceProvider` |
| `IRpfmService` | `rpfmServiceProvider` |
| `ILoggingService` | `loggingServiceProvider` |

The function declares the interface as its return type, but the Riverpod
symbol uses the bare name.

## Ref discipline

The two `ref` methods are not interchangeable. Use the right one for the
calling context:

- **`ref.watch`** — reactive subscription. Use inside:
  - `@riverpod` function provider bodies
  - `Notifier.build()` methods
  - widget `build()` methods (via `ConsumerWidget` / `Consumer`)
- **`ref.read`** — one-shot read, no subscription. Use inside:
  - Notifier mutator methods (`addX`, `delete`, `refresh`, ...)
  - imperative widget event handlers (`onPressed`, `onTap`, ...)
  - async callbacks and timers

Calling `ref.watch` from a mutator or event handler will rebuild the wrong
thing or throw; calling `ref.read` from a `build` method silently breaks
reactivity. Lints catch the worst cases but reviewers should still check.

## Collision handling

Two situations come up when introducing a bridge provider next to existing
feature code:

**1. A feature file already declares a `@riverpod` wrapper whose codegen'd
symbol collides with a bridge symbol.** Import the bridge with an alias and
have the wrapper delegate to it. External callers keep working, but the
wrapper now routes through the canonical bridge instance.

```dart
import 'package:.../providers/shared/service_providers.dart' as bridge;

@riverpod
IHistoryService historyService(Ref ref) =>
    ref.watch(bridge.historyServiceProvider);
```

**2. A consumer file imports both the bridge and a legacy feature file that
re-declares the same symbol.** Use `hide` on the legacy import so the bridge
wins:

```dart
import '.../legacy_providers.dart' hide historyServiceProvider;
import '.../providers/shared/service_providers.dart';
```

These wrappers are intentionally pass-through — see *Current debt* below for
candidates to inline.

## Test bootstrapping

Any test that pumps a widget reading a bridge provider must override that
provider, otherwise the widget hits `ServiceLocator` against an
uninitialised GetIt instance and throws. Pass overrides through the
`overrides:` parameter of `createTestableWidget`:

```dart
await tester.pumpWidget(
  createTestableWidget(
    const MyScreen(),
    overrides: [
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ],
  ),
);
```

Use `test/helpers/fakes/fake_logger.dart::FakeLogger` as the default
silent fake for the logger.

## Why keep GetIt at all?

The DB and some OS-level integrations (`SteamCmdManager`, `RpfmService`)
need deterministic initialisation order at app startup, *before* Riverpod's
`ProviderScope` wraps the widget tree. GetIt handles that cleanly without
forcing those services to become async/lazy Riverpod providers.

## Current debt

Known follow-ups left on the table after the bridge migration:

- **Pass-through UI wrappers.** Several feature-local `@riverpod` wrappers
  (`historyServiceProvider`, `releaseNotesServiceProvider`,
  `gameLocalizationServiceProvider`, ...) now do nothing but
  `ref.watch(bridge.xxxProvider)`. Consider deleting them and pointing
  callers at the bridge directly.
- **Service-layer DI pass.** Many services still accept
  `logger ?? ServiceLocator.get<ILoggingService>()` constructor fallbacks
  (notably DB migrations). A future batch should make `logger` required and
  delete the fallbacks.
- **`lib/utils/retry_utils.dart` (lines 13, 290).** Concrete `LoggingService`
  type field — widen to `ILoggingService`.
- **`lib/services/database/database_service.dart` and `migration_service.dart`.**
  `static ILoggingService _logger = LoggingService.instance;` is a latent
  footgun if the singleton's null-safety contract ever tightens.
- **`ModsProjectService.create`.** Pure pass-through factory with two
  callers (both in `lib/features/mods/utils/mods_screen_controller.dart`,
  lines 160 and 237) — inline it.
- **`ModsScreenController`.** Plain Dart class holding only a `WidgetRef`;
  convert to a `@riverpod` Notifier.
- **`deleteCompilation(WidgetRef ref, ...)`.** Top-level function with a
  single caller — inline.
- **`TmBrowserDataGrid` lines 81–90 (and 3 sibling TM dialogs).** Renders
  unbounded `error.toString()`; wrap in `SingleChildScrollView` or cap with
  `maxLines`.
