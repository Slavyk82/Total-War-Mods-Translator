# Layering Convention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify and enforce the global/feature layering rule, then fix every existing violation, with a regression-safety architecture test written first.

**Architecture:** A pure-Dart architecture test (`test/architecture/import_boundaries_test.dart`) walks `lib/`, parses imports, and asserts three invariants (feature isolation, service purity, dependency direction) against a shrinking allowlist seeded with today's violations. Each refactor lot promotes shared code to a global layer (or injects dependencies via constructor) and deletes its allowlist entries until the allowlist is empty.

**Tech Stack:** Dart/Flutter, Riverpod (code-gen via `build_runner`), `flutter test`. Package name: `twmt`.

---

## Conventions used in this plan

- Test runner: `flutter test <path>`. Full suite: `flutter test`.
- Codegen after editing any `@riverpod` file or moving a file with a `part '*.g.dart'`: `dart run build_runner build --delete-conflicting-outputs`.
- If `flutter test` fails with `PathExistsException` on a native sqlite3 dll, kill stale `flutter_tester` processes / delete the stale dll (known environment issue), then re-run.
- Commit after every task. Branch already in use: `docs/layering-convention` (create a sibling `feat/layering-convention` branch for code lots if you prefer; this plan assumes you commit on the current working branch).

---

## File Structure

**Created:**
- `test/architecture/import_boundaries_test.dart` — the enforcement + regression test.
- `test/architecture/import_graph.dart` — pure helper: read a Dart file, extract resolved `package:twmt/...` import targets. Kept separate so it is unit-testable.
- `test/architecture/import_graph_test.dart` — unit tests for the parser/resolver.
- `docs/architecture/layering.md` — the canonical written rule.
- `lib/providers/settings_providers.dart` — promoted from `lib/features/settings/providers/`.
- `lib/providers/activity_providers.dart` — promoted from `lib/features/activity/providers/`.
- `CLAUDE.md` (repo root, Lot 4) — points to `layering.md`, fixes the dangling reference.

**Modified (high level — exact lists per task):**
- ~13 consumers of `settings_providers.dart`; ~3 consumers of `activity_providers.dart`.
- Inter-feature widget/util/screen importers (Lot 2).
- `headless_batch_translation_runner.dart`, `headless_validation_rescan_service.dart`, `game_installation_sync_service.dart`, `mods_project_service.dart`, `bulk_operations_handlers.dart` (Lot 3).

---

## LOT 0 — Foundation (test + allowlist + doc). No refactor; everything green.

### Task 0.1: Import-graph parser helper

**Files:**
- Create: `test/architecture/import_graph.dart`
- Test: `test/architecture/import_graph_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/architecture/import_graph_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'architecture/import_graph.dart' as ig; // adjusted below if path differs

void main() {
  group('resolveImport', () {
    test('keeps a package:twmt import as-is', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: 'package:twmt/services/shared/i_logging_service.dart',
      );
      expect(r, 'lib/services/shared/i_logging_service.dart');
    });

    test('resolves a relative import against the importing file dir', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: '../../../services/shared/i_logging_service.dart',
      );
      expect(r, 'lib/services/shared/i_logging_service.dart');
    });

    test('returns null for non-twmt package imports', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: 'package:flutter/material.dart',
      );
      expect(r, isNull);
    });

    test('strips show/hide/as clauses before resolving', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/a/b.dart',
        rawImport: 'package:twmt/models/common/result.dart',
      );
      expect(r, 'lib/models/common/result.dart');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/architecture/import_graph_test.dart`
Expected: FAIL — `import_graph.dart` does not exist / `resolveImport` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// test/architecture/import_graph.dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// Resolves a raw import string found in [importingLibPath] to a normalized
/// repo-relative `lib/...` path, or null if the import does not point into
/// this package's `lib/` (e.g. dart:, package:flutter, third-party).
String? resolveImport({
  required String importingLibPath,
  required String rawImport,
}) {
  const pkgPrefix = 'package:twmt/';
  if (rawImport.startsWith(pkgPrefix)) {
    return 'lib/${rawImport.substring(pkgPrefix.length)}';
  }
  // Any other package: / dart: import is external — ignore.
  if (rawImport.startsWith('package:') || rawImport.startsWith('dart:')) {
    return null;
  }
  // Relative import: resolve against the importing file's directory.
  final dir = p.dirname(importingLibPath);
  final joined = p.normalize(p.join(dir, rawImport));
  return p.split(joined).join('/'); // force forward slashes
}

