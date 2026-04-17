# Plan 5c · Wizard / form — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopter l'archétype §7.5 (Wizard / form) sur Pack Compilation editor + Workshop Publish single + batch, séparer Pack Compilation en deux routes (§7.1 list + §7.5 editor), extraire une primitive `DetailScreenToolbar` partagée (clôt follow-up 5b reviewer), et retirer le crumb global (clôt follow-up Plan 2).

**Architecture:** 5 primitives composables dans `lib/widgets/wizard/` (`FormSection`, `SummaryBox`, `StickyFormPanel`, `DynamicZonePanel`, `WizardScreenLayout`) + 1 primitive dans `lib/widgets/detail/` (`DetailScreenToolbar`). Chaque écran compose `Column([DetailScreenToolbar, Expanded(Row([StickyFormPanel, VerticalDivider, Expanded(DynamicZonePanel)]))])`. Tokens exclusivement via `context.tokens`. Golden tests par écran (2 thèmes × 1 état = 8 nouveaux goldens).

**Tech Stack:** Flutter Desktop Windows · Riverpod 3 · GoRouter · `flutter_test` goldens · `CustomPainter` pour la bordure dashed du SummaryBox.

**Spec:** [`docs/superpowers/specs/2026-04-17-ui-wizards-design.md`](../specs/2026-04-17-ui-wizards-design.md)

**Predecessors (shipped on main):** Plan 1 (tokens), Plan 2 (navigation), Plan 3 (Home + cards), Plan 4 (Editor), Plan 5a (Lists + `lib/widgets/lists/`), Plan 5b (Details + `lib/widgets/detail/`).

**Reused primitives:**
- Plan 5a : `FilterToolbar`, `FilterPill`, `ListToolbarLeading`, `ListSearchField`, `ListRow`, `ListRowHeader`, `ListRowColumn`, `SmallTextButton`, `SmallIconButton`, `StatusPill`, `formatRelativeSince`, `clockProvider`.
- Plan 5b : Aucun composant UI direct réutilisé (`StatsRail` non utilisé). `initials` helper non utilisé.

---

## File Structure

### New primitives (Task 1-2)

- `lib/widgets/detail/detail_screen_toolbar.dart` — toolbar 48px (crumb + back + trailing) partagée avec Project/Glossary Detail
- `lib/widgets/wizard/form_section.dart` — titled group of form fields
- `lib/widgets/wizard/summary_box.dart` — dashed-bordered live preview (`SummaryLine`, `SummarySemantics`)
- `lib/widgets/wizard/sticky_form_panel.dart` — 380px left column (sections + summary + actions)
- `lib/widgets/wizard/dynamic_zone_panel.dart` — 1fr right column slot
- `lib/widgets/wizard/wizard_screen_layout.dart` — composition §7.5 (toolbar + form + zone)

### New screens (Tasks 4-7)

- `lib/features/pack_compilation/screens/pack_compilation_list_screen.dart` — §7.1 filterable list
- `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` — §7.5 wizard

### Rewritten screens (Tasks 6-7)

- `lib/features/steam_publish/screens/workshop_publish_screen.dart` — §7.5 rewrite
- `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart` — §7.5 degenerate rewrite

### Migrated screens (Task 1)

- `lib/features/projects/screens/project_detail_screen.dart` — adopt `DetailScreenToolbar` primitive
- `lib/features/glossary/screens/glossary_screen.dart` — adopt `DetailScreenToolbar` primitive

### Router changes (Task 3)

- `lib/config/router/app_router.dart` — ajout `/publishing/pack/new` + `/publishing/pack/:id/edit`

### Deleted files

- `lib/features/pack_compilation/screens/pack_compilation_screen.dart` (mixed list+editor)
- `lib/features/pack_compilation/widgets/compilation_editor.dart` (logic migrates to editor screen)
- `lib/features/pack_compilation/widgets/compilation_list.dart` (replaced by list screen composition)
- `lib/features/pack_compilation/widgets/compilation_editor_sections.dart` (replaced by `FormSection`)
- `lib/features/pack_compilation/widgets/compilation_editor_form_widgets.dart` (replaced by `FormSection`)

### Removed at Task 8

- Crumb block from `lib/widgets/layouts/main_layout_router.dart` (verify via grep first)

### New test files

- `test/widgets/detail/detail_screen_toolbar_test.dart`
- `test/widgets/wizard/form_section_test.dart`
- `test/widgets/wizard/summary_box_test.dart`
- `test/widgets/wizard/sticky_form_panel_test.dart`
- `test/widgets/wizard/dynamic_zone_panel_test.dart`
- `test/widgets/wizard/wizard_screen_layout_test.dart`
- `test/features/pack_compilation/screens/pack_compilation_list_screen_test.dart`
- `test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart`
- `test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart`
- `test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart`
- `test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart` (new; existing test file updated)
- `test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart` (new)

---

## Worktree setup (pre-Task 1)

- [ ] **Create worktree & branch**

```bash
cd /e/Total-War-Mods-Translator
git worktree add .worktrees/ui-wizards -b feat/ui-wizards main
cd .worktrees/ui-wizards
```

- [ ] **Copy `windows/` and regenerate generated code**

```bash
cp -r ../../windows ./
C:/src/flutter/bin/flutter pub get
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Baseline verify**

```bash
C:/src/flutter/bin/flutter test
```

Expected: suite green at ~1330/14 (Plan 5b baseline, 14 pre-existing `SidebarUpdateChecker` overflow failures per memory).

---

## Task 1 · `DetailScreenToolbar` primitive + Project/Glossary migration

**Files:**
- Create: `lib/widgets/detail/detail_screen_toolbar.dart`
- Test: `test/widgets/detail/detail_screen_toolbar_test.dart`
- Modify: `lib/features/projects/screens/project_detail_screen.dart` (drop `_ToolbarCrumb`, import primitive)
- Modify: `lib/features/glossary/screens/glossary_screen.dart` (drop `_GlossaryToolbarCrumb`, import primitive)

Clôt le Plan 5b code-reviewer follow-up (duplication entre Project Detail et Glossary Detail). Les goldens existants doivent rester byte-identiques.

### 1.1 Create the primitive

- [ ] **Step 1 · Write the failing test**

Create `test/widgets/detail/detail_screen_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders crumb and back icon', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'Work › Projects › Foo',
      onBack: () {},
    )));
    expect(find.text('Work › Projects › Foo'), findsOneWidget);
    expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsOneWidget);
  });

  testWidgets('back icon tap fires onBack', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () => tapped = true,
    )));
    await t.tap(find.byIcon(FluentIcons.arrow_left_24_regular));
    expect(tapped, isTrue);
  });

  testWidgets('renders trailing widgets', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
      trailing: const [Text('ACT-1'), Text('ACT-2')],
    )));
    expect(find.text('ACT-1'), findsOneWidget);
    expect(find.text('ACT-2'), findsOneWidget);
  });

  testWidgets('toolbar height is 48', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final container = t.widget<Container>(find.descendant(
      of: find.byType(DetailScreenToolbar),
      matching: find.byType(Container),
    ).first);
    final constraints = container.constraints;
    expect(constraints?.maxHeight ?? (container.decoration != null ? 48.0 : 0.0), 48);
  });

  testWidgets('crumb uses font-mono 12px textDim', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('X'));
    expect(text.style?.fontSize, 12);
    expect(text.style?.color, tokens.textDim);
  });
}
```

- [ ] **Step 2 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/detail/detail_screen_toolbar_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 3 · Implement the primitive**

Create `lib/widgets/detail/detail_screen_toolbar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';

