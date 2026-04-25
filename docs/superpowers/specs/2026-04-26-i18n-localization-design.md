# i18n Localization Design — Total War Mods Translator

**Date:** 2026-04-26
**Status:** Approved — Step 0 infrastructure shipped on `main`. Lots 1-9 migrate progressively.
**Owner:** Slavyk

> **2026-04-26 amendment — no community contribution.**
> The original design assumed a Tier 1 (`en`/`fr`) / Tier 2 (8 stubs)
> / Tier 3 (PR-driven) tiered locale model. The author has decided
> there will be no community contribution: only locales actually
> maintained by the author ship. As a result, the Tier framework, the
> 8 stub locales, and the "track placeholder keys" mechanism are
> dropped. The ramifications throughout the document are noted inline
> with `~~strikethrough~~` where the original text remains for
> historical reference, and bold notes on the corrected stance.

---

## Context

The application is currently English-only. There is no `flutter_localizations`
scaffolding, no ARB files, no locale detection, and no UI affordance for the
user to switch the app language. `intl: ^0.20.1` is declared in `pubspec.yaml`
but is used only for date and number formatting.

User-facing text is scattered across roughly 700 strings in ~141 Dart files.
A single area is already centralized: `lib/config/tooltip_strings.dart`
(~240 tooltip labels). All other strings are inline `Text('...')` literals,
toast/error messages with `'$variable'` interpolation, dialog labels, etc.

The `assets/flags/` directory and `LanguagePreferencesSection` in Settings
manage **mod translation domain** languages (the languages the user translates
mods between), which is unrelated to the **app UI** language addressed by
this spec.

## Goal

Localize the entire user-facing UI of the application so that the app can be
shipped in 10+ languages, with community contributions accepted on top of an
English base maintained by the author. The migration is progressive,
feature-by-feature, with main remaining mergeable at every step.

## Non-goals

- Localizing **LLM system prompts** (kept English; documented best practice
  for translation quality).
- Localizing **`docs/user_guide.md`** (2 557 lines; English remains canonical;
  community translations welcome later, out of scope here).
- Localizing **`RELEASE_NOTES.md`** (changelog file shipped with the repo,
  English).
- Localizing the **Inno Setup installer chrome** (the installer's own UI may
  enable additional Inno languages later via `inno_bundle`; this is a
  one-line config and tracked separately).