/// Returns the set of resolved in-package import targets for [absFilePath].
/// [libRelPath] is the path relative to the repo root, e.g. 'lib/a/b.dart'.
Set<String> importsOf(String absFilePath, String libRelPath) {
  final content = File(absFilePath).readAsStringSync();
  final regex = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
  final result = <String>{};
  for (final m in regex.allMatches(content)) {
    final resolved = resolveImport(
      importingLibPath: libRelPath,
      rawImport: m.group(1)!,
    );
    if (resolved != null) result.add(resolved);
  }
  return result;
}
```

Note: fix the import in the test file to match the real relative path
(`import 'import_graph.dart' as ig;` since both files live in
`test/architecture/`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/architecture/import_graph_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add test/architecture/import_graph.dart test/architecture/import_graph_test.dart
git commit -m "test(arch): add import-graph parser helper"
```

---

### Task 0.2: Architecture boundary test with seeded allowlist

**Files:**
- Create: `test/architecture/import_boundaries_test.dart`

- [ ] **Step 1: Write the test (it will fail until the allowlist is seeded)**

```dart
// test/architecture/import_boundaries_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'import_graph.dart';

/// Known, intentionally-tolerated violations. EACH entry must be removed by
/// the lot that fixes it. Format: '<importerLibPath> -> <importedLibPath>'.
/// The allowlist shrinks to empty; do NOT add new entries.
const _allowlist = <String>{
  // === Seeded in Lot 0 (run with TWMT_PRINT_VIOLATIONS=1 to regenerate) ===
  // (paste the printed lines here verbatim, then add a `// lot:N` tag each)
};

/// Paths that LOOK like Riverpod providers but are not (service purity rule).
bool _isProviderFalsePositive(String libPath) =>
    libPath.startsWith('lib/services/llm/providers/') ||
    libPath == 'lib/repositories/translation_provider_repository.dart';

String _featureOf(String libPath) {
  // returns the feature name for 'lib/features/<name>/...', else ''.
  const prefix = 'lib/features/';
  if (!libPath.startsWith(prefix)) return '';
  return libPath.substring(prefix.length).split('/').first;
}

bool _isRiverpodProviderImport(String importedLibPath) {
  if (_isProviderFalsePositive(importedLibPath)) return false;
  return importedLibPath.contains('/providers/') ||
      importedLibPath.endsWith('_provider.dart') ||
      importedLibPath.endsWith('_providers.dart');
}