/// Detail-screen top toolbar (§7.2 / §7.5).
///
/// 48px fixed height with a back button, ellipsised crumb text, and optional
/// trailing widgets (actions). Used by Project Detail, Glossary Detail, and
/// the three Plan 5c wizard screens.
class DetailScreenToolbar extends StatelessWidget {
  final String crumb;
  final VoidCallback onBack;
  final List<Widget> trailing;

  const DetailScreenToolbar({
    super.key,
    required this.crumb,
    required this.onBack,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SmallIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              crumb,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: tokens.textDim,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            ...trailing,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/detail/detail_screen_toolbar_test.dart
```

Expected: all 5 tests PASS.

### 1.2 Migrate Project Detail

- [ ] **Step 5 · Replace `_ToolbarCrumb` usage in `project_detail_screen.dart`**

Open `lib/features/projects/screens/project_detail_screen.dart`:

1. Add import at top:
   ```dart
   import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
   ```
2. Replace the `_ToolbarCrumb(crumb: ..., onBack: ...)` call inside `_Content.build` with `DetailScreenToolbar(crumb: ..., onBack: ...)`.
3. Delete the private `_ToolbarCrumb` class definition at the bottom of the file.

- [ ] **Step 6 · Verify Project Detail tests still pass**

```bash
C:/src/flutter/bin/flutter test test/features/projects/screens/
```

Expected: all tests PASS. Goldens `project_detail_atelier.png` / `project_detail_forge.png` byte-identical (rendering is visually unchanged).

If goldens drift, investigate — the refactor should not change rendering. Do NOT regenerate without understanding why.

### 1.3 Migrate Glossary Detail

- [ ] **Step 7 · Replace `_GlossaryToolbarCrumb` in `glossary_screen.dart`**

Open `lib/features/glossary/screens/glossary_screen.dart`:

1. Add import at top:
   ```dart
   import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
   ```
2. Replace the `_GlossaryToolbarCrumb(...)` call inside `_buildGlossaryEditorView` with `DetailScreenToolbar(...)`.
3. Delete the private `_GlossaryToolbarCrumb` class definition.

- [ ] **Step 8 · Verify Glossary tests still pass**

```bash
C:/src/flutter/bin/flutter test test/features/glossary/
```

Expected: all tests PASS. Goldens `glossary_detail_atelier.png` / `glossary_detail_forge.png` byte-identical.

- [ ] **Step 9 · Commit**

```bash
cd E:/Total-War-Mods-Translator/.worktrees/ui-wizards
git add lib/widgets/detail/detail_screen_toolbar.dart \
        test/widgets/detail/detail_screen_toolbar_test.dart \
        lib/features/projects/screens/project_detail_screen.dart \
        lib/features/glossary/screens/glossary_screen.dart
git commit -m "refactor: extract DetailScreenToolbar primitive from Project/Glossary Detail"
```

---

## Task 2 · Wizard primitives

**Files (all new):**
- `lib/widgets/wizard/form_section.dart`
- `lib/widgets/wizard/summary_box.dart`
- `lib/widgets/wizard/sticky_form_panel.dart`
- `lib/widgets/wizard/dynamic_zone_panel.dart`
- `lib/widgets/wizard/wizard_screen_layout.dart`
- `test/widgets/wizard/form_section_test.dart`
- `test/widgets/wizard/summary_box_test.dart`
- `test/widgets/wizard/sticky_form_panel_test.dart`
- `test/widgets/wizard/dynamic_zone_panel_test.dart`
- `test/widgets/wizard/wizard_screen_layout_test.dart`

### 2.1 `FormSection`

- [ ] **Step 1 · Write the failing test**

Create `test/widgets/wizard/form_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/form_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders uppercase label + children', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'Basics',
      children: [Text('f1'), Text('f2')],
    )));
    expect(find.text('BASICS'), findsOneWidget);
    expect(find.text('f1'), findsOneWidget);
    expect(find.text('f2'), findsOneWidget);
  });

  testWidgets('renders helpText when provided', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'L',
      helpText: 'Help me',
      children: [Text('c')],
    )));
    expect(find.text('Help me'), findsOneWidget);
  });

  testWidgets('omits helpText when null', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'L',
      children: [Text('c')],
    )));
    expect(find.byKey(const Key('form-section-help-text')), findsNothing);
  });
}
```

- [ ] **Step 2 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/form_section_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 3 · Implement `FormSection`**

Create `lib/widgets/wizard/form_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Titled group of form fields (§7.5).
///
/// Renders an uppercase mono label followed by optional help text and a
/// vertical stack of [children] (gap 10px). Margin-bottom 16.
class FormSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final String? helpText;

  const FormSection({
    super.key,
    required this.label,
    required this.children,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (helpText != null) ...[
            const SizedBox(height: 2),
            Text(
              helpText!,
              key: const Key('form-section-help-text'),
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: tokens.textFaint,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/form_section_test.dart
```

Expected: all 3 tests PASS.

### 2.2 `SummaryBox` + `SummaryLine` + `SummarySemantics`

- [ ] **Step 5 · Write the failing test**

Create `test/widgets/wizard/summary_box_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders uppercase kicker + key/value lines', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'Will generate',
      lines: [
        SummaryLine(key: 'Filename', value: 'foo.pack'),
        SummaryLine(key: 'Size', value: '3.2 MB'),
      ],
    )));
    expect(find.text('WILL GENERATE'), findsOneWidget);
    expect(find.text('Filename'), findsOneWidget);
    expect(find.text('foo.pack'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('3.2 MB'), findsOneWidget);
  });

  testWidgets('semantics applies color to kicker', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'X',
      semantics: SummarySemantics.warn,
      lines: [SummaryLine(key: 'K', value: 'V')],
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final kicker = t.widget<Text>(find.text('X'));
    expect(kicker.style?.color, tokens.warn);
  });

  testWidgets('per-line semantics overrides box semantics', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'X',
      semantics: SummarySemantics.accent,
      lines: [
        SummaryLine(key: 'OK', value: '1', semantics: SummarySemantics.ok),
      ],
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    expect(t.widget<Text>(find.text('1')).style?.color, tokens.ok);
  });
}
```

- [ ] **Step 6 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/summary_box_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 7 · Implement `SummaryBox`**

Create `lib/widgets/wizard/summary_box.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Semantic variants for [SummaryBox] / [SummaryLine].
enum SummarySemantics { neutral, accent, ok, warn, err }

Color _semanticColor(TwmtThemeTokens tokens, SummarySemantics s) {
  return switch (s) {
    SummarySemantics.neutral => tokens.textMid,
    SummarySemantics.accent => tokens.accent,
    SummarySemantics.ok => tokens.ok,
    SummarySemantics.warn => tokens.warn,
    SummarySemantics.err => tokens.err,
  };
}

/// Single key/value row within a [SummaryBox].
class SummaryLine {
  final String key;
  final String value;
  final SummarySemantics? semantics;

  const SummaryLine({
    required this.key,
    required this.value,
    this.semantics,
  });
}

/// Live-preview box for wizard forms (§7.5). Dashed border + uppercase
/// kicker + stacked key/value rows. Semantic color applies to the kicker
/// and border; per-[SummaryLine] semantics overrides the row value color.
class SummaryBox extends StatelessWidget {
  final String label;
  final List<SummaryLine> lines;
  final SummarySemantics semantics;

