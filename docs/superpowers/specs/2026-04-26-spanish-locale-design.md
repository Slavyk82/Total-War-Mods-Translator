# Spanish locale (es) — design

**Date:** 2026-04-26
**Status:** draft (awaiting user review)

## Goal

Add **Spanish (Castilian, code `es`)** as a fully-supported UI locale of TWMT, sitting alongside the existing `en` (base) and `fr` locales. Every user-facing string ships translated; the locale picker exposes "Español" with the `es.png` flag; all i18n structural tests pass.

## Non-goals

- LLM system prompts are explicitly out of scope (rule from `CLAUDE.md`).
- `assets/flags/*` filenames and mod-translation domain language data stay untouched.
- No other locales are seeded in this work (no `de`, `pt`, …).

## Constraints

- **Spanish variant**: castellano (Spain). The directory code is `es`, with no regional suffix — consistent with `en` and `fr` already shipped without suffix. This is the de-facto default in software localization (Microsoft, Apple, Google all map plain `es` to es-ES).
- **Tone — T-V distinction**: formal `usted` register exclusively. Never `tú`, `tu`, `vosotros`, or any informal form. When both forms feel awkward, reformulate impersonally ("Introducir una palabra clave" rather than "Puede introducir una palabra clave").
- **Proper nouns are never translated** in any locale (rule just added to `CLAUDE.md` and `lib/i18n/README.md`). For this work that means in particular: `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, and any Total War game/DLC name. These appear inline inside translation values and MUST be copied verbatim.
- **Placeholders** (`{name}`, `{count}`, …) MUST appear identically in the translated string, with the same identifier and case.
- **Plurals**: use slang's `one`/`other` map syntax wherever the base file does, with Spanish plural conventions.
- **Generated artefacts** (`strings*.g.dart`, `_missing_translations.json`, `_unused_translations.json`) are gitignored — never committed.

## Terminology decisions

Locked at the start of the work to keep all 20 namespace files consistent. Software/gaming-industry standard wording for Spanish:

| English | Spanish (es-ES) | Notes |
|---|---|---|
| Mod | **Mod** | Universally adopted in Spanish-speaking gaming community; never "modificación" in a UI |
| Pack file / Pack | **archivo pack** / **pack** | Total War's `.pack` extension is a name; "pack" stays |
| Glossary | **Glosario** | Standard CAT/translation industry term |
| Translation Memory | **Memoria de traducción** | SDL Trados / memoQ standard |
| Project | **Proyecto** | |
| Mod (singular) / Mods (plural) | Mod / Mods | Plural is invariant in this context, like "los mods" |
| Workshop (Steam) | **Steam Workshop** | Proper noun, never translated |
| Settings | **Ajustes** | Microsoft/Apple Spanish convention |
| Search | **Buscar** | |
| Save / Cancel / Delete | Guardar / Cancelar / Eliminar | Microsoft Spanish style guide |
| Close | Cerrar | |
| Open | Abrir | |
| Import / Export | Importar / Exportar | |
| Compile | Compilar | |
| Publish | Publicar | |
| Translate | Traducir | |
| Validation | Validación | |
| Issue (validation) | Problema | |
| Warning | Advertencia | |
| Error | Error | Cognate, identical |
| File / Folder | Archivo / Carpeta | |
| Browse | Examinar | Microsoft style guide |
| Add / Remove | Añadir / Quitar | |
| Edit | Editar | |
| Refresh | Actualizar | |
| Reset | Restablecer | |
| Apply | Aplicar | |
| Loading | Cargando | |
| Done | Hecho / Listo | "Hecho" for action completion, "Listo" for state |
| Skip | Omitir | |
| Next / Back / Previous | Siguiente / Atrás / Anterior | |
| Confirm | Confirmar | |

## Architecture

Mechanical replication of the existing `lib/i18n/fr/` pattern:

1. **New directory** `lib/i18n/es/` — one JSON file per existing namespace under `lib/i18n/en/`.
2. **Locale registration** — add an `AppLocale.es` entry to the `_localeInfo` map in `lib/i18n/app_locale_info.dart`, with `nativeName: 'Español'` and `flagAsset: 'assets/flags/es.png'` (asset already present on disk).
3. **Code generation** — slang picks up the new directory automatically; `dart run slang` regenerates `strings.g.dart` and emits a new `strings_es.g.dart`.
4. **No application code changes** beyond the `app_locale_info.dart` map. The locale picker, persisted preference, and fallback strategy already iterate over `supportedLocales` / `AppLocale.values` and need no edits.

### Files touched

| Path | Action |
|---|---|
| `lib/i18n/es/activity.i18n.json` | create |
| `lib/i18n/es/app.i18n.json` | create |
| `lib/i18n/es/bootstrap.i18n.json` | create |
| `lib/i18n/es/common.i18n.json` | create |
| `lib/i18n/es/game_translation.i18n.json` | create |
| `lib/i18n/es/glossary.i18n.json` | create |
| `lib/i18n/es/home.i18n.json` | create |
| `lib/i18n/es/import_export.i18n.json` | create |
| `lib/i18n/es/mods.i18n.json` | create |
| `lib/i18n/es/pack_compilation.i18n.json` | create |
| `lib/i18n/es/projects.i18n.json` | create |
| `lib/i18n/es/release_notes.i18n.json` | create |
| `lib/i18n/es/search.i18n.json` | create |
| `lib/i18n/es/settings.i18n.json` | create |
| `lib/i18n/es/steam_publish.i18n.json` | create |
| `lib/i18n/es/tooltips.i18n.json` | create |
| `lib/i18n/es/translation.i18n.json` | create |
| `lib/i18n/es/translation_editor.i18n.json` | create |
| `lib/i18n/es/translation_memory.i18n.json` | create |
| `lib/i18n/es/widgets.i18n.json` | create |
| `lib/i18n/app_locale_info.dart` | edit (add `AppLocale.es` entry) |

20 new JSON files + 1 edited Dart file. No other source-code change.

## Execution strategy

### Translation workflow

The 20 files total ~2153 lines of JSON, spread across functionally cohesive namespaces. To keep the main session context tight and exploit independence, translation is **parallelised across subagents** (Opus 4.6 per project policy). Each subagent receives:

- the source `lib/i18n/en/<namespace>.i18n.json` content;
- the corresponding `lib/i18n/fr/<namespace>.i18n.json` for tone reference (the French file already uses the formal register, so it's a useful sanity check on register consistency);
- the locked terminology table from this spec;
- the proper-nouns rule;
- a strict checklist: identical keys, identical placeholders, formal `usted`, no proper-noun translation, write to `lib/i18n/es/<namespace>.i18n.json`.

Proposed batching (5 batches, dispatched in parallel):

| Batch | Namespaces | Rationale |
|---|---|---|
| **A — Core** | `common`, `app`, `widgets` | Cross-cutting atoms; sets terminology baseline for the rest |
| **B — Navigation/Library** | `home`, `projects`, `mods`, `search` | Top-level navigation surfaces |
| **C — Translation core** | `translation`, `translation_editor`, `translation_memory`, `glossary`, `game_translation` | Translation domain — heaviest namespaces |
| **D — Pipeline** | `import_export`, `pack_compilation`, `steam_publish`, `bootstrap` | I/O and publication flows |
| **E — Misc UI** | `settings`, `tooltips`, `activity`, `release_notes` | Settings + ambient UI |

Each batch runs as one subagent invocation. Batch A is dispatched first; once `common`/`app` come back I review terminology consistency before dispatching B–E in parallel.

### Validation

After all batches return:

1. `dart run slang` — regenerate bindings.
2. `dart run build_runner build --delete-conflicting-outputs` — only needed if the locale picker provider re-references `AppLocale.es`. Will run for safety per `CLAUDE.md`.
3. `dart run slang analyze` — must report **zero missing keys, zero unused keys, zero placeholder mismatches** for `es`.
4. `flutter test test/i18n` — `keys_completeness_test.dart` and `format_consistency_test.dart` must pass.
5. Smoke test: `flutter run -d windows`, switch the locale picker to "Español", verify the app shell, home page, settings, and one editor screen render in Spanish without overflow or fallback to English.

## Error handling and rollback

- If `dart run slang analyze` reports issues for `es`, fix them in the JSON files in-place; do NOT touch generated artefacts.
- If the smoke test surfaces UI overflow on a long Spanish string (Spanish UI strings are typically ~20 % longer than English), tighten the translation rather than widening the layout — mirrors how `fr` was handled.
- If a translation feels off post-merge, the per-key fallback to `en` cushions any regression: a removed/broken `es` key falls back to English, never crashes.

## Testing

- **Structural** (already exist, no new tests needed): `keys_completeness_test.dart` ensures every locale carries every key the base locale defines; `format_consistency_test.dart` ensures placeholders match. Both will exercise `es` automatically once the files exist.
- **Manual smoke**: locale switch to Español, walk the main flows once.

No new test files are introduced.

## Documentation

- `lib/i18n/README.md` already documents the "adding a new locale" procedure and the formal-register rule (we just extended it with the proper-nouns rule). No further README change.
- `CLAUDE.md` is up to date.

## Open questions

None. Variant, register, terminology, and proper-noun handling are all locked.
