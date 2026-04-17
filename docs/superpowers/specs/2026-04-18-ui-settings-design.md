# Plan 5e — Settings retokenisation (design spec)

Date: 2026-04-18
Status: Draft, pending user review
Parent spec: `docs/superpowers/specs/2026-04-14-ui-redesign-design.md`
Follows: Plan 5d (cleanup) — merge commit `49357ff`, 2026-04-17

## 1. Goal

Retokenise the entire `lib/features/settings/` tree so every surface consumes `TwmtThemeTokens` via `context.tokens` instead of `Theme.of(context).colorScheme` / `FluentTheme` / hardcoded colours. Drop `FluentScaffold` at the screen root. Bring Settings to the same token-discipline baseline the rest of the UI reached in Plans 1–5d.

Non-goal: redesign or functional change. Layout and behaviour stay identical. Two targeted alignments are permitted where they eliminate duplication that would otherwise ship into every future Settings screen (see §3.2).

## 2. Scope

### 2.1 Included (28 files, ~6222 LOC under `lib/features/settings/`)

- 1 screen: `settings_screen.dart`
- 4 tab containers: `general_settings_tab.dart`, `folders_settings_tab.dart`, `llm_providers_tab.dart`, `appearance_settings_tab.dart` (last already tokenised; retoken pass verifies only)
- 6 `general/` sections: `backup_section.dart`, `game_installations_section.dart`, `language_preferences_section.dart`, `maintenance_section.dart`, `rpfm_section.dart`, `workshop_section.dart`
- 2 `general/` local primitives: `settings_action_button.dart` (deleted, → `SmallTextButton`), `settings_section_header.dart` (retoken in place)
- 3 accordion sections at widget root: `ignored_source_texts_section.dart`, `llm_custom_rules_section.dart`, `llm_provider_section.dart`
- 1 heavy list: `llm_models_list.dart` (401 LOC, retoken only)
- 3 datagrids + 3 data_sources: `language_settings_*`, `ignored_source_texts_*`, `llm_custom_rules_*`
- 5 dialogs: `add_custom_language_dialog.dart`, `ignored_source_text_editor_dialog.dart`, `llm_custom_rule_editor_dialog.dart`, `dialogs/backup_restore_confirmation_dialog.dart`, `model_management_dialog.dart` (470 LOC, retoken only)

### 2.2 Excluded (deferred, Plan 5f or later)

- Structural refactor of `llm_models_list.dart` or `model_management_dialog.dart`
- `FluentToast` retokenisation
- `SidebarUpdateChecker` overflow fix (Plan 2 follow-up, 14 pre-existing test failures masked)
- `appearance_settings_tab.dart` rework (already shipped in Plan 1)

## 3. Architecture

### 3.1 Screen structure (unchanged)

```
SettingsScreen
  ├─ header (icon + "Settings" title)
  ├─ SettingsTabBar (new primitive, §3.2)
  └─ TabBarView
       ├─ GeneralSettingsTab
       ├─ FoldersSettingsTab
       ├─ LlmProvidersTab
       └─ AppearanceSettingsTab (already tokenised)
```

No route changes. No navigation change. Tab index order preserved.

### 3.2 New primitives

Two primitives only (YAGNI). Both live in `lib/widgets/settings/`.

**`SettingsTabBar`** (replaces the 111-line privée `_FluentTabBar` + `_FluentTab` pair in `settings_screen.dart`).

API:
```dart
class SettingsTabBar extends StatelessWidget {
  const SettingsTabBar({required this.tabs});
  final List<SettingsTabItem> tabs;
}

class SettingsTabItem {
  const SettingsTabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
```

Token usage: `tokens.text` for active label, `tokens.textDim` for inactive, `tokens.panel2.withValues(alpha: 0.5)` for hover, `tokens.border` for the bottom separator (done by the parent, not the bar). No ripple, no Material indicator, identical visual result.

**`SettingsAccordionSection`** (replaces the duplicated scaffold across three callsites: `IgnoredSourceTextsSection`, `LlmCustomRulesSection`, and `LlmProviderSection`. The first two use `AnimatedCrossFade`; the third uses a raw `if (_isExpanded)` — the primitive unifies them on `AnimatedCrossFade`, so `LlmProviderSection` gains the animation as a side-effect).

API:
```dart
class SettingsAccordionSection extends StatefulWidget {
  const SettingsAccordionSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.activeCount,          // int? → StatusPill when > 0
    this.initiallyExpanded = false,
  });
}
```

Behaviour: clickable header row (icon + title/subtitle + optional count `StatusPill` + chevron), `AnimatedCrossFade` for expanded/collapsed body, tokenised border + radius. Consumers pass only the expanded content as `child`.

### 3.3 Primitives reused (no new work)