  const SummaryBox({
    super.key,
    required this.label,
    required this.lines,
    this.semantics = SummarySemantics.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = _semanticColor(tokens, semantics);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: fg.withValues(alpha: 0.7),
        strokeWidth: 1,
        gap: 4,
        dashLength: 6,
        radius: tokens.radiusSm,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: fg,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.key,
                        style: tokens.fontBody.copyWith(
                          fontSize: 12,
                          color: tokens.textMid,
                        ),
                      ),
                    ),
                    Text(
                      line.value,
                      style: tokens.fontMono.copyWith(
                        fontSize: 12,
                        color: _semanticColor(tokens, line.semantics ?? semantics),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gap;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gap,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gap != gap ||
      oldDelegate.radius != radius;
}
```

- [ ] **Step 8 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/summary_box_test.dart
```

Expected: all 3 tests PASS.

### 2.3 `DynamicZonePanel`

- [ ] **Step 9 · Write the failing test**

Create `test/widgets/wizard/dynamic_zone_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders child', (t) async {
    await t.pumpWidget(wrap(const DynamicZonePanel(child: Text('dyn'))));
    expect(find.text('dyn'), findsOneWidget);
  });

  testWidgets('applies custom padding', (t) async {
    await t.pumpWidget(wrap(const DynamicZonePanel(
      padding: EdgeInsets.all(8),
      child: Text('p'),
    )));
    final padding = t.widget<Padding>(find.ancestor(
      of: find.text('p'),
      matching: find.byType(Padding),
    ).first);
    expect(padding.padding, const EdgeInsets.all(8));
  });
}
```

- [ ] **Step 10 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/dynamic_zone_panel_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 11 · Implement `DynamicZonePanel`**

Create `lib/widgets/wizard/dynamic_zone_panel.dart`:

```dart
import 'package:flutter/material.dart';

/// Right-column dynamic zone for §7.5 wizard screens.
///
/// Minimal slot that hosts the per-screen dynamic content (selection list,
/// preview, progress, logs). Intentionally thin — screens compose the
/// specific tree (Column / AnimatedSwitcher / Stack) inside the [child].
class DynamicZonePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DynamicZonePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}
```

- [ ] **Step 12 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/dynamic_zone_panel_test.dart
```

Expected: both tests PASS.

### 2.4 `StickyFormPanel`

- [ ] **Step 13 · Write the failing test**

Create `test/widgets/wizard/sticky_form_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: SizedBox(width: 1200, height: 800, child: Row(children: [child, const Expanded(child: SizedBox())]))),
      );

  testWidgets('panel width defaults to 380', (t) async {
    await t.pumpWidget(wrap(const StickyFormPanel(
      sections: [FormSection(label: 'X', children: [Text('c')])],
    )));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.byType(FormSection),
      matching: find.byType(SizedBox).at(0),
    ).first);
    expect(sized.width, 380);
  });

  testWidgets('renders sections, summary, and actions', (t) async {
    await t.pumpWidget(wrap(StickyFormPanel(
      sections: const [FormSection(label: 'S', children: [Text('field')])],
      summary: const SummaryBox(label: 'sum', lines: [SummaryLine(key: 'k', value: 'v')]),
      actions: [const Text('Action-1')],
    )));
    expect(find.text('field'), findsOneWidget);
    expect(find.text('SUM'), findsOneWidget);
    expect(find.text('Action-1'), findsOneWidget);
  });

  testWidgets('omits summary when null', (t) async {
    await t.pumpWidget(wrap(const StickyFormPanel(
      sections: [FormSection(label: 'S', children: [Text('c')])],
    )));
    expect(find.byType(SummaryBox), findsNothing);
  });
}
```

- [ ] **Step 14 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/sticky_form_panel_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 15 · Implement `StickyFormPanel`**

Create `lib/widgets/wizard/sticky_form_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

/// Sticky left column for §7.5 wizard screens.
///
/// Renders a fixed-width panel (default 380) containing [sections] at top,
/// an optional [summary] in the middle, and stacked [actions] at the
/// bottom. The panel scrolls internally when content exceeds the viewport.
class StickyFormPanel extends StatelessWidget {
  final List<Widget> sections;
  final SummaryBox? summary;
  final List<Widget> actions;
  final double width;
  final EdgeInsetsGeometry padding;

  const StickyFormPanel({
    super.key,
    required this.sections,
    this.summary,
    this.actions = const [],
    this.width = 380,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(right: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: padding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...sections,
                if (summary != null) ...[
                  const SizedBox(height: 8),
                  summary!,
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    actions[i],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 16 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/sticky_form_panel_test.dart
```

Expected: all 3 tests PASS.

### 2.5 `WizardScreenLayout`

- [ ] **Step 17 · Write the failing test**

Create `test/widgets/wizard/wizard_screen_layout_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: SizedBox(width: 1600, height: 900, child: child)),
      );

  testWidgets('composes toolbar, form, and dynamic zone', (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('TBAR'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'X', children: [Text('field')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('DYN')),
    )));
    expect(find.text('TBAR'), findsOneWidget);
    expect(find.text('field'), findsOneWidget);
    expect(find.text('DYN'), findsOneWidget);
  });

  testWidgets('form panel left of dynamic zone', (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('t'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'S', children: [Text('left')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('right')),
    )));
    final leftRect = t.getRect(find.text('left'));
    final rightRect = t.getRect(find.text('right'));
    expect(leftRect.left, lessThan(rightRect.left));
  });
}
```

- [ ] **Step 18 · Run test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/wizard_screen_layout_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 19 · Implement `WizardScreenLayout`**

Create `lib/widgets/wizard/wizard_screen_layout.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';

/// Composition §7.5 wizard screen chrome: toolbar + sticky form + dynamic
/// zone. Places the form panel and dynamic zone side-by-side below the
/// toolbar, with a vertical hairline between them.
class WizardScreenLayout extends StatelessWidget {
  final Widget toolbar;
  final StickyFormPanel formPanel;
  final DynamicZonePanel dynamicZone;

