# Translations

The TWMT user interface is localized with [slang](https://pub.dev/packages/slang).
This directory holds the source-of-truth translation files; the generated
Dart bindings (`strings*.g.dart`) and slang analyze reports
(`_missing_translations.json`, `_unused_translations.json`) are gitignored.

## Layout

The repository uses **locale-as-directory** with **namespace-per-file**:

````
lib/i18n/
├── en/                            base locale (source of truth)
│   ├── app.i18n.json              app shell strings
│   ├── common.i18n.json           reusable atoms (Save / Cancel / Yes / No / …)
│   └── (later) tooltips.i18n.json, home.i18n.json, settings.i18n.json, …
├── fr/                            non-base locale
│   ├── app.i18n.json
│   └── common.i18n.json
└── (future) de/, es/, …
````

- Each subdirectory is a locale code (lowercase ISO 639-1 / 639-2: `en`, `fr`,
  `de`, `pt`, `zh`, …).
- Each file inside a locale is one **namespace** — typically named after a
  feature folder under `lib/features/<feature>/`. Two cross-cutting
  namespaces sit at the top of the list:
  - `common` — reusable atoms shared across the app.
  - `app` — application-shell strings (window title, language picker, …).
- The base locale is **`en`**. Every other locale falls back to `en`
  when a key is missing (`fallback_strategy: base_locale` in `slang.yaml`).

## Adding a new key

1. Add the entry in the base locale file (`lib/i18n/en/<namespace>.i18n.json`).
2. Add the SAME key in every NON-base locale file of the same namespace
   (`lib/i18n/fr/<namespace>.i18n.json`, `lib/i18n/de/<namespace>.i18n.json`, …).
   When a faithful translation is not yet available, copy the English
   string verbatim — the user will see English for that key in that
   locale, which is the expected placeholder state for an unverified
   translation. Flag the key in the PR description so a native speaker
   can review it.
3. Regenerate the typed Dart bindings:

   ```bash
   dart run slang
   ```

4. Validate:

   ```bash
   dart run slang analyze
   flutter test test/i18n
   ```

   Both must report zero issues.

## Adding a new namespace

A namespace is typically a feature folder under `lib/features/<feature>/`.
To add namespace `my_feature`:

1. Create `lib/i18n/en/my_feature.i18n.json` with the strings and a clear
   keyspace (e.g. `actions.*`, `errors.*`, `dialogs.*`).
2. Create the same file in EVERY other locale directory (`fr/`, `de/`, …)
   with matching keys.
3. `dart run slang` regenerates the bindings; you can then call
   `t.myFeature.actions.save` etc. from Dart.

## Adding a new locale

1. Create `lib/i18n/<code>/` (lowercase ISO code).
2. For every namespace present under `lib/i18n/en/`, create the
   corresponding file in the new directory and translate every value.
   Keys, structure, and `{placeholders}` MUST be identical to the base.
3. Add the locale to `lib/i18n/app_locale_info.dart` (`_localeInfo` map),
   with its native name and the matching flag asset under
   `assets/flags/<code>.png`.
4. Regenerate and validate as above.

## Conventions

- **Keys**: camelCase (`welcomeMessage`).
- **Sub-groups**: `errors.*`, `actions.*`, `dialogs.*`, `tooltips.*`.
- **Placeholders**: `{name}`, `{count}`. Format dates and numbers with
  `intl` BEFORE injecting them; never inside the template.
- **Plurals**: use slang's `one`/`other` map syntax.
- **Never localize**: LLM system prompts, `assets/flags/*` filenames.
- **Proper nouns are never translated** in any locale. This includes product
  and brand names, game titles, and platform features. Non-exhaustive list:
  `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`,
  `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, and any
  specific Total War game/DLC name. When in doubt, keep the English form
  rather than coining a translation.
- **Tone (T-V distinction)**: when the target language has both an
  informal and a formal second-person form, ALWAYS use the **formal**
  one. The app addresses the user with the polite register.
  - French: `vous` / `vos` / `votre`, never `tu` / `tes` / `ton`.
  - German: `Sie` / `Ihr`, never `du` / `dein`.
  - Spanish: `usted`, never `tú`.
  - Italian: `Lei`, never `tu`.
  - Polish: `Pan` / `Pani`, never `ty`.
  - Russian: `Вы`, never `ты`.
  - Portuguese: `você` (BR) / `o senhor` / `a senhora` (PT formal),
    never `tu`.
  - Languages with no T-V distinction (English, Japanese honorifics
    aside, Mandarin in modern app contexts): no action needed.
  Reformulate in the impersonal voice when both forms feel awkward
  ("Saisir un mot-clé" rather than "Vous pouvez saisir un mot-clé").

## Tracking incomplete locales

A value byte-identical to the English value in a non-English file
indicates "not yet translated". Reviewers and contributors can compute
the placeholder set with a simple diff against the base file. No
in-band metadata is used.

## Tooling reference

| Command | Purpose |
|---|---|
| `dart run slang` | Regenerate `strings*.g.dart` from JSON sources |
| `dart run slang analyze` | Detect missing/unused keys, parameter mismatches |
| `dart run slang watch` | Live-regenerate during development |
| `flutter test test/i18n` | Run structural tests (key sets, placeholders) |

The build command in `CLAUDE.md` runs `dart run build_runner build` AND
`dart run slang` together.