- Localizing **`assets/flags/*` filenames** (these are domain data; languages
  the user's mods are translated between).

## High-level decisions

| Decision | Choice | Rationale |
|---|---|---|
| Source language | `en` | Lingua franca; best LLM downstream quality; consistent with English-only commit messages rule |
| Target locales | `en` + `fr` complete (author-maintained). Additional locales added one-by-one as the author commits to maintaining them. | No community contribution — every shipped locale is fully maintained by the author. |
| Tooling | `slang` + `slang_flutter` (JSON files, codegen, type-safe) | JSON is Claude-Code-friendly; sharded namespaces match feature-by-feature migration; type-safe call sites prevent silent regressions |
| File format | JSON, one file per locale per feature | Optimal for editing single feature in isolation; standard format for community |
| Migration strategy | Progressive, feature-by-feature | Main always mergeable; PRs reviewable; mixed state during migration is acceptable |
| Fallback | `fallback_strategy: base_locale` | Missing keys fall back to English silently; no broken screens |
| Generated `strings.g.dart` | Not committed (`.gitignore`) | Avoids large generated diffs in PRs; regenerated locally and in CI |
| Persistence | `shared_preferences` key `app_locale` | Already in pubspec; trivial to use |

## Architecture

### Package & config

Add to `pubspec.yaml`:

```yaml
dependencies:
  slang: ^4.x
  slang_flutter: ^4.x

dev_dependencies:
  build_runner: ^2.10.3   # already present; slang reuses it indirectly
```

Create `slang.yaml` at the repo root:

```yaml
base_locale: en
fallback_strategy: base_locale
input_directory: lib/i18n
input_file_pattern: .i18n.json
output_directory: lib/i18n
output_file_name: strings.g.dart
namespaces: true
locale_handling: true
flutter_integration: true
translate_var: t
enum_name: AppLocale
key_case: camel
key_map_case: camel
param_case: camel
```

Add to `.gitignore`:

```
lib/i18n/strings.g.dart
```

### Directory layout

```
lib/i18n/
├── strings.g.dart                ← generated, gitignored
├── README.md                     ← contributor guide
├── _app/                         ← cross-cutting app shell strings
│   ├── _app.i18n.json            ← en (base)
│   ├── _app_fr.i18n.json
│   ├── _app_de.i18n.json
│   └── ...
├── _common/                      ← reusable atoms (Save/Cancel/Yes/No/...)
├── _tooltips/                    ← migrated from lib/config/tooltip_strings.dart
├── home/
├── settings/
├── translation_editor/
├── projects/
├── mods/
├── glossary/
├── search/
├── import_export/
├── pack_compilation/
├── steam_publish/
├── help/
├── bootstrap/
├── activity/
├── translation_memory/
└── release_notes/
```

17 namespaces total. Each namespace folder holds one JSON file per locale.

### Naming conventions

- **Keys**: camelCase (`t.home.welcomeMessage`).
- **Nesting**: feature → optional sub-group → key. Example:
  `t.settings.languagePreferences.title`.
- **Sub-group prefixes**:
  - `errors.*` for error/exception messages (`t.glossary.errors.deleteFailed`)
  - `actions.*` for buttons / menu actions (`t.home.actions.refresh`)
  - `dialogs.*` for dialog content (`t.home.dialogs.confirmDelete.title`)
  - `tooltips.*` for hover tooltips (when not migrated to `_tooltips`)
- **`_common` namespace**: reusable atoms — `t.common.actions.save`,
  `t.common.actions.cancel`, `t.common.confirm`, `t.common.yes`,
  `t.common.no`, etc.
- **`_app` namespace**: app shell strings (window title, menu bar,
  about dialog, generic loading/error states).

### Code generation

- `dart run slang` regenerates `lib/i18n/strings.g.dart` from JSON inputs.
- The build command in `CLAUDE.md` is extended to:

  ```
  dart run build_runner build --delete-conflicting-outputs && dart run slang
  ```

- During development, optionally run `dart run slang watch` in a terminal.

### Runtime initialization

In `lib/main.dart`, before `runApp`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await LocaleSettings.useDeviceLocale();
// later overridden by persisted preference if any
final prefs = await SharedPreferences.getInstance();
final savedLocale = prefs.getString('app_locale');
if (savedLocale != null) {
  LocaleSettings.setLocaleRaw(savedLocale);
}
runApp(TranslationProvider(child: const TwmtApp()));
```

At call sites:

```dart
final t = Translations.of(context);
Text(t.home.welcomeMessage);
```

A short `import 'package:twmt/i18n/strings.g.dart';` exposes the generated
`t` getter and `LocaleSettings`/`AppLocale` types.

## Locale detection, persistence, settings UI

### First launch

`LocaleSettings.useDeviceLocale()` reads `Platform.localeName`. If it is
not in the supported list, fallback to `en`.

### Subsequent launches

A `localeControllerProvider` (Riverpod) reads `app_locale` from
`shared_preferences`. If present, applies it via `LocaleSettings.setLocaleRaw`.

### Changing the locale at runtime

The Settings UI dropdown calls `localeController.setLocale(AppLocale.fr)`,
which:

1. Calls `LocaleSettings.setLocale(AppLocale.fr)`.
2. Persists `'fr'` in `shared_preferences`.
3. Riverpod invalidates dependants; widgets that read `Translations.of(context)`
   rebuild instantly. **No app restart required.**

### Settings UI section

A new section `AppLanguageSection` in
`lib/features/settings/widgets/general/`:

- A dropdown listing `AppLocale.values`.
- Each entry shows: native name (`Français`, `Deutsch`, `日本語`) +
  flag from `assets/flags/<code>.png` when the ISO code matches
  (fallback: no flag).
- A first option `System default` clears the saved preference and rebases
  on device locale.
- Distinct from the existing `LanguagePreferencesSection` (which manages
  *mod translation* languages); a short helper text clarifies the difference.

### Optional v1 polish

- A coverage threshold (e.g. 50%) below which a locale is hidden from the
  dropdown. Off by default; enabled later if needed.

## Dynamic strings

### Simple interpolation (~80% of cases)

```json
{
  "errors": {
    "deleteFailed": "Failed to delete entry: {error}"
  }
}
```

```dart
Text(t.glossary.errors.deleteFailed(error: e.toString()))
```

### Plurals

```json
{
  "modCount": {
    "one": "{count} mod",
    "other": "{count} mods"
  }
}
```

```dart
Text(t.mods.modCount(count: mods.length, n: mods.length))
```

### Date and number formatting

Continue using `intl` (`DateFormat`, `NumberFormat`) with the current locale:

```dart
DateFormat.yMMMd(LocaleSettings.currentLocale.languageCode)
    .format(timestamp);
```

Format the value first, then inject the formatted string into the i18n
template via `{date}` / `{count}` parameters. **Never** localize numbers
or dates inside the template.

### Errors derived from exceptions

Convention:

- Never translate `e.toString()`; it is a technical message.
- Always wrap with a localized prefix:
  `t.glossary.errors.deleteFailed(error: e.toString())`.
- For known business errors (validation, auth, quota, etc.), define a
  `sealed class AppError` in `lib/utils/` and map each variant to a
  localized message via `switch`.

### ICU advanced (gender, select)

Out of scope for v1 (no current usage identified). `slang` supports it
when needed.

## Migration plan

### Step 0 — infrastructure (single PR)

1. Add `slang` + `slang_flutter` to `pubspec.yaml`.
2. Create `slang.yaml`, `lib/i18n/_app/`, `lib/i18n/_common/`,
   `lib/i18n/_tooltips/` (empty stubs OK).
3. Wire `LocaleSettings.useDeviceLocale()` and persistence in `main.dart`.
4. Add the `localeControllerProvider` (Riverpod).
5. Add the `AppLanguageSection` to Settings (functional but switches between
   `en` and `fr` only at this stage; the rest of the UI is still hardcoded).
6. Add `lib/i18n/strings.g.dart` to `.gitignore`.
7. Update `CLAUDE.md` with the new build command and the i18n contributor
   rule (see "Claude Code rule" below).
8. Add `lib/i18n/README.md`.
9. Add the CI guard (`dart run slang analyze`) to GitHub Actions.

### Migration order

| # | Lot | Volume | Notes |
|---|---|---|---|
| 1 | `_tooltips` | ~240 | Drop-in: `tooltip_strings.dart` → `_tooltips_*.i18n.json` |
| 2 | `bootstrap` + `activity` | small | Visible on first launch |
| 3 | `home` | medium | Primary surface |
| 4 | `settings` | large | Sub-PR per section is fine |
| 5 | `translation_editor` | very large | Split: toolbar / inspector / datagrid headers / dialogs |
| 6 | `mods` + `projects` | large | Main navigation |
| 7 | `glossary` + `translation_memory` + `search` | medium | Secondary features |
| 8 | `import_export` + `pack_compilation` + `steam_publish` | medium | Advanced workflows |
| 9 | `release_notes` (UI only) + `help` (UI only) | small | Finalization |

### "Feature migrated" definition of done

A feature counts as migrated when:

1. Every UI string in `lib/features/<feature>/` goes through `t.<feature>.*`.
2. The keys exist in **all** active locale files of the namespace
   (English mandatory; other locales fall back to EN if empty).
3. No `Text('<literal>')` remains in `lib/features/<feature>/`
   (whitelist for debug-only or asset-path strings, see tests below).
4. The feature passes the `no_hardcoded_strings_test` for that path.

### Mixed state during migration

Until all features are migrated, some screens stay English-only even when
the user picks `fr`. This is by design and acceptable: the fallback strategy
displays the English string transparently.

## Tests and CI guards

### `slang analyze`

Slang ships `dart run slang analyze`, which detects:

- Missing keys in a non-base locale.
- Orphan keys (present in a non-base locale, missing in base).
- Inconsistent parameter names between locales for the same key.

Wired into:

- A pre-push convenience script (optional, dev ergonomics).
- A **GitHub Action** on every PR — **blocking**.

### Dart unit tests

- `test/i18n/keys_completeness_test.dart` — load each locale JSON, assert
  the key set matches the base.
- `test/i18n/format_consistency_test.dart` — for each shared key, assert
  the placeholder set (`{x}`) matches across locales.
- `test/i18n/no_hardcoded_strings_test.dart` — for migrated features
  (configurable list), parse the `.dart` files and forbid `Text('...')`
  literals. A small per-file allow-list handles exceptions (debug labels,
  asset paths, monospace tokens).

### Manual checks

- After each feature migration: switch the locale in Settings, navigate
  the migrated screen, validate visually.
- Persistence test: start in `fr`, navigate 5 screens, restart, confirm
  the locale is still `fr`.

## Locales

Only locales actually maintained by the author ship. There are no
empty stubs and no community-PR pipeline. The shipped set grows
deliberately — when the author commits to maintaining a new locale,
it gets added; until then, the dropdown does not list it.

Initial set: `en` (base) + `fr` (author).

### Tone

For every shipped locale, when the target language has both an
informal and a formal second-person form, the **formal** form is
mandatory. See `lib/i18n/README.md` for the full list (FR `vous`,
DE `Sie`, ES `usted`, IT `Lei`, PL `Pan`/`Pani`, RU `Вы`, PT `você`).

### Adding a new locale later

1. Create `lib/i18n/<code>/`.
2. Translate every namespace file (no English-verbatim placeholders —
   the locale is committed only when complete).
3. Add it to `lib/i18n/app_locale_info.dart` (`_localeInfo` map) with
   its native name and matching flag asset.
4. `dart run slang && dart run slang analyze && flutter test test/i18n`.

### What the structural tests catch

Because every shipped locale is fully maintained, the structural tests
(`keys_completeness_test`, `format_consistency_test`) catch real bugs:
a key the author forgot to add to a locale, or a placeholder rename
applied unevenly. They do not need to be relaxed for "stubs in
progress" — there are none.

## Maintenance workflow

`lib/i18n/README.md` documents:

- How to add a key (propagate to every locale at once, run slang +
  analyze + tests).
- How to add a locale (only when the author is committed to maintaining
  it; no empty stubs).
- The naming conventions (camelCase, `errors.*`, `actions.*`, etc.) and
  the formal-second-person rule.

## Claude Code rule (added to `CLAUDE.md`)

The following section is added to the project `CLAUDE.md` during Step 0
of the migration:

```
## Internationalization (i18n)

- User-facing strings MUST go through slang translations (`t.feature.key`),
  never inline `Text('...')` literals (whitelist exceptions in
  test/i18n/no_hardcoded_strings_test.dart).
- When adding a new translation key:
  1. Add the entry in the base locale file (`<feature>.i18n.json`).
  2. Add the SAME key in every locale file of the same namespace
     (`<feature>_fr.i18n.json`, `<feature>_de.i18n.json`, ...).
     Use a faithful translation when you can produce one; otherwise copy
     the English string verbatim — users see English in that locale, which
     is acceptable for an unverified translation — and flag the key in the
     PR description so a native speaker can review it.
  3. Run `dart run slang` to regenerate `strings.g.dart`.
  4. Run `dart run slang analyze` and ensure zero warnings.
- When removing a key, remove it from all locale files at once.
- When renaming a key, rename it in all locale files at once.
- Never localize LLM system prompts; pass `targetLanguage` as a parameter
  in the prompt instead.
- Never localize `assets/flags/*` filenames or any domain data tied to
  mod-translation languages.
```

This rule is mandatory and not optional; the CI guard (`slang analyze`)
enforces the structural part automatically.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| 700-string migration drags on, mixed state forever | Hard scope each PR to one feature; main always mergeable; tracker in `lib/i18n/README.md` |
| Generated file diffs pollute PRs | Gitignore `strings.g.dart`; rebuild in CI |
| Contributors break key consistency | `slang analyze` blocking on PR; tests assert key sets and placeholder consistency |
| Key naming drift between contributors | Conventions documented in `lib/i18n/README.md`; reviewer enforces |
| Existing typos baked into translations (`Transalation`) | Fix typos *before* extracting strings into ARB-equivalent JSON; final UI copy review during Step 0 |
| Performance of `Translations.of(context)` rebuilds | Slang's listener subscribes only once per `TranslationProvider` subtree; impact negligible |
| User confuses "App language" with "Translation languages" in Settings | Distinct section name (`AppLanguageSection`), helper text, distinct icon |

## Open questions for the implementation plan

1. Hook on JSON edit: optional `PostToolUse` hook running
   `dart run slang analyze` automatically (configurable via
   `update-config`).
2. Whether to extract a one-shot string-collection script (Q4 option C
   "hybrid") to bulk-import all current `Text('...')` literals into
   the relevant namespace as a starting catalog before per-feature
   refactor — currently treated as out of scope, can be added if
   velocity is too low.

(Removed: questions about Tier-2 stubs, placeholder-tracking, and
coverage thresholds. They no longer apply now that only fully
maintained locales ship.)
