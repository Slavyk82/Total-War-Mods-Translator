# Spanish Locale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Spanish (Castilian, code `es`) as a fully-translated UI locale of TWMT alongside `en` (base) and `fr`, with all 20 namespaces translated, the locale registered in the picker, and zero warnings from `dart run slang analyze` + `flutter test test/i18n`.

**Architecture:** Mechanical replication of the existing `lib/i18n/fr/` pattern. 20 new JSON files under `lib/i18n/es/` (one per existing English namespace), plus one entry added to the `_localeInfo` map in `lib/i18n/app_locale_info.dart`. Translation work is dispatched to subagents in batches grouped by feature cohesion. No application code changes outside `app_locale_info.dart`.

**Tech Stack:** Flutter, [slang](https://pub.dev/packages/slang) i18n (locale-as-directory + namespace-per-file), JSON source files with `{placeholder}` syntax and `one`/`other` plural maps. Castilian Spanish, formal `usted` register.

**Reference spec:** `docs/superpowers/specs/2026-04-26-spanish-locale-design.md`.

---

## Universal subagent rules

Every translation subagent dispatched in Tasks 1–5 receives the **same hard constraints**, repeated in their prompt:

1. **Locale is castellano (Spain)**. Microsoft Spanish style guide conventions.
2. **Formal register `usted` exclusively**. Never `tú`, `tu`, `tus`, `vosotros`, `os`, `vuestro`. When both forms feel awkward, reformulate impersonally ("Introducir una palabra clave" rather than "Puede usted introducir una palabra clave"). For verb forms, use 3rd-person singular polite form (e.g. "Guarde", "Cancele", "Confirme") in imperative UI labels — but for short button labels prefer the infinitive, which is industry-standard ("Guardar", "Cancelar", "Confirmar").
3. **Identical structure.** The output JSON MUST have the SAME keys, the SAME nesting, the SAME placeholders (`{name}`, `{count}`, …) with identical names and case as the English source. SAME plural maps (`one` / `other`).
4. **Proper nouns are NEVER translated.** Copy verbatim: `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, and any specific Total War game/DLC name. The acronym `TWMT` is also a proper noun and stays as-is. File extensions like `.pack`, `.tmx`, `.csv` stay as-is.
5. **Locked terminology** (must be used consistently across files):

   | English | Spanish |
   |---|---|
   | Mod / Mods | Mod / Mods |
   | Pack file / Pack | archivo pack / pack |
   | Glossary | Glosario |
   | Translation Memory | Memoria de traducción |
   | Project | Proyecto |
   | Settings | Ajustes |
   | Search | Buscar |
   | Save | Guardar |
   | Cancel | Cancelar |
   | Delete | Eliminar |
   | Close | Cerrar |
   | Open | Abrir |
   | Import | Importar |
   | Export | Exportar |
   | Compile | Compilar |
   | Publish | Publicar |
   | Translate | Traducir |
   | Validation | Validación |
   | Issue | Problema |
   | Warning | Advertencia |
   | Error | Error |
   | File / Folder | Archivo / Carpeta |
   | Browse | Examinar |
   | Add / Remove | Añadir / Quitar |
   | Edit | Editar |
   | Refresh | Actualizar |
   | Reset | Restablecer |
   | Apply | Aplicar |
   | Loading | Cargando |
   | Done | Hecho (action) / Listo (state) |
   | Skip | Omitir |
   | Next / Back / Previous | Siguiente / Atrás / Anterior |
   | Confirm | Confirmar |
   | Copy | Copiar |
   | Yes / No / OK | Sí / No / OK |

6. **Use the French file (`lib/i18n/fr/<namespace>.i18n.json`) as a reference for tone and length.** It already uses formal register; placeholder reformulations there are sanity-checked.
7. **Output**: ONE JSON file per assigned namespace, written to `lib/i18n/es/<namespace>.i18n.json`. Valid JSON, UTF-8, 2-space indent, trailing newline (match the formatting of the English source).
8. **Do not modify any other file.** Do not regenerate slang bindings. Do not commit. Do not run any command. Just write the JSON files.
9. **Do not invent keys.** If a key looks redundant or unclear, translate it anyway based on context — never delete or rename keys.

---

## File Structure

| Path | Action | Owner |
|---|---|---|
| `lib/i18n/es/common.i18n.json` | create | Task 1 (Batch A) |
| `lib/i18n/es/app.i18n.json` | create | Task 1 (Batch A) |
| `lib/i18n/es/widgets.i18n.json` | create | Task 1 (Batch A) |
| `lib/i18n/app_locale_info.dart` | modify | Task 2 |
| `lib/i18n/es/home.i18n.json` | create | Task 3 (Batch B) |
| `lib/i18n/es/projects.i18n.json` | create | Task 3 (Batch B) |
| `lib/i18n/es/mods.i18n.json` | create | Task 3 (Batch B) |
| `lib/i18n/es/search.i18n.json` | create | Task 3 (Batch B) |
| `lib/i18n/es/translation.i18n.json` | create | Task 4 (Batch C) |
| `lib/i18n/es/translation_editor.i18n.json` | create | Task 4 (Batch C) |
| `lib/i18n/es/translation_memory.i18n.json` | create | Task 4 (Batch C) |
| `lib/i18n/es/glossary.i18n.json` | create | Task 4 (Batch C) |
| `lib/i18n/es/game_translation.i18n.json` | create | Task 4 (Batch C) |
| `lib/i18n/es/import_export.i18n.json` | create | Task 5 (Batch D) |
| `lib/i18n/es/pack_compilation.i18n.json` | create | Task 5 (Batch D) |
| `lib/i18n/es/steam_publish.i18n.json` | create | Task 5 (Batch D) |
| `lib/i18n/es/bootstrap.i18n.json` | create | Task 5 (Batch D) |
| `lib/i18n/es/settings.i18n.json` | create | Task 6 (Batch E) |
| `lib/i18n/es/tooltips.i18n.json` | create | Task 6 (Batch E) |
| `lib/i18n/es/activity.i18n.json` | create | Task 6 (Batch E) |
| `lib/i18n/es/release_notes.i18n.json` | create | Task 6 (Batch E) |

20 JSON files + 1 Dart file edit.

---

## Task 1: Batch A — Core atoms (common, app, widgets)

**Goal:** Translate the cross-cutting namespaces first. These set the terminology baseline that the remaining batches will reference (and they're tiny — `common` is 23 lines).

**Files:**
- Create: `lib/i18n/es/common.i18n.json`
- Create: `lib/i18n/es/app.i18n.json`
- Create: `lib/i18n/es/widgets.i18n.json`

- [ ] **Step 1: Dispatch translation subagent for Batch A**

Use `Agent` tool with `subagent_type: general-purpose`, `model: opus`. Prompt:

> You are translating UI strings from English to **Spanish (Castilian, Spain — `es-ES`)** for a Flutter desktop application that helps users translate Total War game mods.
>
> **Translate exactly these three files**, copying the structure, keys, placeholders, and plural maps from the English source verbatim — translating only the values:
> - `lib/i18n/en/common.i18n.json` → write to `lib/i18n/es/common.i18n.json`
> - `lib/i18n/en/app.i18n.json` → write to `lib/i18n/es/app.i18n.json`
> - `lib/i18n/en/widgets.i18n.json` → write to `lib/i18n/es/widgets.i18n.json`
>
> **Hard constraints (non-negotiable):**
>
> 1. **Castilian Spanish, formal `usted` register exclusively.** Never `tú`, `tu`, `vosotros`, `os`. For short button labels prefer the infinitive ("Guardar", "Cancelar"). For instructions/prompts use 3rd-person polite imperative or impersonal reformulation.
> 2. **Identical structure**: same keys, same nesting, same `{placeholder}` names, same `one`/`other` plural maps. Output valid JSON, UTF-8, 2-space indent, trailing newline.
> 3. **Proper nouns are NEVER translated.** Copy verbatim: `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, any Total War game/DLC name, `TWMT`, file extensions (`.pack`, `.tmx`, `.csv`).
> 4. **Locked terminology** (use consistently — these are the project standard, set by the design spec):
>    - Mod / Mods → Mod / Mods (invariant)
>    - Pack file / Pack → archivo pack / pack
>    - Glossary → Glosario
>    - Translation Memory → Memoria de traducción
>    - Project → Proyecto
>    - Settings → Ajustes
>    - Search → Buscar
>    - Save → Guardar; Cancel → Cancelar; Delete → Eliminar; Close → Cerrar; Open → Abrir
>    - Import → Importar; Export → Exportar; Compile → Compilar; Publish → Publicar; Translate → Traducir
>    - Validation → Validación; Issue → Problema; Warning → Advertencia; Error → Error
>    - File → Archivo; Folder → Carpeta; Browse → Examinar
>    - Add → Añadir; Remove → Quitar; Edit → Editar; Refresh → Actualizar
>    - Reset → Restablecer; Apply → Aplicar; Loading → Cargando
>    - Done → Hecho (action) / Listo (state); Skip → Omitir
>    - Next → Siguiente; Back → Atrás; Previous → Anterior; Confirm → Confirmar; Copy → Copiar
>    - Yes / No / OK → Sí / No / OK
>
> 5. **Reference**: read `lib/i18n/fr/common.i18n.json`, `lib/i18n/fr/app.i18n.json`, `lib/i18n/fr/widgets.i18n.json` for tone and register sanity-check (French already uses formal "vous").
> 6. **Do not** regenerate slang bindings, run any command, modify any other file, or commit. Just write the three JSON files.
>
> Read the three English source files, read the three French reference files, then write the three Spanish files. Report when done with a one-paragraph summary.

- [ ] **Step 2: Verify subagent output**

Run:

```bash
ls lib/i18n/es/common.i18n.json lib/i18n/es/app.i18n.json lib/i18n/es/widgets.i18n.json
python -c "import json; [json.load(open(f'lib/i18n/es/{n}.i18n.json', encoding='utf-8')) for n in ['common','app','widgets']]; print('OK')"
```

Expected: all three files listed, `OK` printed (valid JSON).

Then verify keys match by structural diff: read both English and Spanish, confirm same key set and same `{placeholder}` set in each value. Spot-check a handful of values for `tú` / `vosotros` (should be ZERO matches):

```bash
grep -E '\b(tú|vosotros|tu |tus |os )\b' lib/i18n/es/common.i18n.json lib/i18n/es/app.i18n.json lib/i18n/es/widgets.i18n.json || echo "OK: no informal forms"
```

Expected: `OK: no informal forms`.

Also verify Steam Workshop is preserved verbatim if it appears:

```bash
grep -i "steam workshop" lib/i18n/es/*.json && grep -i "steam workshop" lib/i18n/en/app.i18n.json
```

Both greps should match the same string `Steam Workshop` exactly (capitalization preserved).

- [ ] **Step 3: Commit Batch A**

```bash
git add lib/i18n/es/common.i18n.json lib/i18n/es/app.i18n.json lib/i18n/es/widgets.i18n.json
git commit -m "feat(i18n): seed Spanish translations for core atoms (common, app, widgets)"
```

---

## Task 2: Register `AppLocale.es` in app_locale_info

**Goal:** Now that `lib/i18n/es/` exists with at least one file, slang will generate `AppLocale.es` on the next regeneration. Register the display metadata so the locale picker picks it up.

**Files:**
- Modify: `lib/i18n/app_locale_info.dart`

- [ ] **Step 1: Regenerate slang bindings to expose `AppLocale.es`**

```bash
dart run slang
```

Expected output: lists `en` and `fr` as before, plus a new `es` locale; writes `lib/i18n/strings_es.g.dart`.

- [ ] **Step 2: Add the Spanish entry to `_localeInfo`**

Edit `lib/i18n/app_locale_info.dart`. Find the `_localeInfo` map (around lines 17–28) and add the third entry after `AppLocale.fr`:

```dart
const Map<AppLocale, AppLocaleInfo> _localeInfo = {
  AppLocale.en: AppLocaleInfo(
    locale: AppLocale.en,
    nativeName: 'English',
    flagAsset: 'assets/flags/en.png',
  ),
  AppLocale.fr: AppLocaleInfo(
    locale: AppLocale.fr,
    nativeName: 'Français',
    flagAsset: 'assets/flags/fr.png',
  ),
  AppLocale.es: AppLocaleInfo(
    locale: AppLocale.es,
    nativeName: 'Español',
    flagAsset: 'assets/flags/es.png',
  ),
};
```

- [ ] **Step 3: Regenerate Riverpod/JSON bindings**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: build succeeds, no errors. (Per `CLAUDE.md`, slang must run before `build_runner`. Step 1 already did slang, so this is the safe second step.)

- [ ] **Step 4: Run slang analyze — expect missing keys for un-translated namespaces**

```bash
dart run slang analyze
```

Expected: reports MISSING keys for `es` in 17 namespaces (everything except `common`, `app`, `widgets`). This is the expected interim state — translation continues in Tasks 3–6. Make a note of the missing-key count for sanity-checking the final task.

- [ ] **Step 5: Commit the locale registration**

```bash
git add lib/i18n/app_locale_info.dart
git commit -m "feat(i18n): register Spanish locale (es) in app locale info"
```

---

## Task 3: Batch B — Navigation & library (home, projects, mods, search)

**Goal:** Translate top-level navigation surfaces.

**Files:**
- Create: `lib/i18n/es/home.i18n.json`
- Create: `lib/i18n/es/projects.i18n.json`
- Create: `lib/i18n/es/mods.i18n.json`
- Create: `lib/i18n/es/search.i18n.json`

- [ ] **Step 1: Dispatch translation subagent for Batch B**

Use `Agent` tool with `subagent_type: general-purpose`, `model: opus`. Prompt:

> You are translating UI strings from English to **Spanish (Castilian, Spain — `es-ES`)** for a Flutter desktop application (TWMT) that helps users translate Total War game mods.
>
> **Translate exactly these four files**, copying the structure, keys, placeholders, and plural maps from the English source verbatim — translating only the values:
> - `lib/i18n/en/home.i18n.json` → write to `lib/i18n/es/home.i18n.json`
> - `lib/i18n/en/projects.i18n.json` → write to `lib/i18n/es/projects.i18n.json`
> - `lib/i18n/en/mods.i18n.json` → write to `lib/i18n/es/mods.i18n.json`
> - `lib/i18n/en/search.i18n.json` → write to `lib/i18n/es/search.i18n.json`
>
> **Hard constraints (non-negotiable):**
>
> 1. **Castilian Spanish, formal `usted` register exclusively.** Never `tú`, `tu`, `vosotros`, `os`, `vuestro`.
> 2. **Identical structure**: same keys, same nesting, same `{placeholder}` names, same `one`/`other` plural maps. Output valid JSON, UTF-8, 2-space indent, trailing newline.
> 3. **Proper nouns are NEVER translated.** Copy verbatim: `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, any Total War game/DLC name, `TWMT`, file extensions.
> 4. **Locked terminology** (use exactly — already established in Batch A, must remain consistent):
>    - Mod / Mods → Mod / Mods; Pack file → archivo pack; Glossary → Glosario; Translation Memory → Memoria de traducción
>    - Project → Proyecto; Settings → Ajustes; Search → Buscar
>    - Save → Guardar; Cancel → Cancelar; Delete → Eliminar; Close → Cerrar; Open → Abrir
>    - Import → Importar; Export → Exportar; Compile → Compilar; Publish → Publicar; Translate → Traducir
>    - Validation → Validación; Issue → Problema; Warning → Advertencia; Error → Error
>    - File → Archivo; Folder → Carpeta; Browse → Examinar
>    - Add → Añadir; Remove → Quitar; Edit → Editar; Refresh → Actualizar
>    - Reset → Restablecer; Apply → Aplicar; Loading → Cargando
>    - Done → Hecho / Listo; Skip → Omitir; Next → Siguiente; Back → Atrás; Previous → Anterior
>    - Confirm → Confirmar; Copy → Copiar; Yes / No → Sí / No
>
> 5. **Reference for tone and register**: read `lib/i18n/fr/home.i18n.json`, `lib/i18n/fr/projects.i18n.json`, `lib/i18n/fr/mods.i18n.json`, `lib/i18n/fr/search.i18n.json` (French already uses formal "vous"). Also read `lib/i18n/es/common.i18n.json` and `lib/i18n/es/app.i18n.json` to align with the Spanish baseline already in place.
> 6. **Do not** regenerate slang bindings, run any command, modify any other file, or commit. Just write the four JSON files.
>
> Read the four English sources, the four French references, the two existing Spanish files, then write the four new Spanish files. Report when done.

- [ ] **Step 2: Verify subagent output**

```bash
ls lib/i18n/es/home.i18n.json lib/i18n/es/projects.i18n.json lib/i18n/es/mods.i18n.json lib/i18n/es/search.i18n.json
python -c "import json; [json.load(open(f'lib/i18n/es/{n}.i18n.json', encoding='utf-8')) for n in ['home','projects','mods','search']]; print('OK')"
grep -E '\b(tú|vosotros|tu |tus |os |vuestro)\b' lib/i18n/es/home.i18n.json lib/i18n/es/projects.i18n.json lib/i18n/es/mods.i18n.json lib/i18n/es/search.i18n.json || echo "OK: no informal forms"
grep -i "steam workshop\|total war" lib/i18n/es/projects.i18n.json lib/i18n/es/mods.i18n.json | head
```

Expected: 4 files exist, valid JSON, no informal forms, proper nouns intact.

- [ ] **Step 3: Run slang analyze — confirm Batch B keys are no longer missing**

```bash
dart run slang analyze
```

Expected: still reports MISSING keys for the 13 remaining namespaces, but `home`, `projects`, `mods`, `search` are no longer flagged.

- [ ] **Step 4: Commit Batch B**

```bash
git add lib/i18n/es/home.i18n.json lib/i18n/es/projects.i18n.json lib/i18n/es/mods.i18n.json lib/i18n/es/search.i18n.json
git commit -m "feat(i18n): translate Spanish strings for navigation namespaces (home, projects, mods, search)"
```

---

## Task 4: Batch C — Translation core (translation, translation_editor, translation_memory, glossary, game_translation)

**Goal:** Translate the heaviest, most domain-rich batch. The translation_editor namespace alone is 353 lines.

**Files:**
- Create: `lib/i18n/es/translation.i18n.json`
- Create: `lib/i18n/es/translation_editor.i18n.json`
- Create: `lib/i18n/es/translation_memory.i18n.json`
- Create: `lib/i18n/es/glossary.i18n.json`
- Create: `lib/i18n/es/game_translation.i18n.json`

- [ ] **Step 1: Dispatch translation subagent for Batch C**

Use `Agent` tool with `subagent_type: general-purpose`, `model: opus`. Prompt:

> You are translating UI strings from English to **Spanish (Castilian, Spain — `es-ES`)** for the TWMT Flutter desktop app, which helps users translate Total War game mods.
>
> **Translate exactly these five files**, copying the structure, keys, placeholders, and plural maps from the English source verbatim — translating only the values:
> - `lib/i18n/en/translation.i18n.json` → `lib/i18n/es/translation.i18n.json`
> - `lib/i18n/en/translation_editor.i18n.json` → `lib/i18n/es/translation_editor.i18n.json`
> - `lib/i18n/en/translation_memory.i18n.json` → `lib/i18n/es/translation_memory.i18n.json`
> - `lib/i18n/en/glossary.i18n.json` → `lib/i18n/es/glossary.i18n.json`
> - `lib/i18n/en/game_translation.i18n.json` → `lib/i18n/es/game_translation.i18n.json`
>
> **Hard constraints (non-negotiable):**
>
> 1. **Castilian Spanish, formal `usted` register exclusively.** Never `tú`, `tu`, `vosotros`, `os`, `vuestro`.
> 2. **Identical structure**: same keys, same nesting, same `{placeholder}` names, same `one`/`other` plural maps. Output valid JSON, UTF-8, 2-space indent, trailing newline.
> 3. **Proper nouns are NEVER translated.** `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, any Total War game/DLC name, `TWMT`, file extensions (`.pack`, `.tmx`, `.csv`, `.loc`).
> 4. **Locked terminology** (must remain consistent with the rest of the app — use exactly):
>    - Mod / Mods → Mod / Mods; Pack file → archivo pack; Glossary → Glosario; Translation Memory → Memoria de traducción
>    - Project → Proyecto; Settings → Ajustes; Search → Buscar
>    - Save → Guardar; Cancel → Cancelar; Delete → Eliminar; Close → Cerrar; Open → Abrir
>    - Import → Importar; Export → Exportar; Compile → Compilar; Publish → Publicar; Translate → Traducir
>    - Validation → Validación; Issue → Problema; Warning → Advertencia; Error → Error
>    - File → Archivo; Folder → Carpeta; Browse → Examinar
>    - Add → Añadir; Remove → Quitar; Edit → Editar; Refresh → Actualizar
>    - Reset → Restablecer; Apply → Aplicar; Loading → Cargando
>    - Done → Hecho / Listo; Skip → Omitir; Next → Siguiente; Back → Atrás; Previous → Anterior
>    - Confirm → Confirmar; Copy → Copiar; Yes / No → Sí / No
>    - **Domain-specific** (this batch):
>      - Source / Target (translation) → Origen / Destino
>      - Source language → Idioma de origen; Target language → Idioma de destino
>      - String / Entry / Row → Cadena / Entrada / Fila
>      - Untranslated → Sin traducir; Translated → Traducido; Pending → Pendiente; Approved → Aprobado
>      - Match / Fuzzy match → Coincidencia / Coincidencia parcial
>      - Glossary term → Término del glosario
>      - Segment → Segmento
>      - Auto-translate → Traducción automática
>      - Review → Revisión; Reviewer → Revisor
>      - Suggestion → Sugerencia
>      - Bulk action → Acción en bloque
>      - Undo / Redo → Deshacer / Rehacer
>
> 5. **Reference for tone, register, and domain phrasing**: read the corresponding French files (`lib/i18n/fr/translation.i18n.json`, …) — they already use formal "vous" and the same translation-tool domain vocabulary. Also read `lib/i18n/es/common.i18n.json`, `lib/i18n/es/app.i18n.json`, `lib/i18n/es/widgets.i18n.json` to align with the Spanish baseline.
> 6. **Do not** regenerate slang bindings, run any command, modify any other file, or commit. Just write the five JSON files.
>
> Read the five English sources, the five French references, the three existing Spanish baseline files, then write the five new Spanish files. Report when done with a one-paragraph summary.

- [ ] **Step 2: Verify subagent output**

```bash
ls lib/i18n/es/translation.i18n.json lib/i18n/es/translation_editor.i18n.json lib/i18n/es/translation_memory.i18n.json lib/i18n/es/glossary.i18n.json lib/i18n/es/game_translation.i18n.json
python -c "import json; [json.load(open(f'lib/i18n/es/{n}.i18n.json', encoding='utf-8')) for n in ['translation','translation_editor','translation_memory','glossary','game_translation']]; print('OK')"
grep -E '\b(tú|vosotros|tu |tus |os |vuestro)\b' lib/i18n/es/translation*.i18n.json lib/i18n/es/glossary.i18n.json lib/i18n/es/game_translation.i18n.json || echo "OK: no informal forms"
```

Expected: 5 files exist, valid JSON, no informal forms.

- [ ] **Step 3: Run slang analyze**

```bash
dart run slang analyze
```

Expected: 8 namespaces still missing for `es` (the ones in Batches D and E).

- [ ] **Step 4: Commit Batch C**

```bash
git add lib/i18n/es/translation.i18n.json lib/i18n/es/translation_editor.i18n.json lib/i18n/es/translation_memory.i18n.json lib/i18n/es/glossary.i18n.json lib/i18n/es/game_translation.i18n.json
git commit -m "feat(i18n): translate Spanish strings for translation core (translation, editor, TM, glossary, game_translation)"
```

---

## Task 5: Batch D — Pipeline (import_export, pack_compilation, steam_publish, bootstrap)

**Goal:** Translate I/O and publication flows.

**Files:**
- Create: `lib/i18n/es/import_export.i18n.json`
- Create: `lib/i18n/es/pack_compilation.i18n.json`
- Create: `lib/i18n/es/steam_publish.i18n.json`
- Create: `lib/i18n/es/bootstrap.i18n.json`

- [ ] **Step 1: Dispatch translation subagent for Batch D**

Use `Agent` tool with `subagent_type: general-purpose`, `model: opus`. Prompt:

> You are translating UI strings from English to **Spanish (Castilian, Spain — `es-ES`)** for the TWMT Flutter desktop app.
>
> **Translate exactly these four files**:
> - `lib/i18n/en/import_export.i18n.json` → `lib/i18n/es/import_export.i18n.json`
> - `lib/i18n/en/pack_compilation.i18n.json` → `lib/i18n/es/pack_compilation.i18n.json`
> - `lib/i18n/en/steam_publish.i18n.json` → `lib/i18n/es/steam_publish.i18n.json`
> - `lib/i18n/en/bootstrap.i18n.json` → `lib/i18n/es/bootstrap.i18n.json`
>
> **Hard constraints (non-negotiable):**
>
> 1. **Castilian Spanish, formal `usted` register exclusively.** Never `tú`, `tu`, `vosotros`, `os`, `vuestro`.
> 2. **Identical structure**: same keys, same nesting, same `{placeholder}` names, same `one`/`other` plural maps. Output valid JSON, UTF-8, 2-space indent, trailing newline.
> 3. **Proper nouns are NEVER translated** — most importantly in this batch: `Steam Workshop`, `Steam` (these names appear extensively in `steam_publish.i18n.json`). Also `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, any Total War game/DLC name, `TWMT`, file extensions (`.pack`, `.tmx`, `.csv`).
> 4. **Locked terminology**:
>    - Mod / Mods → Mod / Mods; Pack file → archivo pack; Glossary → Glosario; Translation Memory → Memoria de traducción
>    - Project → Proyecto; Settings → Ajustes; Search → Buscar
>    - Save → Guardar; Cancel → Cancelar; Delete → Eliminar; Close → Cerrar; Open → Abrir
>    - Import → Importar; Export → Exportar; Compile → Compilar; Publish → Publicar; Translate → Traducir
>    - Validation → Validación; Issue → Problema; Warning → Advertencia; Error → Error
>    - File → Archivo; Folder → Carpeta; Browse → Examinar
>    - Add → Añadir; Remove → Quitar; Edit → Editar; Refresh → Actualizar
>    - Reset → Restablecer; Apply → Aplicar; Loading → Cargando
>    - Done → Hecho / Listo; Skip → Omitir; Next → Siguiente; Back → Atrás; Previous → Anterior
>    - Confirm → Confirmar; Copy → Copiar; Yes / No → Sí / No
>    - **Domain-specific** (this batch):
>      - Workshop item → elemento de Steam Workshop (the noun "item" of a Steam Workshop publication)
>      - Visibility (public/friends-only/private) → Visibilidad (público / solo amigos / privado)
>      - Tags → Etiquetas
>      - Description / Title → Descripción / Título
>      - Upload / Download → Subir / Descargar
>      - Bootstrap / First-run setup → Configuración inicial
>      - Detect / Detection → Detectar / Detección
>      - Game install path → Ruta de instalación del juego
>      - Continue / Next → Continuar / Siguiente
>      - Optional → Opcional; Required → Obligatorio
>      - Subscriber / Subscribers → Suscriptor / Suscriptores
>      - Rating / Score → Valoración / Puntuación
>
> 5. **Reference for tone**: read the corresponding French files. Also read `lib/i18n/es/common.i18n.json`, `lib/i18n/es/app.i18n.json`, `lib/i18n/es/widgets.i18n.json` to align with the established Spanish baseline.
> 6. **Do not** regenerate slang bindings, run any command, modify any other file, or commit. Just write the four JSON files.
>
> Report when done.

- [ ] **Step 2: Verify subagent output**

```bash
ls lib/i18n/es/import_export.i18n.json lib/i18n/es/pack_compilation.i18n.json lib/i18n/es/steam_publish.i18n.json lib/i18n/es/bootstrap.i18n.json
python -c "import json; [json.load(open(f'lib/i18n/es/{n}.i18n.json', encoding='utf-8')) for n in ['import_export','pack_compilation','steam_publish','bootstrap']]; print('OK')"
grep -E '\b(tú|vosotros|tu |tus |os |vuestro)\b' lib/i18n/es/import_export.i18n.json lib/i18n/es/pack_compilation.i18n.json lib/i18n/es/steam_publish.i18n.json lib/i18n/es/bootstrap.i18n.json || echo "OK: no informal forms"
grep -c "Steam Workshop" lib/i18n/es/steam_publish.i18n.json lib/i18n/en/steam_publish.i18n.json
```

Expected: files exist, valid JSON, no informal forms; the `Steam Workshop` count in the Spanish file equals the count in the English file (the proper noun was preserved verbatim every time).

- [ ] **Step 3: Run slang analyze**

```bash
dart run slang analyze
```

Expected: 4 namespaces still missing for `es` (Batch E only).

- [ ] **Step 4: Commit Batch D**

```bash
git add lib/i18n/es/import_export.i18n.json lib/i18n/es/pack_compilation.i18n.json lib/i18n/es/steam_publish.i18n.json lib/i18n/es/bootstrap.i18n.json
git commit -m "feat(i18n): translate Spanish strings for pipeline namespaces (import_export, pack_compilation, steam_publish, bootstrap)"
```

---

## Task 6: Batch E — Misc UI (settings, tooltips, activity, release_notes)

**Goal:** Translate the final group: settings + ambient UI.

**Files:**
- Create: `lib/i18n/es/settings.i18n.json`
- Create: `lib/i18n/es/tooltips.i18n.json`
- Create: `lib/i18n/es/activity.i18n.json`
- Create: `lib/i18n/es/release_notes.i18n.json`

- [ ] **Step 1: Dispatch translation subagent for Batch E**

Use `Agent` tool with `subagent_type: general-purpose`, `model: opus`. Prompt:

> You are translating UI strings from English to **Spanish (Castilian, Spain — `es-ES`)** for the TWMT Flutter desktop app.
>
> **Translate exactly these four files**:
> - `lib/i18n/en/settings.i18n.json` → `lib/i18n/es/settings.i18n.json`
> - `lib/i18n/en/tooltips.i18n.json` → `lib/i18n/es/tooltips.i18n.json`
> - `lib/i18n/en/activity.i18n.json` → `lib/i18n/es/activity.i18n.json`
> - `lib/i18n/en/release_notes.i18n.json` → `lib/i18n/es/release_notes.i18n.json`
>
> **Hard constraints (non-negotiable):**
>
> 1. **Castilian Spanish, formal `usted` register exclusively.** Never `tú`, `tu`, `vosotros`, `os`, `vuestro`.
> 2. **Identical structure**: same keys, same nesting, same `{placeholder}` names, same `one`/`other` plural maps. Output valid JSON, UTF-8, 2-space indent, trailing newline.
> 3. **Proper nouns are NEVER translated**: `Steam Workshop`, `Steam`, `Total War`, `Warhammer`, `Three Kingdoms`, `Empire`, `Napoleon`, `Shogun`, `Attila`, `Rome`, `Medieval`, `TWMT`, file extensions.
> 4. **Locked terminology**:
>    - Mod / Mods → Mod / Mods; Pack file → archivo pack; Glossary → Glosario; Translation Memory → Memoria de traducción
>    - Project → Proyecto; Settings → Ajustes; Search → Buscar
>    - Save → Guardar; Cancel → Cancelar; Delete → Eliminar; Close → Cerrar; Open → Abrir
>    - Import → Importar; Export → Exportar; Compile → Compilar; Publish → Publicar; Translate → Traducir
>    - Validation → Validación; Issue → Problema; Warning → Advertencia; Error → Error
>    - File → Archivo; Folder → Carpeta; Browse → Examinar
>    - Add → Añadir; Remove → Quitar; Edit → Editar; Refresh → Actualizar
>    - Reset → Restablecer; Apply → Aplicar; Loading → Cargando
>    - Done → Hecho / Listo; Skip → Omitir; Next → Siguiente; Back → Atrás; Previous → Anterior
>    - Confirm → Confirmar; Copy → Copiar; Yes / No → Sí / No
>    - **Domain-specific** (this batch):
>      - Theme → Tema; Light / Dark → Claro / Oscuro
>      - Language → Idioma; Display language → Idioma de la interfaz
>      - LLM provider / API key → Proveedor de LLM / Clave de API
>      - Model → Modelo; Temperature → Temperatura
>      - Logs → Registros; Activity → Actividad
>      - Notification → Notificación; Status → Estado
>      - Release notes / Changelog → Notas de la versión / Registro de cambios
>      - What's new → Novedades
>      - Version → Versión
>      - Storage / Cache → Almacenamiento / Caché
>      - About → Acerca de
>
> 5. **Reference for tone and length**: read the corresponding French files (`lib/i18n/fr/settings.i18n.json`, etc.). Also read `lib/i18n/es/common.i18n.json`, `lib/i18n/es/app.i18n.json`, `lib/i18n/es/widgets.i18n.json`. Tooltips should be concise (one short sentence each).
> 6. **Do not** regenerate slang bindings, run any command, modify any other file, or commit. Just write the four JSON files.
>
> Report when done.

- [ ] **Step 2: Verify subagent output**

```bash
ls lib/i18n/es/settings.i18n.json lib/i18n/es/tooltips.i18n.json lib/i18n/es/activity.i18n.json lib/i18n/es/release_notes.i18n.json
python -c "import json; [json.load(open(f'lib/i18n/es/{n}.i18n.json', encoding='utf-8')) for n in ['settings','tooltips','activity','release_notes']]; print('OK')"
grep -E '\b(tú|vosotros|tu |tus |os |vuestro)\b' lib/i18n/es/settings.i18n.json lib/i18n/es/tooltips.i18n.json lib/i18n/es/activity.i18n.json lib/i18n/es/release_notes.i18n.json || echo "OK: no informal forms"
```

Expected: 4 files exist, valid JSON, no informal forms.

- [ ] **Step 3: Commit Batch E**

```bash
git add lib/i18n/es/settings.i18n.json lib/i18n/es/tooltips.i18n.json lib/i18n/es/activity.i18n.json lib/i18n/es/release_notes.i18n.json
git commit -m "feat(i18n): translate Spanish strings for misc UI (settings, tooltips, activity, release_notes)"
```

---

## Task 7: Validate completeness (slang analyze + i18n tests)

**Goal:** All 20 namespaces are now translated. Confirm slang sees zero issues for `es`, and the structural test suite passes.

**Files:** none (validation only)

- [ ] **Step 1: Regenerate slang and Riverpod bindings**

```bash
dart run slang
dart run build_runner build --delete-conflicting-outputs
```

Expected: both succeed, no errors.

- [ ] **Step 2: Run slang analyze — expect zero issues**

```bash
dart run slang analyze
```

Expected output: no missing keys for `es`, no unused keys, no placeholder mismatches. The `_missing_translations.json` and `_unused_translations.json` reports should either be absent or contain empty maps.

If issues are reported:
- **Missing keys**: identify the file and key, edit the JSON in-place to add the translation.
- **Placeholder mismatch**: open the offending Spanish value, ensure `{name}`, `{count}`, etc. match the English source byte-for-byte.
- **Plural map mismatch**: the Spanish map must have `one` and `other` keys exactly like English.

Re-run until clean.

- [ ] **Step 3: Run the i18n structural tests**

```bash
flutter test test/i18n
```

Expected: `All tests passed!` — both `keys_completeness_test.dart` and `format_consistency_test.dart` pass.

If a test fails, the output names the offending key/file. Fix and re-run.

- [ ] **Step 4: Commit only if validation required JSON edits**

If Steps 2–3 required no edits, skip this step. Otherwise:

```bash
git add lib/i18n/es/
git commit -m "fix(i18n): correct Spanish keys flagged by slang analyze"
```

---

## Task 8: Smoke test in the running app

**Goal:** Confirm the locale picker exposes "Español", and the main flows render correctly without overflow or fallback to English.

**Files:** none (manual verification)

- [ ] **Step 1: Run the desktop app**

```bash
flutter run -d windows
```

Expected: app launches, no compile errors.

- [ ] **Step 2: Switch the locale to Español**

In the running app, open Settings (or the in-app locale picker) and select "Español". Confirm the flag shown is the Spanish flag (red/yellow/red).

- [ ] **Step 3: Walk the main flows**

Inspect each of:
1. App shell: window title, sidebar, navigation labels.
2. Home page: empty state, recent projects list, action buttons.
3. Projects list: search bar, project cards, filters.
4. Mods list: scan controls, mod cards.
5. One project's translation editor: filters sidebar, toolbar, validation panel, bulk actions.
6. Settings: every tab (Theme, Language, LLM, Storage, About).
7. Steam Workshop publish flow (open the wizard and walk through screens, even without publishing).

For each surface, verify:
- All visible text is in Spanish (no English fallback).
- No text overflow (Spanish strings ~20% longer than English; if a label clips, tighten the translation in the JSON file).
- `Steam Workshop`, `Total War`, and game titles appear verbatim (untranslated).
- No `{placeholder}` raw text on screen — they should be substituted with values.

- [ ] **Step 4: Note any regressions**

If any string is wrong, awkward, overflows, or breaks register (uses `tú` / `vosotros`), edit the relevant `lib/i18n/es/<namespace>.i18n.json` directly, regenerate (`dart run slang`), and hot-reload (`r` in the Flutter console).

- [ ] **Step 5: Final commit if smoke fixes were needed**

```bash
git add lib/i18n/es/
git commit -m "fix(i18n): tighten Spanish translations after smoke test"
```

If no smoke fixes were needed, skip this step.

- [ ] **Step 6: Verify the full series of commits**

```bash
git log --oneline main..HEAD
```

Expected: a clean series of `feat(i18n): …` commits — at minimum the 6 batch commits + the locale registration commit, plus any optional fix commits from Tasks 7 and 8.

---

## Done criteria

- 20 files exist under `lib/i18n/es/` with structure identical to `lib/i18n/en/`.
- `lib/i18n/app_locale_info.dart` lists `AppLocale.es` with `nativeName: 'Español'` and `flagAsset: 'assets/flags/es.png'`.
- `dart run slang analyze` reports zero missing keys, zero unused keys, zero placeholder mismatches for `es`.
- `flutter test test/i18n` passes.
- `flutter run -d windows` + manual locale switch to Español renders the main flows in Spanish without overflow or English fallback, with proper nouns intact.
- Git history shows a clean series of `feat(i18n): …` commits, one per batch.
