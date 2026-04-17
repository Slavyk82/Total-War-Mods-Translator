# Plan 5e · Settings retokenisation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retokeniser l'intégralité de `lib/features/settings/` — 28 fichiers, ~6222 LOC, ~129 occurrences de `Theme.of(context).colorScheme` / `FluentTheme` / hex hardcodés — en consommant `TwmtThemeTokens` via `context.tokens` partout. Drop `FluentScaffold` au niveau screen. Extraire 2 primitives (`SettingsTabBar`, `SettingsAccordionSection`) qui dédupliquent le scaffolding répété. Pas de changement fonctionnel ni de layout.

**Architecture:** 2 nouveaux widgets publics dans `lib/widgets/settings/`. Les 3 sections accordéon (`IgnoredSourceTexts`, `LlmCustomRules`, `LlmProvider`) migrent vers `SettingsAccordionSection`, éliminant ~500 LOC dupliquées. Le screen root drop `FluentScaffold` → `Scaffold(backgroundColor: tokens.bg)`. Les 3 datagrids Syncfusion sont wrappées dans `SfDataGridTheme(data: buildTokenDataGridTheme(tokens))` (primitive Plan 5a). Les 5 dialogs convertissent `AlertDialog` → `Dialog` (convention Plan 5d) quand le corps est riche. Fix opportuniste : controller-sync in `build()` → `ref.listenManual` dans `initState` (Folders tab + LLM Providers tab).

**Tech Stack:** Flutter Desktop Windows · Riverpod 3 · GoRouter · Syncfusion DataGrid · `flutter_test` goldens.

**Spec:** [`docs/superpowers/specs/2026-04-18-ui-settings-design.md`](../specs/2026-04-18-ui-settings-design.md)

**Predecessors (shipped on main):** Plans 1, 2, 3, 4, 5a, 5b, 5c, 5d.

---

## File Structure

### New primitives (Task 1, Task 2)

- `lib/widgets/settings/settings_tab_bar.dart` — tokenised tab bar (replaces privées `_FluentTabBar`/`_FluentTab`)
- `lib/widgets/settings/settings_accordion_section.dart` — clickable header + `AnimatedCrossFade` body + optional `StatusPill` count

### Test files (new)

- `test/widgets/settings/settings_tab_bar_test.dart`
- `test/widgets/settings/settings_accordion_section_test.dart`
- `test/features/settings/screens/settings_screen_general_golden_test.dart` (2 goldens)
- `test/features/settings/screens/settings_screen_folders_golden_test.dart` (2 goldens)
- `test/features/settings/screens/settings_screen_llm_providers_golden_test.dart` (2 goldens)
- `test/features/settings/screens/settings_screen_appearance_golden_test.dart` (2 goldens)

### Modified files (by task)

**Task 1 — Tab bar primitive + screen root**
- `lib/features/settings/screens/settings_screen.dart` — drop `FluentScaffold`, use `SettingsTabBar`, delete 78 LOC de tab-bar privée

**Task 2 — Accordion primitive + 3 migrations**
- `lib/features/settings/widgets/ignored_source_texts_section.dart` (279 → ~90)
- `lib/features/settings/widgets/llm_custom_rules_section.dart` (229 → ~60)
- `lib/features/settings/widgets/llm_provider_section.dart` (220 → ~120)

**Task 3 — General tab + 6 general/ sections + cleanup**
- `lib/features/settings/widgets/general_settings_tab.dart`
- `lib/features/settings/widgets/general/backup_section.dart`
- `lib/features/settings/widgets/general/game_installations_section.dart`
- `lib/features/settings/widgets/general/language_preferences_section.dart`
- `lib/features/settings/widgets/general/maintenance_section.dart`
- `lib/features/settings/widgets/general/rpfm_section.dart`
- `lib/features/settings/widgets/general/workshop_section.dart`
- `lib/features/settings/widgets/general/settings_section_header.dart`
- `lib/features/settings/widgets/general/settings_action_button.dart` — **supprimé** (callsites → `SmallTextButton`)

**Task 4 — Folders tab + controller-sync fix**
- `lib/features/settings/widgets/folders_settings_tab.dart` — retoken + move `_loadSettingsIntoControllers` de `build()` vers `ref.listenManual` dans `initState`

**Task 5 — LLM Providers tab + models list**
- `lib/features/settings/widgets/llm_providers_tab.dart` — retoken + inline `_buildAdvancedSettings` + même fix controller-sync
- `lib/features/settings/widgets/llm_models_list.dart` — retoken only (401 LOC)

**Task 6 — 3 datagrids + 3 data_sources**
- `lib/features/settings/widgets/language_settings_datagrid.dart`
- `lib/features/settings/widgets/language_settings_data_source.dart`
- `lib/features/settings/widgets/ignored_source_texts_datagrid.dart`
- `lib/features/settings/widgets/ignored_source_texts_data_source.dart`
- `lib/features/settings/widgets/llm_custom_rules_datagrid.dart`
- `lib/features/settings/widgets/llm_custom_rules_data_source.dart`

**Task 7 — 5 dialogs**
- `lib/features/settings/widgets/add_custom_language_dialog.dart`
- `lib/features/settings/widgets/ignored_source_text_editor_dialog.dart`
- `lib/features/settings/widgets/llm_custom_rule_editor_dialog.dart`
- `lib/features/settings/widgets/dialogs/backup_restore_confirmation_dialog.dart`
- `lib/features/settings/widgets/model_management_dialog.dart` (470 LOC, retoken only)

**Task 8 — Goldens (4 tabs × 2 thèmes = 8 fichiers PNG + 4 `.dart` tests)**

**Task 9 — Analyze & final sweep**
- `pubspec.yaml` — vérifier si des imports `fluent/fluent_widgets.dart` deviennent inutiles
- Tout fichier touché si `flutter analyze` remonte un lint

### Goldens à regénérer (existants)

Aucun. Les tabs Settings n'ont pas de golden existant (appearance tab n'en avait pas). Les 8 goldens Task 8 sont tous nouveaux.

---

## Token mapping table (référence Task 3-7)

Utilise cette table pour convertir **chaque** occurrence :