  const WizardScreenLayout({
    super.key,
    required this.toolbar,
    required this.formPanel,
    required this.dynamicZone,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                formPanel,
                Expanded(child: dynamicZone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: the vertical border is drawn by `StickyFormPanel` (right-edge border), not by this layout.

- [ ] **Step 20 · Run test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/wizard_screen_layout_test.dart
```

Expected: both tests PASS.

- [ ] **Step 21 · Commit**

```bash
git add lib/widgets/wizard/ test/widgets/wizard/
git commit -m "feat: add wizard primitives (FormSection, SummaryBox, StickyFormPanel, DynamicZonePanel, WizardScreenLayout)"
```

---

## Task 3 · Router — split Pack Compilation into 2 routes

**Files:**
- Modify: `lib/config/router/app_router.dart`

Add routes `/publishing/pack/new` and `/publishing/pack/:id/edit`. The list route `/publishing/pack` is unchanged. Point all three at placeholder screens (actual refactor lands in Tasks 4-5).

- [ ] **Step 1 · Inspect current router routes for pack compilation**

```bash
grep -n "packCompilation" lib/config/router/app_router.dart
```

Expected: the `packCompilation` route is defined once, pointing at `PackCompilationScreen`.

- [ ] **Step 2 · Edit `app_router.dart`**

Open `lib/config/router/app_router.dart`:

1. In the `AppRoutes` class, add the new route constants (below `packCompilation`):

   ```dart
   static const String packCompilationNew = '/publishing/pack/new';
   static String packCompilationEdit(String id) => '/publishing/pack/$id/edit';
   static const String compilationIdParam = 'compilationId';
   ```

2. Replace the import for `pack_compilation_screen.dart` with placeholder imports for the new screens (Tasks 4 and 5 will create them). For Task 3, use the existing `PackCompilationScreen` as the target for all three routes — Tasks 4 and 5 will swap them to the new screens:

   ```dart
   // At the top, keep import '../../features/pack_compilation/screens/pack_compilation_screen.dart';
   ```

3. Update the routes: under the existing `packCompilation` `GoRoute`, add nested children:

   ```dart
   GoRoute(
     path: AppRoutes.packCompilation,
     name: 'packCompilation',
     pageBuilder: (context, state) {
       return FluentPageTransitions.fadeTransition(
         child: const PackCompilationScreen(),
         state: state,
       );
     },
     routes: [
       GoRoute(
         path: 'new',
         name: 'packCompilationNew',
         pageBuilder: (context, state) {
           return FluentPageTransitions.slideFromRightTransition(
             child: const PackCompilationScreen(),   // replaced in Task 5
             state: state,
           );
         },
       ),
       GoRoute(
         path: ':${AppRoutes.compilationIdParam}/edit',
         name: 'packCompilationEdit',
         pageBuilder: (context, state) {
           return FluentPageTransitions.slideFromRightTransition(
             child: const PackCompilationScreen(),   // replaced in Task 5
             state: state,
           );
         },
       ),
     ],
   ),
   ```

4. Add an extension method for typed navigation:

   ```dart
   void goPackCompilationNew() => go(AppRoutes.packCompilationNew);
   void goPackCompilationEdit(String id) => go(AppRoutes.packCompilationEdit(id));
   ```

- [ ] **Step 3 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/config/router/
```

Expected: no new issues.

- [ ] **Step 4 · Run a smoke test that exercises the routes**

```bash
C:/src/flutter/bin/flutter test test/config/
```

Expected: no regression. If there are no tests for the router, create one minimal smoke test:

`test/config/router/app_router_redirect_test.dart`:

```dart
// existing test file; if it exists, just add:
test('packCompilationEdit formats the path correctly', () {
  expect(AppRoutes.packCompilationEdit('abc'), '/publishing/pack/abc/edit');
});
```

- [ ] **Step 5 · Commit**

```bash
git add lib/config/router/app_router.dart
# (and test/config if modified)
git commit -m "feat: add packCompilation new/edit routes in router"
```

---

## Task 4 · Pack Compilation list screen (§7.1)

**Files:**
- Create: `lib/features/pack_compilation/screens/pack_compilation_list_screen.dart`
- Create: `test/features/pack_compilation/screens/pack_compilation_list_screen_test.dart`
- Create: `test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart`
- Modify: `lib/config/router/app_router.dart` (swap `PackCompilationScreen` → `PackCompilationListScreen` for the `packCompilation` route)
- Delete (Task 5): `pack_compilation_screen.dart` and `compilation_list.dart` (do NOT delete yet — Task 5 owns the removal)

Compose the list using 5a primitives. Reuses the existing `compilationsWithDetailsProvider` from `pack_compilation_providers.dart`.

- [ ] **Step 1 · Create a list screen skeleton first (red state)**

Create `lib/features/pack_compilation/screens/pack_compilation_list_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/pack_compilation_providers.dart';

/// Pack compilations list screen (§7.1 archetype).
class PackCompilationListScreen extends ConsumerStatefulWidget {
  const PackCompilationListScreen({super.key});

  @override
  ConsumerState<PackCompilationListScreen> createState() =>
      _PackCompilationListScreenState();
}

class _PackCompilationListScreenState
    extends ConsumerState<PackCompilationListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final async = ref.watch(compilationsWithDetailsProvider);
    final all = async.asData?.value ?? const <CompilationWithDetails>[];
    final filtered = _query.isEmpty
        ? all
        : all
            .where((c) =>
                c.compilation.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.package_multiple_24_regular,
              title: 'Pack compilations',
              countLabel: '${filtered.length} / ${all.length}',
            ),
            trailing: [
              ListSearchField(
                value: _query,
                onChanged: (v) => setState(() => _query = v),
                onClear: () => setState(() => _query = ''),
              ),
              SmallTextButton(
                label: '+ New compilation',
                icon: FluentIcons.add_24_regular,
                onTap: () => context.push(AppRoutes.packCompilationNew),
              ),
            ],
            pillGroups: const [],
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading compilations: $err',
                  style: tokens.fontBody.copyWith(color: tokens.err),
                ),
              ),
              data: (_) => filtered.isEmpty
                  ? _EmptyState(onNew: () => context.push(AppRoutes.packCompilationNew))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _CompilationRow(
                        details: filtered[i],
                        onEdit: () => context.push(AppRoutes.packCompilationEdit(filtered[i].compilation.id)),
                        onDelete: () => _confirmDelete(filtered[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(CompilationWithDetails d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete compilation'),
        content: Text('Delete "${d.compilation.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final repo = ref.read(compilationRepositoryProvider);
              final r = await repo.delete(d.compilation.id);
              if (!mounted) return;
              if (r.isOk) {
                ref.invalidate(compilationsWithDetailsProvider);
                FluentToast.success(context, 'Deleted "${d.compilation.name}"');
              } else {
                FluentToast.error(context, 'Delete failed: ${r.error}');
              }
            },
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.package_multiple_24_regular,
                size: 56, color: tokens.textFaint),
            const SizedBox(height: 16),
            Text(
              'No compilations yet',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.textMid,
                fontStyle:
                    tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a compilation to bundle several projects into one .pack.',
              style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            ),
            const SizedBox(height: 16),
            SmallTextButton(
              label: '+ New compilation',
              icon: FluentIcons.add_24_regular,
              onTap: onNew,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompilationRow extends ConsumerWidget {
  final CompilationWithDetails details;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CompilationRow({
    required this.details,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final now = ref.watch(clockProvider)();
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      details.compilation.updatedAt,
    );
    return ListRow(
      columns: const [
        ListRowColumn.flex(1),
        ListRowColumn.fixed(120),
        ListRowColumn.fixed(100),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              details.compilation.name,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (details.compilation.packName.isNotEmpty)
              Text(
                details.compilation.packName,
                overflow: TextOverflow.ellipsis,
                style: tokens.fontMono.copyWith(
                  fontSize: 10,
                  color: tokens.textDim,
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${details.projects.length} packs',
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textMid,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatRelativeSince(updatedAt, now: now) ?? '—',
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textFaint,
            ),
          ),
        ),
      ],
      trailingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallTextButton(label: 'Edit', onTap: onEdit),
          const SizedBox(width: 6),
          SmallIconButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete compilation',
            onTap: onDelete,
            foreground: tokens.err,
            background: tokens.errBg,
            borderColor: tokens.err.withValues(alpha: 0.3),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}
```

- [ ] **Step 2 · Wire the router to the new screen**

Open `lib/config/router/app_router.dart`. Add the import:

```dart
import '../../features/pack_compilation/screens/pack_compilation_list_screen.dart';
```

Replace the `child: const PackCompilationScreen(),` inside the `packCompilation` `GoRoute` with:

```dart
child: const PackCompilationListScreen(),
```

(Leave the `new` / `:id/edit` child routes pointing at `PackCompilationScreen` for now — Task 5 swaps them.)

- [ ] **Step 3 · Write the widget test**

Create `test/features/pack_compilation/screens/pack_compilation_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_list_screen.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

const int _epoch = 1_700_000_000;

Compilation _c(String id, String name) => Compilation(
      id: id,
      name: name,
      prefix: 'p',
      packName: '$name.pack',
      languageId: 'fr',
      gameInstallationId: 'g',
      createdAt: _epoch,
      updatedAt: _epoch * 1000,
    );

CompilationWithDetails _d(String id, String name, int projCount) =>
    CompilationWithDetails(
      compilation: _c(id, name),
      projects: List.generate(
        projCount,
        (i) => Project(
          id: '$id-$i',
          name: 'p$i',
          gameInstallationId: 'g',
          createdAt: _epoch,
          updatedAt: _epoch,
        ),
      ),
      projectStatistics: const <String, ProjectStatistics>{},
      gameInstallation: const GameInstallation(
        id: 'g',
        gameCode: 'warhammer_iii',
        name: 'Warhammer III',
        path: '',
        executableName: '',
      ),
    );

List<Override> _overrides({required List<CompilationWithDetails> list}) => [
      compilationsWithDetailsProvider.overrideWith((_) async => list),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('empty state renders new button', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(list: const []),
    ));
    await t.pumpAndSettle();
    expect(find.text('No compilations yet'), findsOneWidget);
  });

  testWidgets('populated state renders rows', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(list: [_d('c1', 'Alpha', 3), _d('c2', 'Beta', 1)]),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('3 packs'), findsOneWidget);
    expect(find.text('1 packs'), findsOneWidget);
  });
}
```

- [ ] **Step 4 · Run the widget test**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_list_screen_test.dart
```

Expected: both tests PASS.

Note: If `CompilationWithDetails` constructor has different fields, open its model file (`lib/features/pack_compilation/models/compilation_with_details.dart`) and adjust fixture.

- [ ] **Step 5 · Golden test**

Create `test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_list_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';
// Import fixture helpers from the widget test (or duplicate them here)
// For robustness, duplicate _c, _d, _overrides helpers above.

// --- Copy fixture helpers from pack_compilation_list_screen_test.dart here ---

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: theme,
      overrides: _overrides(list: [_d('c1', 'Imperial Bundle', 4), _d('c2', 'Chaos Pack', 2)]),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('pack compilation list atelier populated', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(PackCompilationListScreen),
      matchesGoldenFile('../goldens/pack_compilation_list_atelier.png'),
    );
  });

  testWidgets('pack compilation list forge populated', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(PackCompilationListScreen),
      matchesGoldenFile('../goldens/pack_compilation_list_forge.png'),
    );
  });
}
```

Copy the `_c`, `_d`, `_overrides` helpers from the widget test into this file (so the goldens are self-contained).

- [ ] **Step 6 · Generate goldens**

```bash
mkdir -p test/features/pack_compilation/goldens
C:/src/flutter/bin/flutter test --update-goldens test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart
```

Expected: 2 new PNG files.

- [ ] **Step 7 · Re-run golden test for stability**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart
```