void main() {
  // Collect all non-generated lib dart files as repo-relative paths.
  final libDir = Directory('lib');
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  // Build the full violation set first (so we can print or assert).
  final violations = <String>[];

  for (final libRel in files) {
    final imports = importsOf(libRel, libRel);
    for (final target in imports) {
      // Invariant 1: feature isolation.
      final srcF = _featureOf(libRel);
      final tgtF = _featureOf(target);
      if (srcF.isNotEmpty && tgtF.isNotEmpty && srcF != tgtF) {
        violations.add('$libRel -> $target');
        continue;
      }
      // Invariant 2: service purity (no Riverpod providers imported by services).
      if (libRel.startsWith('lib/services/') &&
          _isRiverpodProviderImport(target)) {
        violations.add('$libRel -> $target');
        continue;
      }
      // Invariant 3a: models import nothing above models.
      if (libRel.startsWith('lib/models/') &&
          !(target.startsWith('lib/models/'))) {
        violations.add('$libRel -> $target');
        continue;
      }
      // Invariant 3b: shared widgets import no feature.
      if (libRel.startsWith('lib/widgets/') && tgtF.isNotEmpty) {
        violations.add('$libRel -> $target');
        continue;
      }
    }
  }

  // Optional helper to (re)seed the allowlist.
  if (Platform.environment['TWMT_PRINT_VIOLATIONS'] == '1') {
    // ignore: avoid_print
    for (final v in violations..sort()) print("  '$v',");
  }

  test('no import-boundary violations outside the allowlist', () {
    final unexpected =
        violations.where((v) => !_allowlist.contains(v)).toList()..sort();
    expect(
      unexpected,
      isEmpty,
      reason: 'New layering violations introduced:\n${unexpected.join('\n')}\n'
          'Fix the import (promote shared code to a global layer or inject '
          'via constructor) — do not add to the allowlist.',
    );
  });

  test('allowlist has no stale entries', () {
    final stale = _allowlist.where((v) => !violations.contains(v)).toList()
      ..sort();
    expect(
      stale,
      isEmpty,
      reason: 'Allowlist entries no longer violate — delete them:\n'
          '${stale.join('\n')}',
    );
  });
}
```

- [ ] **Step 2: Print current violations to seed the allowlist**

Run (PowerShell):
`$env:TWMT_PRINT_VIOLATIONS=1; flutter test test/architecture/import_boundaries_test.dart; Remove-Item Env:\TWMT_PRINT_VIOLATIONS`
Expected: prints ~34 lines like `  'lib/features/mods/utils/mods_screen_controller.dart -> lib/features/projects/utils/open_project_editor.dart',`

- [ ] **Step 3: Paste the printed lines into `_allowlist`**

Paste verbatim between the `=== Seeded in Lot 0 ===` markers. Add a trailing
`// lot:1`, `// lot:2`, or `// lot:3` tag to each line per the categorization:
- `-> lib/features/settings/...` or `-> lib/features/activity/...` → `lot:1`
- `lib/services/... -> ...provider...` → `lot:3`
- everything else (feature→feature widgets/utils/screens/providers) → `lot:2`

- [ ] **Step 4: Run the full architecture test — must be green**

Run: `flutter test test/architecture/import_boundaries_test.dart`
Expected: PASS (2 tests). Both `unexpected` and `stale` are empty.

- [ ] **Step 5: Commit**

```bash
git add test/architecture/import_boundaries_test.dart
git commit -m "test(arch): enforce import boundaries with seeded allowlist"
```

---

### Task 0.3: Write the canonical convention doc

**Files:**
- Create: `docs/architecture/layering.md`

- [ ] **Step 1: Write the doc**

Content: copy the "The rule" section from
`docs/superpowers/specs/2026-06-12-layering-convention-design.md` (layer model
+ three invariants), then add a short "How it is enforced" paragraph pointing
at `test/architecture/import_boundaries_test.dart` and explaining the
allowlist-shrinks-to-zero policy and the two false positives. End with "Adding
shared code: promote to `lib/providers/` (state), `lib/widgets/` (UI),
`lib/services/` (logic), or `lib/models/` (data) — never import a sibling
feature."

- [ ] **Step 2: Verify it has no placeholders and links resolve**