From Plan 5a (`lib/widgets/lists/`):
- `SmallTextButton`, `SmallIconButton` — replace `SettingsActionButton`, `OutlinedButton.icon`, `FilledButton.icon` at settings callsites
- `StatusPill` — badge "N active" inside accordion headers
- `buildTokenDataGridTheme` — wrap the 3 settings SfDataGrids
- `formatRelativeSince` / `formatAbsoluteDate` — backup section dates (already used? verify)

From Plan 5d (`lib/widgets/wizard/`):
- `TokenTextField`, `LabeledField`, `ReadonlyField` — form fields in Folders tab, LLM provider API key inputs, dialog editors

From `lib/widgets/common/`:
- `FluentSpinner` — kept (already neutral, used at 2 callsites)

## 4. Retokenisation rules (applied consistently)

1. Replace `Theme.of(context).colorScheme.X` with `context.tokens.Y`:
   - `primary` → `tokens.accent`
   - `onPrimary` → `tokens.accentFg` (or `tokens.bg` where the accent bg is textual)
   - `surface` → `tokens.panel`
   - `surfaceContainerHighest` → `tokens.panel2`
   - `onSurface` → `tokens.text`
   - `onSurface.withValues(alpha: 0.6)` → `tokens.textDim`
   - `onSurface.withValues(alpha: 0.3)`–`0.4` → `tokens.textFaint`
   - `outline` → `tokens.border`
   - `error` → `tokens.err`
2. Replace `Theme.of(context).textTheme.X` with tokens fonts:
   - `headlineMedium`/`headlineLarge` → `tokens.fontDisplay.copyWith(fontSize: …, color: tokens.text)`
   - `titleMedium` → `tokens.fontBody.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: tokens.text)`
   - `bodyMedium`/`bodyLarge` → `tokens.fontBody.copyWith(fontSize: 14, color: tokens.text)`
   - `bodySmall`/`labelSmall` → `tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim)`
3. Replace hardcoded hex colours (`0xFFE1E1E1`, `0xFFA19F9D`, etc. in `_FluentTabBar`) with token values.
4. Replace hardcoded `BorderRadius.circular(N)` with `tokens.radiusMd` / `tokens.radiusLg` where semantically consistent with the rest of the app.
5. Drop `FluentScaffold` wrapper from `settings_screen.dart` → `Scaffold(backgroundColor: tokens.bg)` (same pattern as Plans 5a/5d).
6. Keep `FluentToast.success/error(context, …)` calls as-is (deferred to Plan 5f).
7. Keep `FluentSpinner` — already neutral.
8. Italic resolution (`fontDisplayItalic ? FontStyle.italic : FontStyle.normal`) — keep inline at callsites for this plan; the token getter `tokens.fontDisplayStyle` deferred (noted in Plan 5d follow-ups).

## 5. Data flow (unchanged)

All Riverpod providers (`settingsProvider`, `generalSettingsProvider`, `llmProviderSettingsProvider`, `themeNameProvider`, `backupProviders`, `maintenanceProviders`, etc.) remain identical. No provider signature changes. No migration, no new persistent state.

### 5.1 Controller-sync fix (opportunistic)

`folders_settings_tab.dart:111` currently calls `_loadSettingsIntoControllers(settings)` inside `build`. Plan 5d flushed this anti-pattern at pack editor; same treatment here in Task 4 (Folders tab): move the controller sync to `ref.listenManual` inside `initState`, so `build` becomes pure.

Same check applied to `llm_providers_tab.dart:111-125` (initial key loading inside build): fold into `ref.listenManual` in initState.

## 6. Task breakdown (9 tasks, executed via superpowers:subagent-driven-development)

1. **Task 1 — `SettingsTabBar` primitive + `settings_screen.dart`** — new primitive file + drop `FluentScaffold` + wire `SettingsTabBar` + retoken header. Delete the private `_FluentTabBar`/`_FluentTab` pair.

2. **Task 2 — `SettingsAccordionSection` primitive + three callsite migrations** — new primitive file + migrate `IgnoredSourceTextsSection`, `LlmCustomRulesSection`, and `LlmProviderSection` to use it. Expect ~-500 LOC net.

3. **Task 3 — General tab + 6 sections + cleanup** — retoken `general_settings_tab.dart` + all 6 files under `general/` + delete `settings_action_button.dart` (migrate callsites to `SmallTextButton`) + retoken `settings_section_header.dart`.

4. **Task 4 — Folders tab + controller-sync fix** — retoken `folders_settings_tab.dart`, move controller sync to `initState` via `ref.listenManual` (§5.1). The 3 sub-sections (`game_installations`, `workshop`, `rpfm`) are already covered in Task 3 since they live under `general/`.

5. **Task 5 — LLM Providers tab + models list** — retoken `llm_providers_tab.dart` (including `_buildAdvancedSettings` inlined) and `llm_models_list.dart` (401 LOC, retoken only — no structural change per §2.2). Apply the controller-sync fix (§5.1) as in Task 4. Note: `llm_provider_section.dart` is already covered in Task 2 (accordion primitive migration).