Expected: PASS.

- [ ] **Step 8 · Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_list_screen.dart \
        lib/config/router/app_router.dart \
        test/features/pack_compilation/screens/pack_compilation_list_screen_test.dart \
        test/features/pack_compilation/screens/pack_compilation_list_screen_golden_test.dart \
        test/features/pack_compilation/goldens/pack_compilation_list_atelier.png \
        test/features/pack_compilation/goldens/pack_compilation_list_forge.png
git commit -m "feat: add PackCompilationListScreen (§7.1 archetype)"
```

---

## Task 5 · Pack Compilation editor screen (§7.5)

**Files:**
- Create: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`
- Create: `test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart`
- Create: `test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart`
- Modify: `lib/config/router/app_router.dart` (swap `PackCompilationScreen` → `PackCompilationEditorScreen` for `new` + `edit`)
- Delete: `lib/features/pack_compilation/screens/pack_compilation_screen.dart`
- Delete: `lib/features/pack_compilation/widgets/compilation_editor.dart`
- Delete: `lib/features/pack_compilation/widgets/compilation_list.dart`
- Delete: `lib/features/pack_compilation/widgets/compilation_editor_sections.dart` (content migrates into screen)
- Delete: `lib/features/pack_compilation/widgets/compilation_editor_form_widgets.dart` (content migrates into screen)

**Preserved (retokenised as needed):** `CompilationProjectSelectionSection` (project list with checkboxes), `ConflictingProjectsPanel`, `CompilationBBCodeSection`, `CompilationProgressSection`, `LogTerminal` (imported from `translation_editor`), `ProjectConflictsDetailDialog`, `compilation_editor_notifier.dart` (Riverpod notifier, unchanged).

### 5.1 Create the editor screen

- [ ] **Step 1 · Inspect the existing `CompilationEditorNotifier` methods**

```bash
grep -n "^  " lib/features/pack_compilation/providers/compilation_editor_notifier.dart | head -30
```

Note the method signatures: `reset()`, `loadCompilation(details)`, `updateName(String)`, `updatePrefix`, `updatePackName`, `updateLanguage(String? id) async`, `toggleProjectSelection(String id)`, `selectAllProjects(List<Project>)`, `deselectAllProjects()`, `compile() async`, `cancelCompilation()`. The exact names may differ — verify from the actual file.

- [ ] **Step 2 · Read the preserved widgets and their props**

Read these files to understand the props you must supply:
- `lib/features/pack_compilation/widgets/compilation_project_selection.dart`
- `lib/features/pack_compilation/widgets/conflicting_projects_panel.dart`
- `lib/features/pack_compilation/widgets/compilation_bbcode_section.dart`
- `lib/features/translation_editor/screens/progress/progress_widgets.dart` (for `CompilationProgressSection` + `LogTerminal`)

Note: `CompilationProjectSelectionSection` currently expects `state`, `currentGameAsync`, `onToggle`, `onSelectAll`, `onDeselectAll`. Preserve those.

- [ ] **Step 3 · Write the failing test**

Create `test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('new mode renders WizardScreenLayout with empty form',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationEditorScreen(compilationId: null),
      theme: AppTheme.atelierDarkTheme,
      overrides: const <Override>[],
    ));
    await t.pump();
    expect(find.byType(WizardScreenLayout), findsOneWidget);
    expect(find.textContaining('New'), findsWidgets);
  });

  testWidgets('exposes compilationId field', (t) async {
    const screen = PackCompilationEditorScreen(compilationId: 'c-1');
    expect(screen.compilationId, 'c-1');
  });
}
```

- [ ] **Step 4 · Run test to verify failure**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 5 · Implement the editor screen**

Create `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`. The implementation composes `WizardScreenLayout` with:

- `DetailScreenToolbar` crumb `"Publishing › Pack compilation › ${state.isEditing ? state.name : 'New'}"`, onBack `_handleBack`.
- `StickyFormPanel` with 2 `FormSection` (Basics: name, description, language, game · Output: packName, prefix, outputPath), a `SummaryBox` labelled `"WILL GENERATE"` with lines `Filename`/`Projects`/`Target language`/`Conflicts`/`Size estimate`, and actions `Cancel` + `Compile (filled)`.
- `DynamicZonePanel` wrapping an `AnimatedSwitcher` that shows either editing view (project selection + conflicts panel + BBCode) or compiling view (progress + LogTerminal).

Adapt method names to match the actual `CompilationEditorNotifier` surface.

Reference implementation skeleton (adapt imports and method names):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/translation_editor/screens/progress/progress_widgets.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../providers/compilation_conflict_providers.dart';
import '../providers/pack_compilation_providers.dart';
import '../widgets/compilation_bbcode_section.dart';
import '../widgets/compilation_project_selection.dart';
import '../widgets/conflicting_projects_panel.dart';

class PackCompilationEditorScreen extends ConsumerStatefulWidget {
  final String? compilationId;
  const PackCompilationEditorScreen({super.key, required this.compilationId});

  @override
  ConsumerState<PackCompilationEditorScreen> createState() =>
      _PackCompilationEditorScreenState();
}