| Avant | Après |
|---|---|
| `Theme.of(context).colorScheme.primary` | `context.tokens.accent` |
| `Theme.of(context).colorScheme.onPrimary` | `context.tokens.accentFg` |
| `Theme.of(context).colorScheme.surface` | `context.tokens.panel` |
| `Theme.of(context).colorScheme.surfaceContainerHighest` | `context.tokens.panel2` |
| `Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)` | `context.tokens.panel2.withValues(alpha: 0.5)` |
| `Theme.of(context).colorScheme.onSurface` | `context.tokens.text` |
| `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)` | `context.tokens.text` |
| `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)` | `context.tokens.textDim` |
| `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)` | `context.tokens.textDim` |
| `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)` | `context.tokens.textFaint` |
| `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)` | `context.tokens.textFaint` |
| `Theme.of(context).colorScheme.outline` | `context.tokens.border` |
| `Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)` | `context.tokens.border` |
| `Theme.of(context).colorScheme.error` | `context.tokens.err` |
| `Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)` | `context.tokens.accentBg` |
| `Theme.of(context).textTheme.headlineLarge` | `tokens.fontDisplay.copyWith(fontSize: 24, color: tokens.text, fontStyle: tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal)` |
| `Theme.of(context).textTheme.headlineMedium` | `tokens.fontDisplay.copyWith(fontSize: 20, color: tokens.text, fontStyle: tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal)` |
| `Theme.of(context).textTheme.titleMedium` | `tokens.fontBody.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: tokens.text)` |
| `Theme.of(context).textTheme.bodyLarge` | `tokens.fontBody.copyWith(fontSize: 14, color: tokens.text)` |
| `Theme.of(context).textTheme.bodyMedium` | `tokens.fontBody.copyWith(fontSize: 13, color: tokens.text)` |
| `Theme.of(context).textTheme.bodySmall` | `tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim)` |
| `Theme.of(context).textTheme.labelSmall` | `tokens.fontBody.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: tokens.textDim)` |
| `Theme.of(context).dividerColor` | `context.tokens.border` |
| `BorderRadius.circular(4)` | `BorderRadius.circular(tokens.radiusSm)` |
| `BorderRadius.circular(8)` | `BorderRadius.circular(tokens.radiusMd)` |
| `BorderRadius.circular(12)` | `BorderRadius.circular(tokens.radiusLg)` |
| `Color(0xFFE1E1E1)` (active label, dark) | `tokens.text` |
| `Color(0xFFA19F9D)` (unselected label, dark) | `tokens.textDim` |
| `Color(0xFF323130)` (light active) | `tokens.text` |
| `Color(0xFF605E5C)` (light unselected) | `tokens.textDim` |

Ajouter en haut de chaque fichier modifié :

```dart
import 'package:twmt/theme/twmt_theme_tokens.dart';
```

Retirer les imports devenus inutiles : `fluent/fluent_widgets.dart` si `FluentToast` n'est plus utilisé.

---

## Worktree setup (pre-Task 1)

- [ ] **Create worktree & branch**

```bash
cd /e/Total-War-Mods-Translator
git worktree add .worktrees/ui-settings -b feat/ui-settings main
cd .worktrees/ui-settings
```

- [ ] **Copy `windows/` + regen generated code**

```bash
cp -r ../../windows ./
C:/src/flutter/bin/flutter pub get
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Baseline verify**

```bash
C:/src/flutter/bin/flutter test
```

Expected: 1323 passing / 14 pre-existing failures (SidebarUpdateChecker overflows, per Plan 5d memory).

---

## Task 1 · `SettingsTabBar` primitive + `settings_screen.dart` retoken

**Files:**
- Create: `lib/widgets/settings/settings_tab_bar.dart`
- Test: `test/widgets/settings/settings_tab_bar_test.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`

### 1.1 `SettingsTabBar`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/settings/settings_tab_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_tab_bar.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: DefaultTabController(
            length: 2,
            child: Column(
              children: [child, const Expanded(child: SizedBox())],
            ),
          ),
        ),
      );

  testWidgets('renders one tab per item with label + icon', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
      SettingsTabItem(icon: FluentIcons.folder_24_regular, label: 'Folders'),
    ])));
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.byIcon(FluentIcons.settings_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.folder_24_regular), findsOneWidget);
  });

  testWidgets('active tab label uses tokens.text', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
    ])));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final label = t.widget<Text>(find.text('General'));
    // Active tab color comes from TabBar.labelColor → theme.tokens.text
    expect(label.style?.color ?? tokens.text, isNotNull);
  });

  testWidgets('tab bar is horizontally scrollable', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
      SettingsTabItem(icon: FluentIcons.folder_24_regular, label: 'Folders'),
    ])));
    final bar = t.widget<TabBar>(find.byType(TabBar));
    expect(bar.isScrollable, isTrue);
  });
}
```

- [ ] **Step 2 · Run test (red)**

```bash
C:/src/flutter/bin/flutter test test/widgets/settings/settings_tab_bar_test.dart
```

Expected: FAIL with "Target of URI doesn't exist: 'package:twmt/widgets/settings/settings_tab_bar.dart'".

- [ ] **Step 3 · Implement `SettingsTabBar`**

Create `lib/widgets/settings/settings_tab_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Descriptor for a tab inside [SettingsTabBar].
class SettingsTabItem {
  const SettingsTabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Tokenised tab bar used by Settings screen.
///
/// Replaces the private `_FluentTabBar`/`_FluentTab` pair that used to live
/// inside `settings_screen.dart` with hardcoded colour literals. Active label
/// uses `tokens.text`, inactive uses `tokens.textDim`, hover background
/// applies `tokens.panel2.withValues(alpha: 0.5)`.
class SettingsTabBar extends StatelessWidget {
  const SettingsTabBar({super.key, required this.tabs});

  final List<SettingsTabItem> tabs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabBar(
      isScrollable: true,
      labelPadding: EdgeInsets.zero,
      indicator: const BoxDecoration(),
      dividerColor: Colors.transparent,
      labelColor: tokens.text,
      unselectedLabelColor: tokens.textDim,
      tabs: [
        for (final item in tabs) _SettingsTab(icon: item.icon, label: item.label),
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tab(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? tokens.panel2.withValues(alpha: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16),
              const SizedBox(width: 8),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4 · Run test (green)**

```bash
C:/src/flutter/bin/flutter test test/widgets/settings/settings_tab_bar_test.dart
```

Expected: 3/3 PASS.

- [ ] **Step 5 · Commit**

```bash
git add lib/widgets/settings/settings_tab_bar.dart test/widgets/settings/settings_tab_bar_test.dart
git commit -m "feat: add SettingsTabBar primitive"
```

### 1.2 Retoken `settings_screen.dart`

- [ ] **Step 6 · Rewrite `settings_screen.dart`**

Replace the entire file `lib/features/settings/screens/settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_tab_bar.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/folders_settings_tab.dart';
import '../widgets/llm_providers_tab.dart';
import '../widgets/appearance_settings_tab.dart';

/// Settings screen with a tabbed interface for General / Folders / LLM Providers / Appearance.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.settings_24_regular,
                    size: 32,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 24,
                      color: tokens.text,
                      fontStyle: tokens.fontDisplayItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: const SettingsTabBar(tabs: [
                SettingsTabItem(
                  icon: FluentIcons.settings_24_regular,
                  label: 'General',
                ),
                SettingsTabItem(
                  icon: FluentIcons.folder_24_regular,
                  label: 'Folders',
                ),
                SettingsTabItem(
                  icon: FluentIcons.brain_circuit_24_regular,
                  label: 'LLM Providers',
                ),
                SettingsTabItem(
                  icon: FluentIcons.color_24_regular,
                  label: 'Appearance',
                ),
              ]),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  GeneralSettingsTab(),
                  FoldersSettingsTab(),
                  LlmProvidersTab(),
                  AppearanceSettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7 · Run test-suite partial**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/screens/settings_screen.dart
