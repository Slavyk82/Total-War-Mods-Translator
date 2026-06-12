# Codifying the global/feature layering convention

**Date:** 2026-06-12
**Status:** Approved design, ready for implementation plan

## Problem

The codebase mixes two organizing principles without a written rule:

- **Feature-first**: `lib/features/<f>/{screens,widgets,providers,services,models,utils}`
- **Layer-first**: `lib/services/`, `lib/repositories/`, `lib/providers/`, `lib/widgets/`, `lib/models/`, `lib/config/`

The separation is clear for models and reusable widgets, but ambiguous for
providers and services. Two concrete symptoms have accumulated:

1. **Feature-to-feature coupling.** 34 import sites where a file under
   `lib/features/A/**` imports `lib/features/B/**` internals (widgets, utils,
   screens, providers).
2. **Layer leaks.** A handful of `lib/services/**` files import Riverpod
   providers, contradicting the "services are pure Dart" intent of
   `docs/architecture/dependency_injection.md`.

There is no automated guard, so both categories drift upward over time. There
is also a dangling reference: code and `pubspec.yaml` mention a `CLAUDE.md`
that does not exist at the repo root.

## Goal

1. Write the layering convention down as the canonical reference.
2. Enforce it automatically so new violations cannot be introduced.
3. Fix **all** existing violations, with regression-safety tests written
   before each refactor.

Non-goals: unrelated refactoring; changing the GetIt + Riverpod DI strategy
(that stays as documented in `dependency_injection.md`).

## The rule

### Layer model (dependencies point downward only)

```
lib/config/        router, app constants                          (top)
lib/features/<f>/  UI + feature-local orchestration
lib/widgets/       reusable widgets — zero feature imports
lib/providers/     cross-feature app state + GetIt→Riverpod bridge (shared/)
lib/services/      business logic — pure Dart, no Riverpod, no Flutter widgets
lib/repositories/  data access
lib/models/        domain models — leaf, imports nothing from layers above     (bottom)
```

A layer may import the layers below it, never above. Sibling features never
import each other.

### Three enforced invariants

1. **Feature isolation.** No file under `lib/features/A/**` may import
   `lib/features/B/**` for any `A != B`, regardless of what is imported
   (provider, widget, util, screen, model). Code shared between features is
   **promoted** to the appropriate global layer (`lib/providers/`,
   `lib/widgets/`, `lib/services/`, `lib/models/`).
2. **Service purity.** No file under `lib/services/**` may import a Riverpod
   provider or `package:flutter/*` (except `package:flutter/foundation.dart`).
   Dependencies enter through the constructor, never through `ref`.
3. **Dependency direction.** `lib/models/**` imports nothing from the layers
   above it; `lib/widgets/**` imports no feature; `lib/repositories/**`
   imports no service/provider/feature.

A single uniform "no inter-feature import" rule is chosen over a
provider-vs-widget distinction: it is simpler to state, enforce, and reason
about. `settings` and `activity` are **not** exempt — they are promoted
(see below) so the rule stays at zero exceptions.

## Enforcement: architecture test (Dart)

`test/architecture/import_boundaries_test.dart`:

- Walks every `lib/**.dart` file (excluding generated `*.g.dart` /
  `*.freezed.dart`).
- Parses `import` directives (regex on `package:twmt/...` and relative
  imports resolved to package paths).
- Asserts the three invariants.
- Carries an explicit **allowlist** of the current violations, seeded in
  Lot 0. Each refactor lot removes its entries. When the allowlist is empty,
  the boundary is locked at zero.

This single artifact is **both** the CI gate (it runs in the existing
`flutter test`) **and** the regression-safety net: the test is green at every
step because a violation is either allowlisted or already fixed.

Allowlist format — a `Set<String>` of `"<importingFile> -> <importedFile>"`
pairs, with a `// reason / lot:` comment per entry, so the list is
self-documenting and shrinks visibly.