class _PackCompilationEditorScreenState
    extends ConsumerState<PackCompilationEditorScreen> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _packNameCtl;
  late final TextEditingController _prefixCtl;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController();
    _packNameCtl = TextEditingController();
    _prefixCtl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(compilationEditorProvider.notifier);
      if (widget.compilationId == null) {
        notifier.reset();
      } else {
        final list =
            await ref.read(compilationsWithDetailsProvider.future);
        final target = list.firstWhere(
          (c) => c.compilation.id == widget.compilationId,
          orElse: () => throw StateError('Compilation ${widget.compilationId} not found'),
        );
        notifier.loadCompilation(target);
      }
      // Sync controllers to state
      final s = ref.read(compilationEditorProvider);
      _nameCtl.text = s.name;
      _packNameCtl.text = s.packName;
      _prefixCtl.text = s.prefix;
    });
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _packNameCtl.dispose();
    _prefixCtl.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (ref.read(compilationEditorProvider).isCompiling) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compilationEditorProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final currentGameAsync = ref.watch(currentGameInstallationProvider);
    final conflictsAsync = state.selectedProjectIds.length >= 2 &&
            state.selectedLanguageId != null
        ? ref.watch(compilationConflictsProvider)       // adapt exact name
        : const AsyncValue<ConflictAnalysisResult?>.data(null);
    final notifier = ref.read(compilationEditorProvider.notifier);

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        crumb: state.isEditing
            ? 'Publishing › Pack compilation › ${state.name.isEmpty ? "Untitled" : state.name}'
            : 'Publishing › Pack compilation › New',
        onBack: _handleBack,
      ),
      formPanel: StickyFormPanel(
        sections: [
          FormSection(
            label: 'Basics',
            children: [
              TextField(
                controller: _nameCtl,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: notifier.updateName,
              ),
              // Language dropdown (bind to state.selectedLanguageId, languagesAsync)
              // Prefix TextField bound to _prefixCtl + notifier.updatePrefix
            ],
          ),
          FormSection(
            label: 'Output',
            children: [
              TextField(
                controller: _packNameCtl,
                decoration: const InputDecoration(labelText: 'Pack filename'),
                onChanged: notifier.updatePackName,
              ),
              // (Optional) output path picker
            ],
          ),
        ],
        summary: SummaryBox(
          label: 'Will generate',
          semantics: _summarySemantics(conflictsAsync),
          lines: _summaryLines(state, conflictsAsync, languagesAsync.asData?.value ?? const []),
        ),
        actions: [
          SmallTextButton(
            label: 'Cancel',
            onTap: state.isCompiling ? null : () => context.pop(),
          ),
          SmallTextButton(
            label: state.isCompiling ? 'Compiling…' : 'Compile',
            icon: FluentIcons.play_24_regular,
            onTap: state.isCompiling || !_canCompile(state)
                ? null
                : () => notifier.compile(),
          ),
        ],
      ),
      dynamicZone: DynamicZonePanel(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: state.isCompiling
              ? _CompilingView(
                  key: const ValueKey('compiling'),
                  onStop: () => notifier.cancelCompilation(),
                )
              : _EditingView(
                  key: const ValueKey('editing'),
                  state: state,
                  currentGameAsync: currentGameAsync,
                  conflictsAsync: conflictsAsync,
                  onToggle: notifier.toggleProjectSelection,
                  onSelectAll: (projects) => notifier.selectAllProjects(projects),
                  onDeselectAll: notifier.deselectAllProjects,
                ),
        ),
      ),
    );
  }

  bool _canCompile(CompilationEditorState s) =>
      s.name.isNotEmpty &&
      s.packName.isNotEmpty &&
      s.selectedLanguageId != null &&
      s.selectedProjectIds.isNotEmpty;

  SummarySemantics _summarySemantics(AsyncValue<ConflictAnalysisResult?> c) {
    final count = c.asData?.value?.conflicts.length ?? 0;
    return count > 0 ? SummarySemantics.warn : SummarySemantics.accent;
  }

  List<SummaryLine> _summaryLines(
    CompilationEditorState state,
    AsyncValue<ConflictAnalysisResult?> conflicts,
    List<dynamic> languages,  // Language list
  ) {
    final langName = languages.isEmpty
        ? '—'
        : (languages.firstWhere(
              (l) => l.id == state.selectedLanguageId,
              orElse: () => null,
            )?.name ?? '—');
    final conflictCount = conflicts.asData?.value?.conflicts.length ?? 0;
    return [
      SummaryLine(key: 'Filename', value: state.packName.isEmpty ? '—' : state.packName),
      SummaryLine(key: 'Projects', value: '${state.selectedProjectIds.length} selected'),
      SummaryLine(key: 'Target language', value: langName),
      SummaryLine(
        key: 'Conflicts',
        value: conflictCount > 0 ? '$conflictCount ⚠' : 'None',
        semantics: conflictCount > 0 ? SummarySemantics.warn : SummarySemantics.ok,
      ),
    ];
  }
}

class _EditingView extends StatelessWidget {
  final CompilationEditorState state;
  final AsyncValue currentGameAsync;
  final AsyncValue<ConflictAnalysisResult?> conflictsAsync;
  final Function(String) onToggle;
  final Function(List) onSelectAll;
  final VoidCallback onDeselectAll;

  const _EditingView({
    super.key,
    required this.state,
    required this.currentGameAsync,
    required this.conflictsAsync,
    required this.onToggle,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  @override
  Widget build(BuildContext context) {
    final showConflicts = state.selectedProjectIds.length >= 2 &&
        state.selectedLanguageId != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            onToggle: onToggle,
            onSelectAll: onSelectAll,
            onDeselectAll: onDeselectAll,
          ),
          if (showConflicts)
            const ConflictingProjectsPanel(),
          if (state.lastBBCode != null)                 // check actual property name
            CompilationBBCodeSection(state: state),
        ],
      ),
    );
  }
}

class _CompilingView extends StatelessWidget {
  final VoidCallback onStop;
  const _CompilingView({super.key, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CompilationProgressSection(onStop: onStop),     // adapt props
        const SizedBox(height: 12),
        const Expanded(child: LogTerminal(expand: true)),
      ],
    );
  }
}
```

The skeleton contains placeholders for fields you'll adapt based on actual notifier API and model shape. Open each preserved widget / notifier and wire the props correctly.

- [ ] **Step 6 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/pack_compilation/
```

Fix any compile errors. Expected outcome: analyzer clean after wiring.

- [ ] **Step 7 · Run the widget test**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart
```

Expected: both tests PASS.

- [ ] **Step 8 · Swap the router**

Open `lib/config/router/app_router.dart`. Add the import:

```dart
import '../../features/pack_compilation/screens/pack_compilation_editor_screen.dart';
```

Replace the two `child: const PackCompilationScreen(),` occurrences under `new` / `:compilationId/edit` with:

```dart
// new route
child: const PackCompilationEditorScreen(compilationId: null),

// edit route
child: PackCompilationEditorScreen(
  compilationId: state.pathParameters[AppRoutes.compilationIdParam]!,
),
```

Remove the original `packCompilation` import `import '../../features/pack_compilation/screens/pack_compilation_screen.dart';` (no longer needed).

- [ ] **Step 9 · Delete obsolete files**

```bash
git rm lib/features/pack_compilation/screens/pack_compilation_screen.dart
git rm lib/features/pack_compilation/widgets/compilation_editor.dart
git rm lib/features/pack_compilation/widgets/compilation_list.dart
git rm lib/features/pack_compilation/widgets/compilation_editor_sections.dart
git rm lib/features/pack_compilation/widgets/compilation_editor_form_widgets.dart
```

- [ ] **Step 10 · Delete or adapt orphan tests**

```bash
# Inspect which tests reference the deleted files
grep -rln "pack_compilation_screen\|compilation_editor\.dart\|compilation_list\|compilation_editor_sections\|compilation_editor_form_widgets" test/ || true
```

For each match, either delete the test file (if its target is deleted) or adapt the import to the new screen/widgets.

- [ ] **Step 11 · Run full pack compilation test suite**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/
```

Expected: all tests PASS.

- [ ] **Step 12 · Generate goldens**

Create `test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationEditorScreen(compilationId: null),
      theme: theme,
    ));
    await t.pumpAndSettle();
  }

  testWidgets('pack compilation editor atelier empty form', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(PackCompilationEditorScreen),
      matchesGoldenFile('../goldens/pack_compilation_editor_atelier.png'),
    );
  });

  testWidgets('pack compilation editor forge empty form', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(PackCompilationEditorScreen),
      matchesGoldenFile('../goldens/pack_compilation_editor_forge.png'),
    );
  });
}
```

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart
```

Expected: 2 new PNG files.

- [ ] **Step 13 · Re-run goldens for stability**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart
```