```

Expected: 0 issues.

- [ ] **Step 8 · Commit**

```bash
git add lib/features/settings/screens/settings_screen.dart
git commit -m "refactor: drop FluentScaffold + use SettingsTabBar in settings screen"
```

---

## Task 2 · `SettingsAccordionSection` + 3 callsite migrations

**Files:**
- Create: `lib/widgets/settings/settings_accordion_section.dart`
- Test: `test/widgets/settings/settings_accordion_section_test.dart`
- Modify: `lib/features/settings/widgets/ignored_source_texts_section.dart`
- Modify: `lib/features/settings/widgets/llm_custom_rules_section.dart`
- Modify: `lib/features/settings/widgets/llm_provider_section.dart`

### 2.1 `SettingsAccordionSection`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/settings/settings_accordion_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders header with title + subtitle collapsed by default', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'My section',
      subtitle: 'Some description',
      child: Text('expanded-content'),
    )));
    expect(find.text('My section'), findsOneWidget);
    expect(find.text('Some description'), findsOneWidget);
    expect(find.text('expanded-content'), findsNothing);
  });

  testWidgets('tapping header expands and shows child', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'Title',
      subtitle: 'Sub',
      child: Text('expanded-content'),
    )));
    await t.tap(find.text('Title'));
    await t.pumpAndSettle();
    expect(find.text('expanded-content'), findsOneWidget);
  });

  testWidgets('shows StatusPill when activeCount > 0', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      activeCount: 3,
      child: SizedBox.shrink(),
    )));
    expect(find.text('3 active'), findsOneWidget);
  });

  testWidgets('hides StatusPill when activeCount is null or 0', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      activeCount: 0,
      child: SizedBox.shrink(),
    )));
    expect(find.textContaining('active'), findsNothing);
  });

  testWidgets('initiallyExpanded=true renders child on first frame', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      initiallyExpanded: true,
      child: Text('up-front'),
    )));
    expect(find.text('up-front'), findsOneWidget);
  });
}
```

- [ ] **Step 2 · Run test (red)**

```bash
C:/src/flutter/bin/flutter test test/widgets/settings/settings_accordion_section_test.dart
```

Expected: FAIL "Target of URI doesn't exist".

- [ ] **Step 3 · Implement `SettingsAccordionSection`**

Create `lib/widgets/settings/settings_accordion_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Reusable accordion section used by Settings (Ignored Source Texts,
/// LLM Custom Rules, LLM Provider) — clickable header + animated body.
///
/// Consolidates ~500 LOC of duplicated scaffolding that previously lived in
/// three sibling widgets. The three callsites differ only in icon / title /
/// subtitle / optional active count / body content.
class SettingsAccordionSection extends StatefulWidget {
  const SettingsAccordionSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.activeCount,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final int? activeCount;
  final bool initiallyExpanded;

  @override
  State<SettingsAccordionSection> createState() =>
      _SettingsAccordionSectionState();
}

class _SettingsAccordionSectionState extends State<SettingsAccordionSection> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        children: [
          _buildHeader(tokens),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.all(16),
              child: widget.child,
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TwmtThemeTokens tokens) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isExpanded ? tokens.panel2 : Colors.transparent,
            borderRadius: _isExpanded
                ? BorderRadius.vertical(top: Radius.circular(tokens.radiusMd))
                : BorderRadius.circular(tokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              if ((widget.activeCount ?? 0) > 0) ...[
                StatusPill(
                  label: '${widget.activeCount} active',
                  tone: StatusTone.accent,
                ),
                const SizedBox(width: 12),
              ],
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 20,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> **Note:** `StatusPill` accepts a `tone` enum. Verify the actual enum name by reading `lib/widgets/lists/status_pill.dart` first; if the enum is called `StatusPillTone` or different value names are used, adjust the import and the call accordingly. Fall back to a plain tokenised `Container` with `tokens.accentBg` + `tokens.accent` text if `StatusPill` API doesn't match.

- [ ] **Step 4 · Run test (green)**

```bash
C:/src/flutter/bin/flutter test test/widgets/settings/settings_accordion_section_test.dart
```

Expected: 5/5 PASS.

- [ ] **Step 5 · Commit**

```bash
git add lib/widgets/settings/settings_accordion_section.dart test/widgets/settings/settings_accordion_section_test.dart
git commit -m "feat: add SettingsAccordionSection primitive"
```

### 2.2 Migrate `ignored_source_texts_section.dart`

- [ ] **Step 6 · Rewrite section with primitive**

Replace the entire file `lib/features/settings/widgets/ignored_source_texts_section.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/ignored_source_texts_providers.dart';
import 'ignored_source_texts_datagrid.dart';
import 'ignored_source_text_editor_dialog.dart';

/// Expandable section for managing ignored source texts.
///
/// Uses the shared [SettingsAccordionSection] scaffold; only the body
/// is specific (info banner + buttons + DataGrid).
class IgnoredSourceTextsSection extends ConsumerWidget {
  const IgnoredSourceTextsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledCountAsync = ref.watch(enabledIgnoredTextsCountProvider);
    final tokens = context.tokens;

    return SettingsAccordionSection(
      icon: FluentIcons.text_bullet_list_square_24_regular,
      title: 'Ignored Source Texts',
      subtitle: 'Skip specific source texts during translation',
      activeCount: enabledCountAsync.whenOrNull(data: (c) => c > 0 ? c : null),
      child: _IgnoredSourceTextsBody(
        tokens: tokens,
        onAdd: () => _addText(context, ref),
        onReset: () => _resetToDefaults(context, ref),
      ),
    );
  }

  Future<void> _addText(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const IgnoredSourceTextEditorDialog(),
    );
    if (result == null || result.isEmpty) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(ignoredSourceTextsProvider.notifier).addText(result);
    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, 'Text added successfully');
    } else {
      FluentToast.error(context, error ?? 'Failed to add text');
    }
  }

  Future<void> _resetToDefaults(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ResetConfirmDialog(),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(ignoredSourceTextsProvider.notifier).resetToDefaults();
    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, 'Reset to defaults successfully');
    } else {
      FluentToast.error(context, error ?? 'Failed to reset to defaults');
    }
  }
}

class _IgnoredSourceTextsBody extends StatelessWidget {
  const _IgnoredSourceTextsBody({
    required this.tokens,
    required this.onAdd,
    required this.onReset,
  });

  final TwmtThemeTokens tokens;
  final VoidCallback onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.info_24_regular, size: 18, color: tokens.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Source texts matching these values will be excluded from translation. '
                  'Note: Fully bracketed texts like [PLACEHOLDER] are automatically skipped. '
                  'Use this list for custom patterns specific to your mods.',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message: TooltipStrings.settingsResetIgnoredDefaults,
              waitDuration: const Duration(milliseconds: 500),
              child: SmallTextButton(
                label: 'Reset to Defaults',
                icon: FluentIcons.arrow_reset_24_regular,
                onPressed: onReset,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: TooltipStrings.settingsAddIgnoredText,
              waitDuration: const Duration(milliseconds: 500),
              child: SmallTextButton(
                label: 'Add Text',
                icon: FluentIcons.add_24_regular,
                onPressed: onAdd,
                emphasis: SmallTextButtonEmphasis.filled,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const IgnoredSourceTextsDataGrid(),
      ],
    );
  }
}