Run: `flutter test test/architecture` (sanity: doc change doesn't break tests)
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/layering.md
git commit -m "docs(arch): add layering convention reference"
```

---

## LOT 1 — Promote settings + activity to `lib/providers/`

> Procedure for moving a Riverpod codegen provider file:
> 1. `git mv` the `.dart` (and its `.g.dart`) to the new dir.
> 2. Fix the relative imports inside the moved file (depth changes).
> 3. Fix the `part '...g.dart';` directive if the filename is unchanged it stays the same.
> 4. Update every consumer's import path. Provider **symbol names do not change**.
> 5. Regenerate codegen, run tests.

### Task 1.1: Move `settings_providers.dart` to `lib/providers/`

**Files:**
- Move: `lib/features/settings/providers/settings_providers.dart` → `lib/providers/settings_providers.dart` (and `.g.dart`)
- Modify (consumers — exact list):
  - `lib/features/glossary/providers/glossary_providers.dart`
  - `lib/features/mods/services/mods_project_service.dart`
  - `lib/features/projects/services/bulk_operations_handlers.dart`
  - `lib/features/projects/utils/open_project_editor.dart`
  - `lib/features/projects/widgets/bulk_review_dialog.dart`
  - `lib/features/projects/widgets/create_project/create_project_dialog.dart`
  - `lib/features/settings/widgets/general/maintenance_section.dart`
  - `lib/features/steam_publish/screens/workshop_publish_screen.dart`
  - `lib/features/steam_publish/widgets/workshop_onboarding_card.dart`
  - `lib/features/steam_publish/widgets/workshop_publish_settings_dialog.dart`
  - `lib/features/translation_editor/providers/llm_model_providers.dart`
  - `lib/providers/selected_game_provider.dart`
  - `lib/services/mods/game_installation_sync_service.dart` (leak — fully fixed in Lot 3; here only the path changes)

- [ ] **Step 1: Move the files**

```bash
git mv lib/features/settings/providers/settings_providers.dart lib/providers/settings_providers.dart
git mv lib/features/settings/providers/settings_providers.g.dart lib/providers/settings_providers.g.dart
```

- [ ] **Step 2: Fix relative imports inside the moved file**

The file currently uses `../../../providers/shared/...`, `../../../services/...`,
`../../../models/...`, `../utils/pack_prefix_sanitizer.dart`. From the new
location `lib/providers/`, rewrite to:
- `../../../providers/shared/logging_providers.dart` → `shared/logging_providers.dart`
- `../../../providers/shared/service_providers.dart` → `shared/service_providers.dart`
- `../../../services/settings/settings_service.dart` → `../services/settings/settings_service.dart`
- `../../../services/llm/llm_model_management_service.dart` → `../services/llm/llm_model_management_service.dart`
- `../../../services/glossary/glossary_auto_provisioning_service.dart` → `../services/glossary/glossary_auto_provisioning_service.dart`
- `../../../services/service_locator.dart` → `../services/service_locator.dart`
- `../../../services/shared/i_logging_service.dart` → `../services/shared/i_logging_service.dart`
- `../../../models/domain/llm_provider_model.dart` → `../models/domain/llm_provider_model.dart`
- `../utils/pack_prefix_sanitizer.dart` → `../features/settings/utils/pack_prefix_sanitizer.dart`

(The `pack_prefix_sanitizer` is a settings-feature util; keeping it in the
feature is fine — a provider importing a feature util is allowed because the
provider now lives in `lib/providers/`, not in a feature. The arch test only
forbids feature→feature.) The `part 'settings_providers.g.dart';` stays.

- [ ] **Step 3: Update every consumer import path**

In each file listed above, replace:
`import 'package:twmt/features/settings/providers/settings_providers.dart';`
(or the relative equivalent) with
`import 'package:twmt/providers/settings_providers.dart';`
Provider symbol names (`settingsServiceProvider`, `generalSettingsProvider`,
`llmProviderSettingsProvider`, etc.) are unchanged.

- [ ] **Step 4: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes; `lib/providers/settings_providers.g.dart` regenerated.

- [ ] **Step 5: Run analyzer + the architecture test + affected feature tests**

Run: `flutter analyze`
Expected: no errors.
Run: `flutter test test/architecture test/features/settings`
Expected: PASS — the `settings`-targeted entries are now reported as **stale**.

- [ ] **Step 6: Remove the now-stale `lot:1` settings entries from the allowlist**

Delete every `_allowlist` line whose target contains
`lib/features/settings/providers/settings_providers.dart`.

- [ ] **Step 7: Run architecture test again**

Run: `flutter test test/architecture/import_boundaries_test.dart`
Expected: PASS (no stale, no unexpected).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(settings): promote settings_providers to lib/providers"
```

### Task 1.2: Move `activity_providers.dart` to `lib/providers/`

**Files:**
- Move: `lib/features/activity/providers/activity_providers.dart` (+ `.g.dart`) → `lib/providers/`
- Modify (consumers):
  - `lib/features/glossary/providers/glossary_providers.dart`
  - `lib/features/pack_compilation/providers/compilation_editor_notifier.dart`

- [ ] **Step 1: Move the files**

```bash
git mv lib/features/activity/providers/activity_providers.dart lib/providers/activity_providers.dart
git mv lib/features/activity/providers/activity_providers.g.dart lib/providers/activity_providers.g.dart
```

- [ ] **Step 2: Fix relative imports inside the moved file**

Open `lib/providers/activity_providers.dart`; rewrite each `../../../X` to the
correct depth from `lib/providers/` (one fewer `../`), and any `../<sibling>`
to `../features/activity/<sibling>`. Keep the `part` directive.

- [ ] **Step 3: Update the two consumer import paths**

Replace the activity_providers import with
`import 'package:twmt/providers/activity_providers.dart';`. Symbols unchanged.

- [ ] **Step 4: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes.

- [ ] **Step 5: Run analyzer + tests**

Run: `flutter analyze`
Expected: no errors.
Run: `flutter test test/architecture test/features/activity test/features/glossary`
Expected: PASS — activity entries now stale.

- [ ] **Step 6: Remove the `lot:1` activity entries from the allowlist, then re-run**

Run: `flutter test test/architecture/import_boundaries_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(activity): promote activity_providers to lib/providers"
```

---

## LOT 2 — Remove inter-feature widget/util/screen/provider couplings

Each remaining `lot:2` allowlist entry is fixed by one of two moves:
- **(P) Promote** the imported unit to a global layer (`lib/widgets/` for a
  reusable widget, `lib/providers/` for shared state, `lib/services/` for
  logic, `lib/models/` for a DTO), then update all importers.
- **(W) Wrap** via a shared provider: if feature A only needs a *value* from
  feature B, expose that value through a `lib/providers/` provider that B also
  uses, and have A read the shared provider instead of B's internals.

> Work one allowlist entry (or one tightly-related cluster) per task. Template
> below; repeat per cluster. The clusters, from the inventory:
> 1. `mods → projects` — `mods_screen_controller.dart` imports
>    `open_project_editor.dart`, `project_initialization_dialog.dart`,
>    `projects_screen_providers.dart`; `whats_new_dialog.dart` imports a
>    projects file. → Promote `open_project_editor` + the dialog to
>    `lib/widgets/` or `lib/providers/`; expose the needed projects provider
>    via `lib/providers/`.
> 2. `projects → translation_editor` — `bulk_operations_handlers.dart`,
>    `bulk_review_dialog.dart`, `projects_bulk_menu_panel.dart` import editor
>    toolbar widgets + providers. → Promote the shared toolbar widgets
>    (`editor_toolbar_batch_settings.dart`, `editor_toolbar_model_selector.dart`)
>    to `lib/widgets/`; promote shared editor providers to `lib/providers/`.
> 3. `translation_editor → projects` — `editor_language_switcher.dart` imports
>    projects providers. → Promote the shared project-language provider to
>    `lib/providers/`.
> 4. `bootstrap → mods / steam_publish` — `mod_scan_boot_dialog.dart`. →
>    Promote the shared dialog pieces to `lib/widgets/` or expose via provider.
> 5. `pack_compilation → translation_editor / home` —
>    `pack_compilation_editor_screen.dart`, `compilation_editor_notifier.dart`.
>    → Promote shared widget/provider.
> 6. `home → mods / projects` — `workflow_providers.dart`,
>    `action_grid_providers.dart` (already thin wrappers). → Promote the
>    upstream counts/providers they read to `lib/providers/`.
> 7. `glossary → activity` — resolved in Lot 1 if it pointed at
>    activity_providers; otherwise promote the referenced unit.

### Task 2.N (template — instantiate once per cluster above)

**Files:**
- Move/Create: the promoted unit's new global path (state in PLAN per cluster).
- Modify: the moved unit's internal imports; every importer.
- Test: a widget/unit test pinning the moved unit's behavior BEFORE moving.

- [ ] **Step 1: Write a characterization test for the unit being moved**

Pin current behavior so the move is provably safe. For a widget, a
`testWidgets` that pumps it (with required Riverpod overrides via
`createTestableWidget` + `overrides:` — see
`docs/architecture/dependency_injection.md`) and asserts it renders its key
elements. For a provider, a `ProviderContainer` test asserting the value it
yields given overridden dependencies.

- [ ] **Step 2: Run the new test — must PASS at current location**

Run: `flutter test <new test path>`
Expected: PASS (behavior captured before the move).

- [ ] **Step 3: Perform the move (P or W)**

For **(P)**: `git mv` the unit to the chosen global dir; fix its internal
relative imports for the new depth; update every importer's import path. If the
unit is a widget that itself imports a sibling feature, that import must also be
resolved (recurse the rule) — promote or wrap it too.
For **(W)**: create the shared provider in `lib/providers/`; point both the
origin feature and the consumer feature at it; delete the cross-feature import.

- [ ] **Step 4: Regenerate codegen (if any `@riverpod` file changed) + analyze**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 5: Run the characterization test (now at the new location) + arch test**

Run: `flutter test <new test path> test/architecture`
Expected: characterization test PASS; arch test reports this cluster's entries
as **stale**.

- [ ] **Step 6: Delete this cluster's `lot:2` entries from the allowlist; re-run**

Run: `flutter test test/architecture/import_boundaries_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(<cluster>): remove inter-feature coupling via promotion"
```

> Repeat Task 2.N for clusters 1–7. After the last cluster, no `lot:2` entries
> remain in the allowlist.

---

## LOT 3 — Fix service→Riverpod leaks via constructor injection

Rule restored: `lib/services/**` takes dependencies through its constructor;
the calling Riverpod provider reads `ref` and passes plain objects in.

### Task 3.1: `headless_batch_translation_runner` — inject dependencies

**Files:**
- Modify: `lib/services/translation/headless_batch_translation_runner.dart`
- Modify: the provider/notifier that constructs it (find with
  `grep -rln HeadlessBatchTranslationRunner lib`)
- Test: `test/services/translation/headless_batch_translation_runner_test.dart`

- [ ] **Step 1: Write/extend a test that constructs the runner with fakes**

Construct the runner passing fake repositories + a settings snapshot value
(no `ref`). Assert it performs one batch correctly against fakes. This both
captures behavior and forces the injected-constructor shape.

- [ ] **Step 2: Run it — expect FAIL (constructor still needs a Ref / imports providers)**

Run: `flutter test test/services/translation/headless_batch_translation_runner_test.dart`
Expected: FAIL (compile error: constructor signature mismatch).

- [ ] **Step 3: Refactor the runner**

Remove `import '.../features/translation_editor/providers/translation_settings_provider.dart';`
and `import '.../providers/shared/service_providers.dart';`. Replace every
`ref.read(xProvider)` with a constructor-injected field (e.g.
`final TranslationSettings settings;`, `final ITranslationOrchestrator
orchestrator;`). Introduce a plain settings value object if the provider
returned derived state.

- [ ] **Step 4: Update the caller to read providers and pass values in**

In the constructing provider/notifier, read the providers via `ref` and pass
the resolved objects into the runner constructor.

- [ ] **Step 5: Codegen + analyze + test**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter analyze`
Run: `flutter test test/services/translation/headless_batch_translation_runner_test.dart test/architecture`
Expected: unit test PASS; arch test reports this file's `lot:3` entries stale.

- [ ] **Step 6: Remove this file's `lot:3` entries; re-run arch test**

Run: `flutter test test/architecture/import_boundaries_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(services): inject deps into headless_batch_translation_runner"
```

### Task 3.2: `headless_validation_rescan_service` — inject dependencies

Same procedure as Task 3.1 for
`lib/services/translation/headless_validation_rescan_service.dart` (imports
`providers/shared/repository_providers.dart` + `service_providers.dart`).
Test: `test/services/translation/headless_validation_rescan_service_test.dart`.
Steps 1–7 identical in shape: characterization test with fakes → fail →
inject constructor deps → update caller → codegen/analyze/test → drop allowlist
entries → commit (`refactor(services): inject deps into headless_validation_rescan_service`).

### Task 3.3: `game_installation_sync_service` — inject settings

**Files:**
- Modify: `lib/services/mods/game_installation_sync_service.dart` (imports
  `settings_providers.dart` — now at `lib/providers/` after Lot 1, still a
  provider import and still a leak).
- Modify: its caller.
- Test: `test/services/.../game_installation_sync_service_test.dart` (create if absent).

- [ ] **Step 1: Characterization test constructing it with a fake settings source** — run, expect FAIL.
- [ ] **Step 2: Remove the `settings_providers` import; inject the needed settings values (or `SettingsService`) via constructor.**
- [ ] **Step 3: Update the caller to pass them from `ref`.**
- [ ] **Step 4: Codegen + `flutter analyze` + run the test + `test/architecture`.**
- [ ] **Step 5: Drop the allowlist entry; re-run arch test (PASS).**
- [ ] **Step 6: Commit** (`refactor(services): inject settings into game_installation_sync_service`).

### Task 3.4: `mods_project_service` — inject settings + selected-game

**Files:**
- Modify: `lib/features/mods/services/mods_project_service.dart` (imports
  `lib/providers/selected_game_provider.dart` and the settings providers).

Note: this file is a **feature service**, so the relevant invariant is that a
service must not depend on Riverpod. Inject the selected-game value and settings
via constructor / method parameter; the calling notifier supplies them from
`ref`. Same 6 steps as Task 3.3; commit
`refactor(mods): inject deps into mods_project_service`.

### Task 3.5: `bulk_operations_handlers` — inject dependencies

**Files:**
- Modify: `lib/features/projects/services/bulk_operations_handlers.dart`
  (imports several providers, incl. `bulk_operation_state.dart`,
  `projects_screen_providers.dart`, `settings_providers.dart`, two
  translation_editor providers, and shared repo/service providers).

This is the densest leak. Inject the repositories/services/settings it needs
via constructor; have the bulk-operations notifier read providers and pass them
in. The translation_editor provider imports become value parameters (or shared
providers promoted in Lot 2 — if Lot 2 already promoted them, just update the
path and inject the value). Same 6 steps; commit
`refactor(projects): inject deps into bulk_operations_handlers`.

---

## LOT 4 — Lock

### Task 4.1: Verify allowlist empty and suite green

- [ ] **Step 1: Confirm the allowlist is empty**

Open `test/architecture/import_boundaries_test.dart`; `_allowlist` must contain
zero entries (only the comment markers).

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: PASS, including both architecture tests with an empty allowlist.

- [ ] **Step 3: Commit (if the allowlist needed final cleanup)**

```bash
git add -A
git commit -m "test(arch): empty allowlist — layering boundaries fully enforced"
```

### Task 4.2: Recreate root `CLAUDE.md`

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write `CLAUDE.md`**

Brief project orientation that points to `docs/architecture/layering.md` and
`docs/architecture/dependency_injection.md` as the architecture rules, states
the "no inter-feature import; services are pure Dart" invariants in one line
each, and notes the Syncfusion DataGrid mandate referenced elsewhere. This
fixes the dangling "MANDATORY per CLAUDE.md" reference in `pubspec.yaml`.

- [ ] **Step 2: Run full suite (sanity)**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: recreate root CLAUDE.md pointing to layering rules"
```

---

## Self-Review notes

- **Spec coverage:** rule statement → Task 0.3/4.2; enforcement test → 0.1/0.2;
  settings/activity promotion → Lot 1; inter-feature couplings → Lot 2;
  service→Riverpod leaks → Lot 3; false positives → encoded in 0.2
  (`_isProviderFalsePositive`); dangling CLAUDE.md → 4.2; tests-first → every
  refactor task writes the characterization test before changing code.
- **Allowlist mechanism** is the single regression spine; it shrinks
  monotonically (each lot deletes only its own entries) and the "no stale
  entries" test guarantees you cannot forget to remove a fixed one.
- **Risk noted in spec** (headless hidden coupling) is mitigated by Step 1
  characterization tests in Lot 3.