Expected: PASS.

- [ ] **Step 14 · Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart \
        lib/config/router/app_router.dart \
        test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart \
        test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart \
        test/features/pack_compilation/goldens/pack_compilation_editor_atelier.png \
        test/features/pack_compilation/goldens/pack_compilation_editor_forge.png
git add -u   # deletes staged
git commit -m "refactor: migrate Pack Compilation editor to §7.5 archetype"
```

---

## Task 6 · Workshop Publish single screen (§7.5)

**Files:**
- Rewrite: `lib/features/steam_publish/screens/workshop_publish_screen.dart`
- Create: `test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart`
- Modify: `test/features/steam_publish/screens/workshop_publish_screen_test.dart` (adapt to new structure)

Preserves `WorkshopPublishNotifier`, `WorkshopPublishSettingsDialog`, `SteamGuardDialog`, `SteamLoginDialog`, `SteamCmdInstallDialog` dialogs, `PublishableItem` DTO.

- [ ] **Step 1 · Inspect current screen and notifier API**

Read:
- `lib/features/steam_publish/screens/workshop_publish_screen.dart` (full)
- `lib/features/steam_publish/providers/workshop_publish_notifier.dart` (full)

Note the notifier state shape (`phase`, progress, logs, etc.) and the form fields (title, description, visibility, change notes).

- [ ] **Step 2 · Write the failing widget test**

Modify `test/features/steam_publish/screens/workshop_publish_screen_test.dart` (or create if absent). Minimal structural test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders WizardScreenLayout skeleton', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createTestableWidget(
      const WorkshopPublishScreen(),
    ));
    await t.pump();
    // The screen may guard on staging data — accept either WizardScreenLayout or empty Material
    expect(
      find.byType(WizardScreenLayout).evaluate().isNotEmpty ||
          find.text('No pack staged').evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
      isTrue,
    );
  });
}
```

- [ ] **Step 3 · Run it (red state)**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/workshop_publish_screen_test.dart
```

Expected: current screen uses `FluentScaffold`, not `WizardScreenLayout`. Test will fail.

- [ ] **Step 4 · Rewrite the screen**

Rewrite `lib/features/steam_publish/screens/workshop_publish_screen.dart` to compose `WizardScreenLayout`:

- `DetailScreenToolbar` crumb `"Publishing › Steam Workshop › ${item?.projectName ?? ''}"`.
- `StickyFormPanel` with 2 `FormSection`s (Publication: title, description, visibility dropdown, change note · Pack: read-only path, read-only Steam ID if update) + `SummaryBox` with `label: _isUpdate ? "Will update" : "Will publish"` + 2 actions (Cancel, Publish/Update filled).
- `DynamicZonePanel` wrapping `AnimatedSwitcher` keyed on the notifier `phase`:
  - `idle` → `_PublishPreview` (title, description, visibility rendered as the eventual Steam page would show them)
  - `uploading|publishing|processing` → `_PublishProgressView` (phase header + elapsed + `LogTerminal`)
  - `done` → `_PublishResultPanel` (success message + Open in Steam)
  - `failed` → `_PublishErrorPanel` (error + Retry)

Preserve all existing dialog triggers (`_showingSteamGuardDialog`, `_confirmLeaveIfActive`, SteamCmd install prompts) and the `WorkshopPublishNotifier` consumption pattern. The key structural change: the screen **always** renders `WizardScreenLayout`, never swaps to a different widget tree for progress.

For the controllers: `TextEditingController`s for title/description/changeNote — keep them at `State` level so they don't re-init on phase switch. Use `ref.listen` on the notifier to trigger navigation after `done` if needed (or render the result panel until user dismisses).

Expected LOC after rewrite: ~450-550 LOC (vs 821 currently; simpler structure).

- [ ] **Step 5 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/steam_publish/screens/workshop_publish_screen.dart
```

Fix compile errors.

- [ ] **Step 6 · Run tests**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/workshop_publish_screen_test.dart
```

Expected: PASS.

- [ ] **Step 7 · Create golden test**

Create `test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  // Stub the publish staging provider with a minimal item
  List<Override> _overrides() => [
        publishStagingProvider.overrideWithValue(
          PublishStagingData(
            /* adapt with minimal fields — see publish_staging_provider.dart */
          ),
        ),
      ];

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const WorkshopPublishScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('workshop publish atelier pre-submit', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(WorkshopPublishScreen),
      matchesGoldenFile('../goldens/workshop_publish_atelier.png'),
    );
  });

  testWidgets('workshop publish forge pre-submit', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(WorkshopPublishScreen),
      matchesGoldenFile('../goldens/workshop_publish_forge.png'),
    );
  });
}
```

Inspect `publish_staging_provider.dart` for the exact `PublishStagingData` fields (or whichever shape the provider uses) and fill in valid sample data.

- [ ] **Step 8 · Generate goldens**

```bash
mkdir -p test/features/steam_publish/goldens
C:/src/flutter/bin/flutter test --update-goldens test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart
```

- [ ] **Step 9 · Verify goldens stable**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart
```

- [ ] **Step 10 · Commit**

```bash
git add lib/features/steam_publish/screens/workshop_publish_screen.dart \
        test/features/steam_publish/screens/workshop_publish_screen_test.dart \
        test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart \
        test/features/steam_publish/goldens/workshop_publish_atelier.png \
        test/features/steam_publish/goldens/workshop_publish_forge.png
git commit -m "refactor: migrate Workshop Publish single to §7.5 archetype"
```

---

## Task 7 · Workshop Publish batch screen (§7.5 dégénéré)

**Files:**
- Rewrite: `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart`
- Modify: `test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart` (adapt)
- Create: `test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart`

Preserves `BatchWorkshopPublishNotifier` timing (`initState + addPostFrameCallback` → `publishBatch`).

- [ ] **Step 1 · Inspect current screen**

Read `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart` and `batch_workshop_publish_notifier.dart` in full.

- [ ] **Step 2 · Write the failing test**

Update `test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders WizardScreenLayout skeleton', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createTestableWidget(
      const BatchWorkshopPublishScreen(),
    ));
    await t.pump();
    expect(find.byType(WizardScreenLayout), findsOneWidget);
  });
}
```

- [ ] **Step 3 · Rewrite the screen**

Rewrite `batch_workshop_publish_screen.dart` to compose `WizardScreenLayout`:

- `DetailScreenToolbar` crumb `"Publishing › Steam Workshop › Batch (${items.length} packs)"`, onBack `_confirmLeaveIfActive`.
- `StickyFormPanel`:
  - `sections`: single `FormSection(label: 'Staging', children: [ ...rows with label+value pairs for Packs, Total size, Publish count, Update count, Account, Elapsed ])`. Rows are `_StagingRow` helpers (inline in the screen: simple `Row` with label + value, matching the style of `StatsRailRow` from Plan 5b but private).
  - `summary: null`.
  - `actions`: if publishing → `SmallTextButton(Stop, danger=true, onTap: _confirmCancel)`. Else → `SmallTextButton(Close, onTap: context.pop)`.
- `DynamicZonePanel` wrapping:
  - `_OverallProgressHeader(completed, total, percent)` at top.
  - `Expanded(ListView.builder(itemCount: items, itemBuilder: _BatchPackRow))` in the middle.
  - `SizedBox(height: 240, child: LogTerminal(expand: false))` at bottom.

Preserve `initState + addPostFrameCallback` publish-batch call. Preserve elapsed timer logic. Preserve `SteamGuardDialog` trigger guard.

Expected LOC after rewrite: ~320-380 LOC (vs 543 currently).