class _ResetConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AlertDialog(
      backgroundColor: tokens.panel,
      title: Text(
        'Reset to Defaults',
        style: tokens.fontDisplay.copyWith(
          fontSize: 18,
          color: tokens.text,
          fontStyle: tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      content: Text(
        'This will delete all current ignored texts and restore the default values:\n\n'
        '• placeholder\n'
        '• dummy\n\n'
        'Note: Texts fully enclosed in brackets like [placeholder] are always filtered automatically.\n\n'
        'Are you sure you want to continue?',
        style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        SmallTextButton(
          label: 'Reset',
          emphasis: SmallTextButtonEmphasis.filled,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
```

> **Verify `SmallTextButton` API:** Read `lib/widgets/lists/small_text_button.dart` to confirm the `emphasis: SmallTextButtonEmphasis.filled` param name and enum values. If the primitive uses a different API (e.g. `variant`, `style`, or a bool `filled:`), adapt the calls. Same applies to every other `SmallTextButton` call throughout Tasks 2-7.

- [ ] **Step 7 · Run tests**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/ignored_source_texts_section.dart
C:/src/flutter/bin/flutter test
```

Expected: 0 analyze issues. Test suite still at 1323/14 (no new tests yet).

- [ ] **Step 8 · Commit**

```bash
git add lib/features/settings/widgets/ignored_source_texts_section.dart
git commit -m "refactor: migrate ignored_source_texts_section to SettingsAccordionSection"
```

### 2.3 Migrate `llm_custom_rules_section.dart`

- [ ] **Step 9 · Rewrite section with primitive**

Replace the entire file `lib/features/settings/widgets/llm_custom_rules_section.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/llm_custom_rules_providers.dart';
import 'llm_custom_rules_datagrid.dart';
import 'llm_custom_rule_editor_dialog.dart';

/// Expandable section for managing LLM custom translation rules.
class LlmCustomRulesSection extends ConsumerWidget {
  const LlmCustomRulesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledCountAsync = ref.watch(enabledRulesCountProvider);
    final tokens = context.tokens;

    return SettingsAccordionSection(
      icon: FluentIcons.text_bullet_list_ltr_24_regular,
      title: 'Custom Translation Rules',
      subtitle: 'Add custom instructions to translation prompts',
      activeCount: enabledCountAsync.whenOrNull(data: (c) => c > 0 ? c : null),
      child: _LlmCustomRulesBody(
        tokens: tokens,
        onAdd: () => _addRule(context, ref),
      ),
    );
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const LlmCustomRuleEditorDialog(),
    );
    if (result == null || result.isEmpty) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(llmCustomRulesProvider.notifier).addRule(result);
    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, 'Rule added successfully');
    } else {
      FluentToast.error(context, error ?? 'Failed to add rule');
    }
  }
}

class _LlmCustomRulesBody extends StatelessWidget {
  const _LlmCustomRulesBody({required this.tokens, required this.onAdd});

  final TwmtThemeTokens tokens;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.info_24_regular, size: 18, color: tokens.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Custom rules are appended to every translation prompt sent to the LLM. '
                  'Use this to define global instructions, terminology guidelines, '
                  'or translation preferences that apply to all projects.',
                  style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.text),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message: TooltipStrings.settingsAddRule,
              waitDuration: const Duration(milliseconds: 500),
              child: SmallTextButton(
                label: 'Add Rule',
                icon: FluentIcons.add_24_regular,
                onPressed: onAdd,
                emphasis: SmallTextButtonEmphasis.filled,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const LlmCustomRulesDataGrid(),
      ],
    );
  }
}
```

- [ ] **Step 10 · Commit**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/llm_custom_rules_section.dart
git add lib/features/settings/widgets/llm_custom_rules_section.dart
git commit -m "refactor: migrate llm_custom_rules_section to SettingsAccordionSection"
```

### 2.4 Migrate `llm_provider_section.dart`

- [ ] **Step 11 · Read current implementation**

```bash
cat lib/features/settings/widgets/llm_provider_section.dart
```

Expected structure: consumer stateful with `_isExpanded`, header row (icon + provider name + masked API key + chevron), body with field + models list + save button.

- [ ] **Step 12 · Rewrite using primitive**

Apply the same migration pattern as 2.2 / 2.3:
1. Replace the top-level accordion scaffold (`Container` + `_buildHeader` + raw `if (_isExpanded)`) with `SettingsAccordionSection(icon:, title:, subtitle:, child: _body)`.
2. Move the body content into a private `_LlmProviderBody` widget.
3. Replace every `Theme.of(context).colorScheme.X` in the body with `context.tokens.Y` per the Token mapping table.
4. Replace inline `FilledButton`/`OutlinedButton.icon` with `SmallTextButton` (setting `emphasis: SmallTextButtonEmphasis.filled` for the "Save" action).
5. Replace `Theme.of(context).textTheme.X` with the corresponding `tokens.fontBody.copyWith(...)` per the table.

Do NOT preserve the previous masked-API-key display in the header; it was informational only. Keep it in the body instead (or drop it — align with the data already in the body's TextField).

> **Verification checkpoint:** After rewriting, the file should drop from 220 LOC to ~100-130 LOC. `grep -n "Theme.of(context)" lib/features/settings/widgets/llm_provider_section.dart` must return 0 matches.

- [ ] **Step 13 · Commit**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/llm_provider_section.dart
git add lib/features/settings/widgets/llm_provider_section.dart
git commit -m "refactor: migrate llm_provider_section to SettingsAccordionSection"
```

---

## Task 3 · General tab + 6 `general/` sections + delete `settings_action_button.dart`

**Files:**
- Modify: `lib/features/settings/widgets/general_settings_tab.dart` (42 LOC)
- Modify: `lib/features/settings/widgets/general/backup_section.dart` (384 LOC, 16 Theme.of)
- Modify: `lib/features/settings/widgets/general/game_installations_section.dart` (228 LOC)
- Modify: `lib/features/settings/widgets/general/language_preferences_section.dart` (137 LOC, 7 Theme.of)
- Modify: `lib/features/settings/widgets/general/maintenance_section.dart` (258 LOC)
- Modify: `lib/features/settings/widgets/general/rpfm_section.dart` (269 LOC)
- Modify: `lib/features/settings/widgets/general/workshop_section.dart` (162 LOC)
- Modify: `lib/features/settings/widgets/general/settings_section_header.dart` (37 LOC)
- Delete: `lib/features/settings/widgets/general/settings_action_button.dart` (124 LOC)

### 3.1 Audit callsites of `SettingsActionButton`

- [ ] **Step 1 · Find callsites**

```bash
grep -rn "SettingsActionButton" lib/ test/
```

Expected: a handful of call sites inside `general/` sections. Record the list.

### 3.2 Retoken `general_settings_tab.dart`

- [ ] **Step 2 · Apply retoken**

Open `lib/features/settings/widgets/general_settings_tab.dart` and:
1. Add `import 'package:twmt/theme/twmt_theme_tokens.dart';`.
2. In the `error` branch of `settingsAsync.when`, replace the implicit `Text('Error: $error')` colour with `tokens.err` + `tokens.fontBody`.
3. No other change (file already uses only `FluentSpinner` and section widgets).

Full replacement:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../widgets/common/fluent_spinner.dart';
import '../providers/settings_providers.dart';
import 'general/backup_section.dart';
import 'general/language_preferences_section.dart';
import 'general/maintenance_section.dart';
import 'ignored_source_texts_section.dart';

class GeneralSettingsTab extends ConsumerWidget {
  const GeneralSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(generalSettingsProvider);
    final tokens = context.tokens;

    return settingsAsync.when(
      loading: () => const Center(child: FluentSpinner()),
      error: (error, stack) => Center(
        child: Text(
          'Error loading settings: $error',
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.err),
        ),
      ),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            LanguagePreferencesSection(),
            SizedBox(height: 32),
            IgnoredSourceTextsSection(),
            SizedBox(height: 32),
            MaintenanceSection(),
            SizedBox(height: 32),
            BackupSection(),
          ],
        );
      },
    );
  }
}
```

### 3.3 Retoken each `general/*.dart` section

For **every** file in the following list (7 files), apply this uniform pass:

**Files to touch (in this order):**
1. `lib/features/settings/widgets/general/settings_section_header.dart`
2. `lib/features/settings/widgets/general/language_preferences_section.dart`
3. `lib/features/settings/widgets/general/maintenance_section.dart`
4. `lib/features/settings/widgets/general/backup_section.dart`
5. `lib/features/settings/widgets/general/game_installations_section.dart`
6. `lib/features/settings/widgets/general/workshop_section.dart`
7. `lib/features/settings/widgets/general/rpfm_section.dart`

**Uniform pass (steps 3-9, repeated per file):**

- [ ] **Step N · Read the file, then apply the token mapping table**

For each file:
1. Add `import 'package:twmt/theme/twmt_theme_tokens.dart';` at the top.
2. In the `build` method (or each `_build*` helper) add `final tokens = context.tokens;` as the first statement.
3. Apply **every** mapping from the "Token mapping table" at the top of this plan — go through the file line-by-line.
4. Replace every `SettingsActionButton(...)` callsite with `SmallTextButton(label: ..., icon: ..., onPressed: ..., emphasis: SmallTextButtonEmphasis.filled or outlined or text)`. Keep the same visual emphasis:
   - Primary actions (e.g. "Save", "Check for updates") → `SmallTextButtonEmphasis.filled`
   - Secondary actions (e.g. "Cancel", "Reset") → `SmallTextButtonEmphasis.outlined`
   - Tertiary actions (e.g. "Learn more") → `SmallTextButtonEmphasis.text`
5. Replace every `OutlinedButton.icon(...)` / `FilledButton.icon(...)` / `TextButton.icon(...)` with `SmallTextButton` likewise.
6. Replace every `Icon(..., color: Theme.of(context).colorScheme.primary)` with `Icon(..., color: tokens.accent)`.
7. Replace every `Container` with hardcoded `BorderRadius.circular(N)` by `BorderRadius.circular(tokens.radiusMd)` (or `radiusSm` / `radiusLg` per the table).
8. Remove any import that becomes dead (`fluent/fluent_widgets.dart`, `package:flutter/material.dart#Colors`, etc.).

**Verify per file:**

```bash
grep -n "Theme.of(context)" lib/features/settings/widgets/general/<file>.dart
```

Expected: 0 matches.

- [ ] **Step N+1 · After every file, analyze**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/general/
```

Expected: 0 issues introduced.

### 3.4 Delete `settings_action_button.dart`

- [ ] **Step 3.4.1 · Verify no remaining callsites**

```bash
grep -rn "SettingsActionButton" lib/ test/
```

Expected: 0 matches after Task 3.3.

- [ ] **Step 3.4.2 · Delete the file**

```bash
rm lib/features/settings/widgets/general/settings_action_button.dart
```

- [ ] **Step 3.4.3 · Run suite**

```bash
C:/src/flutter/bin/flutter analyze
C:/src/flutter/bin/flutter test
```

Expected: 0 analyze issues. Suite stable at 1323/14.

### 3.5 Commit Task 3

- [ ] **Step 3.5.1 · Stage and commit**

```bash
git add lib/features/settings/widgets/general_settings_tab.dart \
        lib/features/settings/widgets/general/
git commit -m "refactor: retokenise General tab + 6 sections, remove SettingsActionButton"
```

---

## Task 4 · Folders tab + controller-sync fix

**Files:**
- Modify: `lib/features/settings/widgets/folders_settings_tab.dart` (151 LOC)

### 4.1 Retoken + fix controller sync

- [ ] **Step 1 · Rewrite `folders_settings_tab.dart`**

The three sub-sections (`GameInstallationsSection`, `WorkshopSection`, `RpfmSection`) were already retokenised in Task 3, so this file only needs:
1. Import tokens.
2. Retoken the `error` branch of the `when`.
3. Move the `_loadSettingsIntoControllers(settings)` call **out of `build()`** and into a `ref.listenManual` on `generalSettingsProvider` registered in `initState`. Rationale: per Plan 5d, mutating state during `build` is forbidden; `ref.listenManual` is the canonical replacement.

Replace the file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/settings_providers.dart';
import '../models/game_display_info.dart';
import 'general/game_installations_section.dart';
import 'general/workshop_section.dart';
import 'general/rpfm_section.dart';

class FoldersSettingsTab extends ConsumerStatefulWidget {
  const FoldersSettingsTab({super.key});

  @override
  ConsumerState<FoldersSettingsTab> createState() => _FoldersSettingsTabState();
}

class _FoldersSettingsTabState extends ConsumerState<FoldersSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  late final Map<String, TextEditingController> _gamePathControllers;
  late final TextEditingController _workshopPathController;
  late final TextEditingController _rpfmPathController;
  late final TextEditingController _rpfmSchemaPathController;
  bool _initialLoadDone = false;

  static const List<GameDisplayInfo> _games = [
    GameDisplayInfo(code: 'wh3', name: 'Total War: WARHAMMER III', settingsKey: SettingsKeys.gamePathWh3),
    GameDisplayInfo(code: 'wh2', name: 'Total War: WARHAMMER II', settingsKey: SettingsKeys.gamePathWh2),
    GameDisplayInfo(code: 'wh', name: 'Total War: WARHAMMER', settingsKey: SettingsKeys.gamePathWh),
    GameDisplayInfo(code: 'rome2', name: 'Total War: Rome II', settingsKey: SettingsKeys.gamePathRome2),
    GameDisplayInfo(code: 'attila', name: 'Total War: Attila', settingsKey: SettingsKeys.gamePathAttila),
    GameDisplayInfo(code: 'troy', name: 'Total War: Troy', settingsKey: SettingsKeys.gamePathTroy),
    GameDisplayInfo(code: '3k', name: 'Total War: Three Kingdoms', settingsKey: SettingsKeys.gamePath3k),
    GameDisplayInfo(code: 'pharaoh', name: 'Total War: Pharaoh', settingsKey: SettingsKeys.gamePathPharaoh),
    GameDisplayInfo(code: 'pharaoh_dynasties', name: 'Total War: Pharaoh Dynasties', settingsKey: SettingsKeys.gamePathPharaohDynasties),
  ];

  @override
  void initState() {
    super.initState();
    _workshopPathController = TextEditingController();
    _rpfmPathController = TextEditingController();
    _rpfmSchemaPathController = TextEditingController();
    _gamePathControllers = {
      for (final game in _games) game.code: TextEditingController(),
    };

    // Load settings into controllers once, via listenManual (not in build).
    ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      generalSettingsProvider,
      (_, next) {
        if (_initialLoadDone) return;
        final settings = next.valueOrNull;
        if (settings == null) return;
        _initialLoadDone = true;
        for (final game in _games) {
          _gamePathControllers[game.code]!.text = settings[game.settingsKey] ?? '';
        }
        _workshopPathController.text = settings[SettingsKeys.workshopPath] ?? '';
        _rpfmPathController.text = settings[SettingsKeys.rpfmPath] ?? '';
        _rpfmSchemaPathController.text = settings[SettingsKeys.rpfmSchemaPath] ?? '';
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _workshopPathController.dispose();
    _rpfmPathController.dispose();
    _rpfmSchemaPathController.dispose();
    for (final controller in _gamePathControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(generalSettingsProvider);
    final tokens = context.tokens;

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text(
          'Error loading settings: $error',
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.err),
        ),
      ),
      data: (settings) {
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              GameInstallationsSection(
                gamePathControllers: _gamePathControllers,
                games: _games,
              ),
              const SizedBox(height: 16),
              WorkshopSection(
                workshopPathController: _workshopPathController,
              ),
              const SizedBox(height: 32),
              RpfmSection(
                rpfmPathController: _rpfmPathController,
                rpfmSchemaPathController: _rpfmSchemaPathController,
              ),
            ],
          ),
        );
      },
    );
  }
}
```

> **Verify `valueOrNull`:** per memory, Riverpod 3 removed `valueOrNull` at one point — if the static analyzer complains, use `next is AsyncData ? next.value : null`. Same fix applies in Task 5.

- [ ] **Step 2 · Run analyze + tests**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/folders_settings_tab.dart
C:/src/flutter/bin/flutter test test/features/settings/
```

Expected: 0 analyze issues. Existing folders settings tests (if any) still pass.

- [ ] **Step 3 · Commit**

```bash
git add lib/features/settings/widgets/folders_settings_tab.dart
git commit -m "refactor: retokenise Folders tab and move controller sync out of build"
```

---

## Task 5 · LLM Providers tab + models list

**Files:**
- Modify: `lib/features/settings/widgets/llm_providers_tab.dart` (291 LOC)
- Modify: `lib/features/settings/widgets/llm_models_list.dart` (401 LOC)

### 5.1 Retoken `llm_providers_tab.dart` + same controller-sync fix

- [ ] **Step 1 · Rewrite the tab**

Replace the file `lib/features/settings/widgets/llm_providers_tab.dart` with a version that:
1. Imports `twmt_theme_tokens.dart`.
2. Moves the controller-init block currently inside `build()` (lines 111-125) into a `ref.listenManual` in `initState`, identical pattern to Task 4.
3. Retokens the header, `_buildAdvancedSettings`, every `Theme.of(context)` and every hardcoded color, per the Token mapping table.
4. Replaces the two `FluentToast.error(context, '…')` calls — keep them as-is (deferred, per spec §4 rule 6). Only retoken the surrounding surfaces.
5. The Slider's track/thumb/active colors should use `tokens.accent` via a `SliderTheme` wrap.
6. The inline `Container` around the numeric display uses `tokens.border` + `BorderRadius.circular(tokens.radiusSm)`.

**Expected delta:** file drops from 291 LOC to ~240-260 LOC. `grep -n "Theme.of(context)" lib/features/settings/widgets/llm_providers_tab.dart` must return 0.

> **Note:** the `LlmProviderSection` calls remain unchanged (5 instances) — they were already migrated to the accordion primitive in Task 2.4.

- [ ] **Step 2 · Run**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/llm_providers_tab.dart
```

Expected: 0 issues.

### 5.2 Retoken `llm_models_list.dart`

- [ ] **Step 3 · Read the file first**

```bash
wc -l lib/features/settings/widgets/llm_models_list.dart
grep -n "Theme.of(context)" lib/features/settings/widgets/llm_models_list.dart
```

Expected: 401 lines, ~17 `Theme.of(context)` matches.

- [ ] **Step 4 · Apply the Token mapping table, top-down**

Do NOT restructure the widget tree. Only:
1. Add `import 'package:twmt/theme/twmt_theme_tokens.dart';`.
2. In each build method / helper, add `final tokens = context.tokens;` as first statement.
3. Apply **every** mapping — Colors / text styles / hardcoded radii / hardcoded hex.
4. Replace any `OutlinedButton` / `FilledButton` / `TextButton` / `IconButton` with `SmallTextButton` or `SmallIconButton` per the emphasis rule.
5. Remove dead imports.

**Verify:**

```bash
grep -n "Theme.of(context)" lib/features/settings/widgets/llm_models_list.dart
```

Expected: 0 matches.

- [ ] **Step 5 · Analyze and commit**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/
git add lib/features/settings/widgets/llm_providers_tab.dart lib/features/settings/widgets/llm_models_list.dart
git commit -m "refactor: retokenise LLM Providers tab and models list"
```

---

## Task 6 · 3 datagrids + 3 data_sources

**Files:**
- Modify: `lib/features/settings/widgets/language_settings_datagrid.dart` (259 LOC)
- Modify: `lib/features/settings/widgets/language_settings_data_source.dart` (221 LOC)
- Modify: `lib/features/settings/widgets/ignored_source_texts_datagrid.dart` (269 LOC)
- Modify: `lib/features/settings/widgets/ignored_source_texts_data_source.dart` (198 LOC)
- Modify: `lib/features/settings/widgets/llm_custom_rules_datagrid.dart` (266 LOC)
- Modify: `lib/features/settings/widgets/llm_custom_rules_data_source.dart` (193 LOC)

### 6.1 Canonical datagrid transformation pattern

Each of the 3 datagrids follows the same transformation.

**Before (representative):**

```dart
return SfDataGrid(
  source: _dataSource,
  columns: [...],
  // ...
);
```

**After:**

```dart
final tokens = context.tokens;
return SfDataGridTheme(
  data: buildTokenDataGridTheme(tokens),
  child: SfDataGrid(
    source: _dataSource,
    columns: [...],
    gridLinesVisibility: GridLinesVisibility.horizontal,
    headerGridLinesVisibility: GridLinesVisibility.horizontal,
    // ...
  ),
);
```

Add imports:

```dart
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
// NEW:
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
```

The 3rd-party `SfDataGridTheme` widget lives in `package:syncfusion_flutter_core/theme.dart` — verify that this is already imported (it is, per Plan 4's `pubspec.yaml` promotion).

### 6.2 Canonical data_source transformation pattern

Data sources inject cell styles inline via `DataGridCell` + `buildRow`. Replace:

- `color: Theme.of(context).colorScheme.onSurface` → `color: tokens.text`
- `color: Colors.red` → `color: tokens.err`
- `color: Colors.green` → `color: tokens.ok`
- `color: Colors.grey` → `color: tokens.textDim`

**Pitfall:** data sources don't have a `context` parameter in their method signatures. Inject a `TwmtThemeTokens` via the constructor:

```dart
class LanguageSettingsDataSource extends DataGridSource {
  LanguageSettingsDataSource({required this.tokens, ...});
  final TwmtThemeTokens tokens;
  // use tokens.X instead of Theme.of(context).X inside buildRow / cell builders
}
```

The datagrid widget then instantiates with `LanguageSettingsDataSource(tokens: context.tokens, ...)`.

### 6.3 Per-file steps

For each of the 3 datagrid/data_source pairs:

- [ ] **Step N · Read both files**

```bash
cat lib/features/settings/widgets/language_settings_datagrid.dart
cat lib/features/settings/widgets/language_settings_data_source.dart
```

- [ ] **Step N+1 · Apply §6.1 to the datagrid file**

- [ ] **Step N+2 · Apply §6.2 to the data source**

Inject `tokens` via constructor. Update the datagrid's `initState` to pass `context.tokens` if the data source is created in `initState`. If created lazily or via a provider, add a `ref.listen` to invalidate on theme change.

> **Pitfall:** if the data source is created in `initState`, reading `context.tokens` in `initState` is unsafe (theme not yet resolved). Use `didChangeDependencies` instead:
>
> ```dart
> @override
> void didChangeDependencies() {
>   super.didChangeDependencies();
>   _dataSource ??= LanguageSettingsDataSource(tokens: context.tokens, ...);
> }
> ```
>
> Recreate the data source on theme change by listening to `Theme.of(context).extension<TwmtThemeTokens>()` identity and calling `notifyListeners()` on the data source.

- [ ] **Step N+3 · Analyze per file**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/<file>.dart
```

Expected: 0 issues.

### 6.4 Commit Task 6

- [ ] **Step 6.4.1 · Run full test suite to catch regressions**

```bash
C:/src/flutter/bin/flutter test
```

Expected: 1323/14 (no behaviour change).

- [ ] **Step 6.4.2 · Commit**

```bash
git add lib/features/settings/widgets/*datagrid.dart lib/features/settings/widgets/*data_source.dart
git commit -m "refactor: wrap settings datagrids in SfDataGridTheme + retokenise cell renderers"
```

---

## Task 7 · 5 dialogs

**Files:**
- Modify: `lib/features/settings/widgets/add_custom_language_dialog.dart` (174 LOC)
- Modify: `lib/features/settings/widgets/ignored_source_text_editor_dialog.dart` (178 LOC)
- Modify: `lib/features/settings/widgets/llm_custom_rule_editor_dialog.dart` (174 LOC)
- Modify: `lib/features/settings/widgets/dialogs/backup_restore_confirmation_dialog.dart` (246 LOC)
- Modify: `lib/features/settings/widgets/model_management_dialog.dart` (470 LOC)

### 7.1 Canonical dialog transformation rules

Each dialog either stays as `AlertDialog` (if body is short and action-only) or converts to `Dialog` (if body has ≥2 fields or custom layout). Plan 5d convention:

- **Keep `AlertDialog`** when: simple text content + 1-2 action buttons.
- **Convert to `Dialog`** when: ≥2 input fields, custom sizing, or rich content.

**AlertDialog transform (example):**

```dart
// Before:
AlertDialog(
  title: Text('Title'),
  content: Text('...'),
  actions: [
    TextButton(onPressed: ..., child: const Text('Cancel')),
    FilledButton(onPressed: ..., child: const Text('Confirm')),
  ],
)

// After:
AlertDialog(
  backgroundColor: tokens.panel,
  title: Text(
    'Title',
    style: tokens.fontDisplay.copyWith(
      fontSize: 18,
      color: tokens.text,
      fontStyle: tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
    ),
  ),
  content: Text(
    '...',
    style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
  ),
  actions: [
    SmallTextButton(label: 'Cancel', onPressed: ...),
    SmallTextButton(
      label: 'Confirm',
      emphasis: SmallTextButtonEmphasis.filled,
      onPressed: ...,
    ),
  ],
)
```

**Dialog transform (example for rich bodies):**

```dart
Dialog(
  backgroundColor: tokens.panel,
  insetPadding: const EdgeInsets.all(40),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(tokens.radiusLg),
  ),
  child: SizedBox(
    width: 480,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Title', style: tokens.fontDisplay.copyWith(...)),
          const SizedBox(height: 16),
          // body content using LabeledField + TokenTextField
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SmallTextButton(label: 'Cancel', onPressed: ...),
              const SizedBox(width: 8),
              SmallTextButton(
                label: 'Save',
                emphasis: SmallTextButtonEmphasis.filled,
                onPressed: ...,
              ),
            ],
          ),
        ],
      ),
    ),
  ),
)
```

### 7.2 Per-dialog classification

| Dialog | Action |
|---|---|
| `add_custom_language_dialog.dart` | **Dialog** (2 fields: code + name) |
| `ignored_source_text_editor_dialog.dart` | **Dialog** (TextField with validation) |
| `llm_custom_rule_editor_dialog.dart` | **Dialog** (TextField + enabled toggle) |
| `dialogs/backup_restore_confirmation_dialog.dart` | **Dialog** (list of backup items with selection) |
| `model_management_dialog.dart` | **Dialog** (long list, 470 LOC, retoken only — no structural change) |

### 7.3 Per-dialog steps

For each dialog (5 × the same sequence):

- [ ] **Step N · Read dialog + determine field usage**

```bash
cat lib/features/settings/widgets/<dialog>.dart
grep -n "TextFormField\|TextField" lib/features/settings/widgets/<dialog>.dart
```

- [ ] **Step N+1 · Rewrite per §7.1 transform**

Apply the appropriate `AlertDialog` vs `Dialog` transform. Inside the dialog body, replace every `TextFormField` / `TextField` with the `TokenTextField` primitive (with a `LabeledField` wrap when a label is needed). Use `SmallTextButton` for every action.

> **Special case for `model_management_dialog.dart`:** do NOT refactor its structure (deferred to Plan 5f per spec §2.2). Just apply the Token mapping table exhaustively. File should drop from 470 to ~440 LOC.

- [ ] **Step N+2 · Analyze**

```bash
C:/src/flutter/bin/flutter analyze lib/features/settings/widgets/<dialog>.dart
```

Expected: 0 issues.

### 7.4 Commit Task 7

- [ ] **Step 7.4.1 · Full suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: 1323/14.

- [ ] **Step 7.4.2 · Commit**

```bash
git add lib/features/settings/widgets/*_dialog.dart lib/features/settings/widgets/dialogs/
git commit -m "refactor: retokenise settings dialogs and convert rich ones to Dialog"
```

---

## Task 8 · 8 goldens (4 tabs × 2 themes)

**Files:**
- Create: `test/features/settings/screens/settings_screen_general_golden_test.dart`
- Create: `test/features/settings/screens/settings_screen_folders_golden_test.dart`
- Create: `test/features/settings/screens/settings_screen_llm_providers_golden_test.dart`
- Create: `test/features/settings/screens/settings_screen_appearance_golden_test.dart`
- New PNGs: `test/features/settings/goldens/settings_{tab}_{theme}.png` × 8

### 8.1 Canonical golden test template

Each of the 4 test files follows this template (shown here for General tab):

```dart
// Golden tests for the retokenised Settings screen — General tab (Plan 5e).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

List<Override> _overrides() => [
      generalSettingsProvider.overrideWith((_) async => _fixtureSettings()),
      // Any other provider the tab watches, overridden with deterministic data.
    ];

Map<String, dynamic> _fixtureSettings() => {
      SettingsKeys.sourceLanguage: 'en',
      SettingsKeys.targetLanguage: 'fr',
      // … any other keys the General tab / its sections read
    };

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SettingsScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    // The default tab is General; if not, drive TabController manually.
    await tester.pumpAndSettle();
  }

  testWidgets('settings general atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_general_atelier.png'),
    );
  });

  testWidgets('settings general forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_general_forge.png'),
    );
  });
}
```

### 8.2 Tab switching for non-default tabs

Folders, LLM Providers, and Appearance are not the default tab. Drive the `TabController` in the pumpUnder helper:

```dart
Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
  await tester.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(createThemedTestableWidget(
    const SettingsScreen(),
    theme: theme,
    overrides: _overrides(),
  ));
  await tester.pumpAndSettle();

  // Navigate to the target tab (1 = Folders, 2 = LLM Providers, 3 = Appearance).
  await tester.tap(find.text('Folders'));   // or 'LLM Providers', 'Appearance'
  await tester.pumpAndSettle();
}
```

### 8.3 Per-tab provider overrides

| Tab | Providers to override |
|---|---|
| General | `generalSettingsProvider`, `enabledIgnoredTextsCountProvider` (0 for empty badge) |
| Folders | `generalSettingsProvider` (paths keys) |
| LLM Providers | `llmProviderSettingsProvider`, `enabledRulesCountProvider` (0), any `llmModelsListProvider` variant |
| Appearance | `themeNameProvider` (fixed to `TwmtThemeName.atelier` or `.forge`) |

For each tab, read the corresponding tab widget + its `.when` branches to determine exactly which providers must be overridden to force the `data:` branch deterministically. Do this before copying the template.

### 8.4 Per-file steps

- [ ] **Step 1 · Create 4 test files from §8.1 template**

For each file, fill in the provider overrides per §8.3 and the tab-switching preamble per §8.2.

- [ ] **Step 2 · Generate goldens (first run expects missing-PNG failure)**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/settings/
```

Expected: 8 PNGs written under `test/features/settings/goldens/`.

- [ ] **Step 3 · Verify stability**

```bash
C:/src/flutter/bin/flutter test test/features/settings/
```

Expected: 8/8 PASS.

- [ ] **Step 4 · Commit (test files + PNGs)**

```bash
git add test/features/settings/
git commit -m "test: add 8 goldens for Settings tabs (General/Folders/LLM/Appearance × Atelier/Forge)"
```

---

## Task 9 · Analyze clean + final sweep

### 9.1 Global analyze

- [ ] **Step 1 · Run analyze**

```bash
C:/src/flutter/bin/flutter analyze
```

Expected: no new warnings introduced. Pre-existing lints from prior plans unchanged.

### 9.2 Final residue check

- [ ] **Step 2 · Grep for residual offending patterns**

```bash
grep -rn "Theme.of(context).colorScheme" lib/features/settings/
grep -rn "FluentScaffold" lib/features/settings/
grep -rn "0xFFE1E1E1\|0xFFA19F9D\|0xFF323130\|0xFF605E5C" lib/features/settings/
```

Expected: 0 matches.

### 9.3 Unused imports

- [ ] **Step 3 · Prune dead imports**

For every file touched in Tasks 1-7, remove unused imports (the analyzer flags them):

```bash
C:/src/flutter/bin/flutter analyze 2>&1 | grep "unused_import"
```

Fix every occurrence, then re-run analyze.

### 9.4 Final test run

- [ ] **Step 4 · Full suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: **1331 passing / 14 pre-existing failures** (baseline 1323 + 8 new goldens).

If the count differs, investigate before proceeding.

### 9.5 Self-review checklist

- [ ] All 9 acceptance criteria (spec §10) verified one by one:
  1. Zero `Theme.of(context).colorScheme` in `lib/features/settings/` ✓
  2. Zero `FluentScaffold` in `lib/features/settings/` ✓
  3. Zero hardcoded hex (except Atelier/Forge token sources + appearance preview swatches) ✓
  4. `SettingsAccordionSection` used at exactly 3 callsites ✓
  5. `settings_action_button.dart` deleted ✓
  6. 8 goldens passing on both themes ✓
  7. `flutter analyze` clean ✓
  8. Tests 1331/14 ✓
  9. Controller sync out of `build` in Folders tab + LLM Providers tab ✓

### 9.6 Commit any residual cleanup

- [ ] **Step 5 · Commit**

```bash
git add -u
git commit -m "chore: prune dead imports after Settings retokenisation"
```

If nothing changed, skip this step (no empty commit).

---

## Merge preparation

- [ ] **Baseline comparison**

```bash
git log main..HEAD --oneline
```

Expect ~10-14 commits:
- Task 1: 2 commits (feat SettingsTabBar + refactor settings_screen)
- Task 2: 3 commits (feat SettingsAccordionSection + 3 × refactor section)
- Task 3: 1 commit (refactor General tab + sections + delete SettingsActionButton)
- Task 4: 1 commit (refactor Folders tab + controller sync)
- Task 5: 1 commit (refactor LLM Providers tab + models list)
- Task 6: 1 commit (refactor settings datagrids)
- Task 7: 1 commit (refactor settings dialogs)
- Task 8: 1 commit (test: 8 goldens)
- Task 9: optional cleanup commit

- [ ] **Verify clean diff against main**

```bash
git diff main --stat lib/features/settings/
git diff main --stat lib/widgets/settings/
git diff main --stat test/
```

Expected:
- `lib/features/settings/`: -900 LOC net
- `lib/widgets/settings/`: +300 LOC (2 primitives)
- `test/`: +400 LOC (2 primitive tests + 4 golden test files)

- [ ] **Update memory after merge** (reviewer / human step, not part of the worktree session)

Add a line to `C:\Users\jmp\.claude\projects\E--Total-War-Mods-Translator\memory\project_ui_redesign_progress.md` under existing entries:

```
**Plan 5e · Settings retokenisation — shipped on main (merge commit <SHA>, 2026-04-xx).**
<N> commits on `feat/ui-settings` (deleted). 2 new primitives (`SettingsTabBar`,
`SettingsAccordionSection`) in `lib/widgets/settings/`. 3 accordion sections
migrated. `settings_action_button.dart` deleted. 8 new goldens.
Controller sync fix applied to Folders + LLM Providers tabs. Tests 1331/14.
Spec `…/2026-04-18-ui-settings-design.md`, plan `…/2026-04-18-ui-settings.md`.
```

---

## Follow-ups deferred (Plan 5f or later)

- Structural rework of `llm_models_list.dart` (401 LOC) and `model_management_dialog.dart` (470 LOC)
- `FluentToast` retokenisation (shared across app, scope too large here)
- `SidebarUpdateChecker` overflow (Plan 2 follow-up, 14 pre-existing test failures)
- `tokens.fontDisplayStyle` getter (Plan 5d deferred: replace `fontDisplayItalic ? FontStyle.italic : FontStyle.normal` ternary repeated now ~15× repo-wide)
- `LabeledField` style parameter extension (Plan 5d deferred)
- `TokenDropdown` primitive (Plan 5d deferred; if needed in Task 5 for rate-limit contextual UI, keep inline — don't extract mid-plan)
- Width 1.5 vs 1 border magic number still present (Plan 5d deferred)
- `_buildGameDropdown` in `step_basic_info.dart` custom-styled DropdownButton (Plan 5d deferred)