6. **Task 6 — 3 datagrids + 3 data_sources** — `language_settings_datagrid.dart` + `language_settings_data_source.dart` + `ignored_source_texts_datagrid.dart` + `ignored_source_texts_data_source.dart` + `llm_custom_rules_datagrid.dart` + `llm_custom_rules_data_source.dart`. Each grid wrapped in `SfDataGridTheme(data: buildTokenDataGridTheme(tokens))`. Cell renderers retokenised inline.

7. **Task 7 — 5 dialogs** — retoken `add_custom_language_dialog.dart`, `ignored_source_text_editor_dialog.dart`, `llm_custom_rule_editor_dialog.dart`, `dialogs/backup_restore_confirmation_dialog.dart`, `model_management_dialog.dart`. Convert `AlertDialog` → `Dialog` (Plan 5d convention) where the body has ≥2 fields or custom content. Reuse `TokenTextField` / `LabeledField` where fields exist.

8. **Task 8 — Goldens** — 8 tests = 4 tabs × 2 themes (Atelier + Forge). Re-use the pattern from `test/features/home/home_screen_golden_test.dart`. Stable epoch via existing `fixedClock` helper. Tab `appearance` covered for completeness even though already tokenised.

9. **Task 9 — Analyze clean + final sweep** — run `flutter analyze`, fix any new warnings (must be 0 introduced), prune unused `fluent_widgets.dart` imports, verify tests **1331/14** (+8 nets vs baseline 1323/14). Write `feat:`/`refactor:` commit split per task discipline.

## 7. Golden coverage

| Screen | Atelier | Forge |
|---|---|---|
| General tab | ✓ | ✓ |
| Folders tab | ✓ | ✓ |
| LLM Providers tab | ✓ | ✓ |
| Appearance tab | ✓ | ✓ |

Total = 8 goldens. No dialog goldens, no section-isolated goldens (dialogs covered by their callsite, sections covered by composition inside tab goldens).

## 8. Tests target

- **Baseline (main at 49357ff)**: 1323 / 14
- **After Plan 5e**: ~1331 / 14
  - +8 nets: 8 new goldens in Task 8
  - 14 pre-existing `SidebarUpdateChecker` overflow failures carried over (Plan 2 follow-up, unchanged)
  - 0 new fonctionnel tests — retoken is behaviour-preserving

## 9. Risks & pitfalls

- **`FluentScaffold` drop** — pattern proven in Plans 5a/5b/5c/5d, `Scaffold(backgroundColor: tokens.bg)` is the fix. No routing change.
- **`SfDataGridTheme` wrap** — Plan 4 gotcha: don't nest `Expanded(ListView)` inside. Not applicable here (all 3 datagrids are inside sections, finite heights already handled). Verify during Task 6.
- **Controller sync in `build()`** — present in `folders_settings_tab` and `llm_providers_tab`. §5.1 prescribes the fix. Plan 5d's `ref.listenManual` pattern applies verbatim.
- **`model_management_dialog.dart` (470 LOC, 16 `Theme.of`)** — big file, retoken only, no structural refactor. High likelihood of missed spots: Task 7 reviewer must grep for residual `Theme.of(context).colorScheme` after the pass.
- **Goldens & fonts** — settings tabs may have hover states in the tab bar. Goldens must be captured in the non-hover rest state. Use the canonical "render once, no pump" helper.
- **Windows file lock on worktree teardown** — Plan 3 known issue, mitigate by closing IDE/build_runner before `git worktree remove`.

## 10. Acceptance criteria

1. Zero `Theme.of(context).colorScheme` references in `lib/features/settings/`.
2. Zero `FluentScaffold` usage in `lib/features/settings/`.
3. Zero hardcoded colour literals (hex) in `lib/features/settings/` except: (a) Atelier/Forge token definitions already there, (b) `appearance_settings_tab.dart` preview colours (those come from the palette itself — kept).
4. `SettingsAccordionSection` used at exactly 3 callsites (`IgnoredSourceTextsSection`, `LlmCustomRulesSection`, `LlmProviderSection`), each ~60-120 LOC after migration.
5. `settings_action_button.dart` deleted; zero callsites remain.
6. 8 goldens passing on both Atelier and Forge.
7. `flutter analyze` clean (0 warnings introduced).
8. Tests: ~1331 / 14 (baseline 1323 / 14, +8 nets, 14 pre-existing failures preserved).
9. Controller sync in `build()` removed from Folders tab + LLM Providers tab.

## 11. Out of scope for Plan 5e (tracked for 5f)

- Structural rework of `llm_models_list.dart` and `model_management_dialog.dart`.
- `FluentToast` retokenisation (shared across whole app, scope too large here).
- `SidebarUpdateChecker` overflow (Plan 2 follow-up).
- `tokens.fontDisplayStyle` getter (Plan 5d deferred item).
- `LabeledField` style parameter extension (Plan 5d deferred item).
- `TokenDropdown` primitive (Plan 5d deferred; may be needed in Task 5 for rate-limit slider context — if so, keep inline, don't create primitive mid-plan).