No new production or dev dependency is added.

## settings / activity: promotion

Both behave as cross-cutting infrastructure (`settings` imported by ~7
features, `activity` by 2). Their publicly-consumed providers move out of the
feature into the global layer:

- `lib/features/settings/providers/settings_providers.dart` → `lib/providers/`
  (e.g. `lib/providers/settings_providers.dart`), updating all consumers.
- `lib/features/activity/providers/activity_providers.dart` → `lib/providers/`
  similarly.

This removes the most common inter-feature edges and keeps the enforced rule
at **zero exceptions**, rather than carrying a permanent "platform feature"
allowlist. Feature-private settings/activity UI (screens, widgets) stays in
the feature; only the shared provider surface is promoted.

## headless_* runners: constructor injection

`lib/services/translation/headless_batch_translation_runner.dart` and
`headless_validation_rescan_service.dart` currently read settings and
shared repositories/services through Riverpod providers. They are refactored
to **accept their dependencies via the constructor** (repositories, a settings
snapshot/value object, services). The Riverpod wiring moves to the calling
provider/notifier, which reads from `ref` and passes plain dependencies in.
This keeps them in `lib/services/`, makes them pure and unit-testable, and
satisfies invariant #2. Same treatment for the smaller leaks in
`game_installation_sync_service` and `mods_project_service`.

## Phasing (tests-first, per lot)

Each lot: (1) the architecture test already allowlists the violation → green;
(2) write/strengthen characterization tests on the touched code; (3) refactor
(promote to a global layer, or inject via constructor); (4) remove the
allowlist entry → the test locks it.

- **Lot 0 — Foundation.** Write `import_boundaries_test.dart` + allowlist
  seeded with the current state; write `docs/architecture/layering.md`. No
  refactor — everything green.
- **Lot 1 — settings/activity (cross-cutting).** Promote their shared
  providers to `lib/providers/`; reroute consumers. Clears ~10 edges.
- **Lot 2 — Inter-feature widgets/utils/screens** (~33 UI couplings):
  `projects ↔ translation_editor`, `mods → projects`,
  `bootstrap → mods / steam_publish`,
  `pack_compilation → translation_editor / home`,
  `translation_editor → projects`, `glossary → activity`,
  `home → mods / projects`. Promote to `lib/widgets/` or expose via a shared
  provider.
- **Lot 3 — Service→Riverpod leaks.** Constructor-inject dependencies into
  `headless_batch_translation_runner`, `headless_validation_rescan_service`,
  `game_installation_sync_service`, `mods_project_service`, and the
  Riverpod-coupled `bulk_operations_handlers`.
- **Lot 4 — Lock.** Allowlist empty; recreate the root `CLAUDE.md` pointing to
  `layering.md` (also fixing the dangling reference).

### Known false positives (must NOT be treated as violations)

The enforcement test must distinguish these by path, not by the substring
"provider":

- `lib/services/llm/providers/*` — LLM strategy classes (Anthropic, OpenAI,
  DeepL…), not Riverpod providers.
- `lib/repositories/translation_provider_repository.dart` — a repository whose
  name contains "provider".

## Testing strategy

- The architecture test is the primary new test and the regression spine.
- Per-lot: characterization/unit tests on each refactored unit before changing
  it (e.g. inject-and-verify tests for the headless runners; widget tests for
  promoted widgets to confirm rendering parity).
- Full `flutter test` green after every lot; allowlist strictly monotonically
  shrinking.

## Risks

- **Promotion churn** (Lot 1/2) touches many import sites; mechanical but
  broad. Mitigated by per-lot scope and the always-green test.
- **headless_* injection** may surface hidden coupling (provider read inside a
  loop, lazy reads). Mitigated by writing the characterization tests first.
- **Import parsing** in the test must resolve relative imports and handle
  `as`/`show`/`hide`; covered by unit tests on the parser helper itself.