- [ ] **Step 4 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/steam_publish/screens/batch_workshop_publish_screen.dart
```

- [ ] **Step 5 · Run tests**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6 · Create golden test**

Create `test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/batch_workshop_publish_notifier.dart';
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  List<Override> _overrides() => [
        // Override batch staging with a 3-pack fixture (2 done, 1 in progress)
        batchPublishStagingProvider.overrideWithValue(
          BatchPublishStagingData(
            items: /* 3 PublishableItem fixtures */,
            username: 'tester',
            password: '',
            steamGuardCode: null,
          ),
        ),
        // Override batchWorkshopPublishProvider with a state that has 2 completed + 1 uploading
        // (Adapt based on the actual notifier state shape)
      ];

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const BatchWorkshopPublishScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('batch publish atelier in-progress', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(BatchWorkshopPublishScreen),
      matchesGoldenFile('../goldens/batch_workshop_publish_atelier.png'),
    );
  });

  testWidgets('batch publish forge in-progress', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(BatchWorkshopPublishScreen),
      matchesGoldenFile('../goldens/batch_workshop_publish_forge.png'),
    );
  });
}
```

Open `batch_workshop_publish_notifier.dart` for exact state shape and build a fixture that renders in-progress without triggering real steamcmd.

- [ ] **Step 7 · Generate goldens**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart
```

- [ ] **Step 8 · Verify stable**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart
```

- [ ] **Step 9 · Commit**

```bash
git add lib/features/steam_publish/screens/batch_workshop_publish_screen.dart \
        test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart \
        test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart \
        test/features/steam_publish/goldens/batch_workshop_publish_atelier.png \
        test/features/steam_publish/goldens/batch_workshop_publish_forge.png
git commit -m "refactor: migrate Workshop Publish batch to §7.5 archetype"
```

---

## Task 8 · Remove global breadcrumb + final verification

**Files:**
- Modify: `lib/widgets/layouts/main_layout_router.dart` (remove global breadcrumb)

Clôt le follow-up Plan 2 « breadcrumb au niveau écran ».

### 8.1 Remove the global breadcrumb

- [ ] **Step 1 · Locate the breadcrumb usage**

```bash
grep -n "Breadcrumb" lib/widgets/layouts/main_layout_router.dart
```

Note the current structure — the global `Breadcrumb` widget is rendered inside `MainLayoutRouter`, likely conditionally (e.g. hidden on Home).

- [ ] **Step 2 · Verify all screens embed their own toolbar**

Screens that must have a local crumb before removing the global one:
- Home (already hides the global crumb — OK).
- Mods, Projects, Glossary, TM, Steam Publish (Plan 5a migrated lists — they have `ListToolbarLeading` which acts as the crumb).
- Project Detail, Glossary Detail (Plan 5b — have `DetailScreenToolbar`).
- Game Files (Game Translation) — **verify**. If no local crumb, add a minimal one or defer removal.
- Settings, Help — **verify**. If no local crumb, add a minimal one or defer removal.
- Pack Compilation list + editor (Plan 5c — both have toolbars).
- Workshop Publish single + batch (Plan 5c — both have `DetailScreenToolbar`).

```bash
grep -rln "MainLayoutRouter" lib/widgets/layouts/
```

- [ ] **Step 3 · Edit `main_layout_router.dart`**

Remove the `Breadcrumb` widget and the associated padding/column wrapper. Keep the shell structure (navigation sidebar + content area).

Example edit (adapt to actual file):

```dart
// BEFORE:
// Column([Breadcrumb(...), Expanded(child)])

// AFTER:
// child
```

If some screens still rely on the global breadcrumb as the only source of crumb (e.g., Game Files, Settings), **stop and add a local toolbar** to those screens before removing the global one.

### 8.2 Final verification

- [ ] **Step 4 · Run `flutter analyze`**

```bash
cd E:/Total-War-Mods-Translator/.worktrees/ui-wizards
C:/src/flutter/bin/flutter analyze
```

Expected: zero new issues beyond the pre-existing 35 (per baseline).

- [ ] **Step 5 · Full test suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: suite green. Target ~1385 passing / 14 failing (pre-existing). All new primitives + screens pass.

If unexpected failures, inspect:
1. Goldens may have drifted on screens indirectly affected by the global crumb removal (if any screen was relying on it). Re-generate only if the drift is expected.
2. Route tests may need updates if paths changed.

- [ ] **Step 6 · Manual smoke test (optional but recommended)**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Navigate through:
- `/publishing/pack` — list, search, "+ New" button.
- `/publishing/pack/new` — editor empty state, fill form, select projects, verify summary updates live, click Compile.
- `/publishing/pack/:id/edit` — load existing compilation, re-edit, re-compile.
- `/publishing/steam/single` via Steam Publish list → select a pack → Publish. Verify preview, submit, progress, logs, result.
- `/publishing/steam/batch` via Steam Publish list → batch select + Publish.
- Verify Project Detail + Glossary Detail still render correctly (no `DetailScreenToolbar` regression).

Close the app.

- [ ] **Step 7 · Commit the global crumb removal**

```bash
git add lib/widgets/layouts/main_layout_router.dart
git commit -m "chore: remove global breadcrumb (all screens embed their own)"
```

---

## Spec coverage check (self-review)

| Spec requirement | Task |
|---|---|
| §2 decision #1 (scope 3+1 screens) | Tasks 4, 5, 6, 7 |
| §2 decision #2 (Workshop Publish mode transition) | Task 6 (AnimatedSwitcher on dynamic zone) |
| §2 decision #3 (Pack Compilation route split) | Tasks 3, 4, 5 |
| §2 decision #4 (primitives composables) | Tasks 1, 2 |
| §2 decision #5 (Batch Publish §7.5 degenerate) | Task 7 |
| §2 decision #6 (DetailScreenToolbar extraction) | Task 1 |
| §2 decision #7 (global crumb cleanup) | Task 8 |
| §4 primitives (6 total) | Tasks 1, 2 |
| §5.1 Pack Compilation list layout | Task 4 |
| §5.2 Pack Compilation editor layout | Task 5 |
| §5.3 Workshop Publish single layout | Task 6 |
| §5.4 Workshop Publish batch layout | Task 7 |
| §5.5 Project/Glossary Detail migration | Task 1 |
| §6 widget tests primitives (~15) | Tasks 1, 2 |
| §6 widget tests screens (~15) | Tasks 4, 5, 6, 7 |
| §6 goldens (8) | Tasks 4, 5, 6, 7 |
| §7.1 Worktree setup | pre-Task 1 |
| §7.2 Task order séquentiel | Tasks 1-8 |
| §7.3 Conventions (anglais, tokens) | rappelé dans chaque task |
| §8 Risques — Route split Pack | Task 5 Step 5 (initState loads/resets) |
| §8 Risques — Workshop Publish sticky form | Task 6 Step 4 (controllers at State level) |
| §8 Risques — Batch Publish notifier timing | Task 7 Step 3 (preserve addPostFrameCallback) |
| §8 Risques — DetailScreenToolbar golden drift | Task 1 Step 6 (check byte-identical) |
| §8 Risques — DashedBorder | Task 2 Step 7 (CustomPainter home-made) |
| §8 Risques — Crumb global cleanup | Task 8 Step 2 (verify all screens before removing) |
| §9 Follow-ups déférés | explicitly noted |
| §10 Open Q1 DashedBorder impl | Task 2 Step 7 (CustomPainter, ~60 LOC) |
| §10 Open Q2 _StagingRow | Task 7 Step 3 (inline private helper) |
| §10 Open Q3 Route parameter parsing | Task 3 Step 2 (path patterns distincts) |
| §10 Open Q4 AnimatedSwitcher duration | Task 5 / Task 6 (200ms) |
| §10 Open Q5 FormSection helpText position | Task 2 Step 3 (sous le label) |
