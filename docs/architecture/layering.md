# Layering Convention

This project mixes feature-first and layer-first organization. This file is the
canonical rule for what lives where and how the pieces may depend on each other.
It is enforced automatically — see "How it is enforced" below.

## Layer model (dependencies point downward only)

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

## Three enforced invariants

1. **Feature isolation.** No file under `lib/features/A/**` may import
   `lib/features/B/**` for any `A != B`, regardless of what is imported
   (provider, widget, util, screen, model). Code shared between features is
   promoted to the appropriate global layer.
2. **Service purity.** No file under `lib/services/**` may import a Riverpod
   provider or `package:flutter` widgets (except `package:flutter/foundation.dart`).
   Dependencies enter through the constructor, never through `ref`.
3. **Dependency direction.** `lib/models/**` imports nothing from the layers
   above it; `lib/widgets/**` imports no feature.

`settings` and `activity` are NOT exempt: their shared providers were promoted
to `lib/providers/` so the rule stays at zero exceptions.

## Adding shared code

When two features need the same thing, promote it — never import a sibling
feature:

- shared **state** → `lib/providers/`
- shared **UI** → `lib/widgets/`
- shared **logic** → `lib/services/`
- shared **data shapes** → `lib/models/`

## How it is enforced

`test/architecture/import_boundaries_test.dart` walks `lib/`, parses every
import, and asserts the three invariants. It carries an allowlist of
historically-tolerated violations that shrinks toward empty; once empty, the
boundaries are locked. New violations fail the test — fix the import (promote
or inject), do not add to the allowlist.

Two known false positives are excluded by path, because they are not Riverpod
providers despite their names:

- `lib/services/llm/providers/*` — LLM strategy classes (Anthropic, OpenAI, …).
- `lib/services/database/migrations/migration_*_provider.dart` — DB migrations.
- `lib/repositories/translation_provider_repository.dart` — a repository.

See also `docs/architecture/dependency_injection.md` for the GetIt + Riverpod
DI strategy these layers sit on top of.
