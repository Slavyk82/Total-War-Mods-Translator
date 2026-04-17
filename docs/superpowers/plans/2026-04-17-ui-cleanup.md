# Plan 5d · Cleanup & retokenization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clôture du redesign UI (hors Settings) — extraire 3 form primitives partagées, retokéniser β les 2 dialogs multi-step (Game Translation + New Project) et le Help screen, absorber 4 follow-ups Plan 5c.

**Architecture:** 3 nouveaux widgets publics dans `lib/widgets/wizard/` (`TokenTextField`, `LabeledField`, `ReadonlyField`). Workshop Publish screens passent de classes privées à import des primitives. Dialog + Help screens consomment ces primitives + `SmallTextButton`/`SmallIconButton` + tokens partout. 5c follow-ups : `ref.listen` remplace `Future.delayed(100ms)` x3 dans pack editor + controller sync hors de `build` + narrow try/catch + `@visibleForTesting` sur staging notifiers.

**Tech Stack:** Flutter Desktop Windows · Riverpod 3 · GoRouter · `flutter_test` goldens.

**Spec:** [`docs/superpowers/specs/2026-04-17-ui-cleanup-design.md`](../specs/2026-04-17-ui-cleanup-design.md)

**Predecessors (shipped on main):** Plans 1, 2, 3, 4, 5a, 5b, 5c.

---

## File Structure

### New primitives (Task 1)

- `lib/widgets/wizard/token_text_field.dart` — TextField with token theme + focus accent
- `lib/widgets/wizard/labeled_field.dart` — label caps-mono above an arbitrary child widget
- `lib/widgets/wizard/readonly_field.dart` — labelled read-only value box (font-mono)

### Modified files (Task 1)

- `lib/features/steam_publish/screens/workshop_publish_screen.dart` — delete `_LabeledField`, `_TokenTextField`, `_ReadonlyField` private classes; import public primitives
- `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart` — idem if any use exists

### Modified files (Task 2)

- `lib/features/steam_publish/screens/workshop_publish_screen.dart` — narrow `try/catch` in `_loadTemplates` and `dispose`
- `lib/features/steam_publish/providers/publish_staging_provider.dart` — add `@visibleForTesting` annotations to the 2 public notifier classes

### Modified files (Task 3)

- `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` — replace 3 `Future.delayed(100ms)` with `ref.listen` on `compilationEditorProvider.select((s) => ...)` ; replace in-build controller sync with `ref.listenManual` in `initState`

### Modified files (Task 4)

- `lib/features/help/screens/help_screen.dart` — drop `FluentScaffold`, retoken header
- `lib/features/help/widgets/help_section_content.dart` — tokens partout
- `lib/features/help/widgets/help_toc_sidebar.dart` — tokens partout

### Modified files (Task 5)

- `lib/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart` — AlertDialog body retokenised + `_StepHeader` + `SmallTextButton` actions
- `lib/features/game_translation/widgets/create_game_translation/step_select_source.dart` — tokens + `TokenTextField`
- `lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart` — tokens
- `lib/features/game_translation/widgets/create_game_translation/add_language_wizard_dialog.dart` — tokens

### Modified files (Task 6)

- `lib/features/projects/widgets/create_project/create_project_dialog.dart` — AlertDialog body retokenised + `_StepHeader` + `SmallTextButton` actions
- `lib/features/projects/widgets/create_project/step_basic_info.dart` — tokens + `TokenTextField`
- `lib/features/projects/widgets/create_project/step_languages.dart` — tokens
- `lib/features/projects/widgets/create_project/step_settings.dart` — tokens

### New test files

- `test/widgets/wizard/token_text_field_test.dart`
- `test/widgets/wizard/labeled_field_test.dart`
- `test/widgets/wizard/readonly_field_test.dart`
- `test/features/help/screens/help_screen_golden_test.dart` (2 goldens)
- `test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart` (2 goldens)
- `test/features/projects/widgets/create_project_dialog_golden_test.dart` (2 goldens)

### Goldens to verify byte-identical

- `test/features/steam_publish/goldens/workshop_publish_atelier.png` + `workshop_publish_forge.png`
- `test/features/steam_publish/goldens/batch_workshop_publish_atelier.png` + `batch_workshop_publish_forge.png`

### Goldens that may drift (regen if justified)

- `test/features/pack_compilation/goldens/pack_compilation_editor_atelier.png` + `pack_compilation_editor_forge.png` — only 1-frame timing change, content identical

---

## Worktree setup (pre-Task 1)

- [ ] **Create worktree & branch**

```bash
cd /e/Total-War-Mods-Translator
git worktree add .worktrees/ui-cleanup -b feat/ui-cleanup main
cd .worktrees/ui-cleanup
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

Expected: ~1318 passing / 14 pre-existing failures (SidebarUpdateChecker overflows per memory).

---

## Task 1 · Extract form primitives + migrate Workshop Publish screens

**Files:**
- Create: `lib/widgets/wizard/token_text_field.dart`
- Create: `lib/widgets/wizard/labeled_field.dart`
- Create: `lib/widgets/wizard/readonly_field.dart`
- Test: `test/widgets/wizard/token_text_field_test.dart`
- Test: `test/widgets/wizard/labeled_field_test.dart`
- Test: `test/widgets/wizard/readonly_field_test.dart`
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart`
- Modify (if applicable): `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart`

### 1.1 `LabeledField`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/wizard/labeled_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders label + child', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'Title',
      child: Text('field-widget'),
    )));
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('field-widget'), findsOneWidget);
  });

  testWidgets('label uses fontBody 11 textDim w500', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'T',
      child: SizedBox.shrink(),
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('T'));
    expect(text.style?.fontSize, 11);
    expect(text.style?.color, tokens.textDim);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('renders without a label crash when child is empty', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'X',
      child: SizedBox.shrink(),
    )));
    expect(find.text('X'), findsOneWidget);
  });
}
```

- [ ] **Step 2 · Run test (red)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/labeled_field_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 3 · Implement `LabeledField`**

Create `lib/widgets/wizard/labeled_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Label + child pair used inside wizard forms (§7.5).
///
/// Renders a token-themed body-font label above an arbitrary [child] widget
/// (typically a [TokenTextField], dropdown, or other input). Keeps the label
/// typography consistent across dialogs, Workshop Publish screens, and
/// Pack Compilation editor.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
```

- [ ] **Step 4 · Run test (green)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/labeled_field_test.dart
```

Expected: 3/3 PASS.

### 1.2 `TokenTextField`

- [ ] **Step 5 · Write failing test**

Create `test/widgets/wizard/token_text_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders TextField with hint', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: 'Type here…',
      enabled: true,
    )));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Type here…'), findsOneWidget);
  });

  testWidgets('onChanged fires on input', (t) async {
    String? captured;
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: '',
      enabled: true,
      onChanged: (v) => captured = v,
    )));
    await t.enterText(find.byType(TextField), 'abc');
    expect(captured, 'abc');
  });

  testWidgets('disabled renders with disabled border', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: '',
      enabled: false,
    )));
    final tf = t.widget<TextField>(find.byType(TextField));
    expect(tf.enabled, isFalse);
  });
}
```

- [ ] **Step 6 · Run test (red)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/token_text_field_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 7 · Implement `TokenTextField`**

Create `lib/widgets/wizard/token_text_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Token-themed text field used inside wizard forms (§7.5).
///
/// Panel2 fill, border outline, accent focus, font-body 13px text,
/// text-faint placeholder. Extracted from Workshop Publish private classes
/// so Game Translation / New Project dialogs share the same input style.
class TokenTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  const TokenTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.enabled,
    this.maxLines = 1,
    this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 2 : 1,
      focusNode: focusNode,
      style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: tokens.panel2,
        hintText: hint,
        hintStyle: tokens.fontBody.copyWith(
          fontSize: 13,
          color: tokens.textFaint,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.accent),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide:
              BorderSide(color: tokens.border.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8 · Run test (green)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/token_text_field_test.dart
```

Expected: 3/3 PASS.

### 1.3 `ReadonlyField`

- [ ] **Step 9 · Write failing test**

Create `test/widgets/wizard/readonly_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/readonly_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders label + value', (t) async {
    await t.pumpWidget(wrap(const ReadonlyField(
      label: 'Pack path',
      value: 'C:/data/foo.pack',
    )));
    expect(find.text('Pack path'), findsOneWidget);
    expect(find.text('C:/data/foo.pack'), findsOneWidget);
  });

  testWidgets('empty value renders em-dash', (t) async {
    await t.pumpWidget(wrap(const ReadonlyField(
      label: 'L',
      value: '',
    )));
    expect(find.text('—'), findsOneWidget);
  });
}
```

- [ ] **Step 10 · Run test (red)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/readonly_field_test.dart
```

Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 11 · Implement `ReadonlyField`**

Create `lib/widgets/wizard/readonly_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Token-themed read-only value box used inside wizard forms (§7.5).
///
/// Label via body-font, value via mono-font on a panel2 container with
/// border. Renders em-dash when [value] is empty. Extracted from Workshop
/// Publish private classes so Game Translation / New Project dialogs share
/// the same read-only style.
class ReadonlyField extends StatelessWidget {
  final String label;
  final String value;

  const ReadonlyField({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            value.isEmpty ? '—' : value,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textMid,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 12 · Run test (green)**

```bash
C:/src/flutter/bin/flutter test test/widgets/wizard/readonly_field_test.dart
```

Expected: 2/2 PASS.

### 1.4 Migrate Workshop Publish single

- [ ] **Step 13 · Replace private classes with imports**

Open `lib/features/steam_publish/screens/workshop_publish_screen.dart`. At the top, add imports:

```dart
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import 'package:twmt/widgets/wizard/readonly_field.dart';
```

Replace `_LabeledField(...)` with `LabeledField(...)`, `_TokenTextField(...)` with `TokenTextField(...)`, `_ReadonlyField(...)` with `ReadonlyField(...)`. The constructors match 1-to-1 (already verified same fields).

Delete the 3 private class definitions at the bottom of the file (lines ~1098-1224 — `_LabeledField`, `_TokenTextField`, `_ReadonlyField`).

- [ ] **Step 14 · Check batch screen for same private classes**

```bash
grep -n "_LabeledField\|_TokenTextField\|_ReadonlyField" lib/features/steam_publish/screens/batch_workshop_publish_screen.dart
```

If matches exist, apply the same replacement pattern (imports + rename). If none, skip.

- [ ] **Step 15 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/steam_publish/ lib/widgets/wizard/
```

Expected: no new issues.

- [ ] **Step 16 · Run Workshop Publish tests + verify goldens byte-identical**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/workshop_publish_screen_test.dart test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart test/features/steam_publish/screens/batch_workshop_publish_screen_golden_test.dart
```

Expected: all PASS without `--update-goldens`. If goldens drift, the extraction changed rendering somewhere — investigate before regenerating.

- [ ] **Step 17 · Commit**

```bash
cd E:/Total-War-Mods-Translator/.worktrees/ui-cleanup
git add lib/widgets/wizard/ test/widgets/wizard/ \
        lib/features/steam_publish/screens/workshop_publish_screen.dart \
        lib/features/steam_publish/screens/batch_workshop_publish_screen.dart
git commit -m "feat: extract TokenTextField, LabeledField, ReadonlyField wizard primitives"
```

---

## Task 2 · 5c follow-ups P3 + P4 (narrow try/catch + @visibleForTesting)

**Files:**
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart`
- Modify: `lib/features/steam_publish/providers/publish_staging_provider.dart`

### 2.1 P3 — narrow try/catch

- [ ] **Step 1 · Inspect current `_loadTemplates` and `dispose`**

```bash
grep -n "_loadTemplates\|silentCleanup" lib/features/steam_publish/screens/workshop_publish_screen.dart
```

Locate the try/catch blocks. Current state swallows all exceptions.

- [ ] **Step 2 · Narrow `_loadTemplates`**

Replace the body of `_loadTemplates`:

```dart
Future<void> _loadTemplates() async {
  try {
    final settings = ref.read(settingsServiceProvider);
    final titleTemplate = await settings.getString('workshop_default_title');
    final descTemplate = await settings.getString('workshop_default_description');
    if (!mounted) return;
    setState(() {
      if (titleTemplate != null && _titleController.text.isEmpty) {
        _titleController.text = titleTemplate;
      }
      if (descTemplate != null && _descriptionController.text.isEmpty) {
        _descriptionController.text = descTemplate;
      }
    });
  } on StateError catch (e) {
    debugPrint('[WorkshopPublish] Settings unavailable: $e');
  }
}
```

**Important**: the existing `_loadTemplates` may have a different inner body — preserve whatever logic was there, just replace `catch (_) {}` with the `on StateError` clause + `debugPrint`. Adapt field/method names to the actual source. `ProviderException` is not always thrown; `StateError` is the typical failure mode when Riverpod can't resolve a provider dependency.

Add import at top of file (if not already present):

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 3 · Narrow `dispose`**

Replace the dispose body's cleanup section:

```dart
@override
void dispose() {
  _elapsedTimer?.cancel();
  _titleController.dispose();
  _descriptionController.dispose();
  _changeNoteController.dispose();
  _outputScrollController.dispose();
  try {
    _publishNotifier.silentCleanup();
  } on StateError catch (e) {
    debugPrint('[WorkshopPublish] silentCleanup state error: $e');
  }
  super.dispose();
}
```

Preserve any additional disposal logic that was there (other timers, controllers, etc.) — only narrow the try/catch around `silentCleanup`.

- [ ] **Step 4 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/steam_publish/screens/workshop_publish_screen.dart
```

Expected: no new issues. `debugPrint` is imported.

- [ ] **Step 5 · Run Workshop Publish tests**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/screens/workshop_publish_screen_test.dart test/features/steam_publish/screens/workshop_publish_screen_golden_test.dart
```

Expected: all PASS. Debug prints may appear in test output — acceptable.

### 2.2 P4 — @visibleForTesting annotations

- [ ] **Step 6 · Add annotations**

Open `lib/features/steam_publish/providers/publish_staging_provider.dart`. Add at top:

```dart
import 'package:flutter/foundation.dart';
```

Find the 2 public notifier classes (`SinglePublishStagingNotifier` and `BatchPublishStagingNotifier`) and add the annotation directly above each class declaration:

```dart
@visibleForTesting
class SinglePublishStagingNotifier extends Notifier<...> {
  // ... existing body
}

@visibleForTesting
class BatchPublishStagingNotifier extends Notifier<...> {
  // ... existing body
}
```

- [ ] **Step 7 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/steam_publish/providers/publish_staging_provider.dart
```

Expected: no new issues. Existing golden-test subclass usage inside `test/` directory is still allowed under `@visibleForTesting`.

- [ ] **Step 8 · Run full steam_publish suite**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/
```

Expected: all PASS.

- [ ] **Step 9 · Commit**

```bash
git add lib/features/steam_publish/
git commit -m "chore: narrow try/catch + add visibleForTesting to staging notifiers"
```

---

## Task 3 · 5c follow-ups P1 + P2 (pack editor ref.listen refactors)

**Files:**
- Modify: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`

### 3.1 P1 — remove Future.delayed(100ms) race

- [ ] **Step 1 · Inspect current `onToggle` / `onSelectAll` / `onDeselectAll` handlers**

```bash
grep -n "Future.delayed\|compilationConflictAnalysisProvider" lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
```

Locate the 3 sites (approximately lines 346, 367, 401) where `Future.delayed(const Duration(milliseconds: 100), () {...})` triggers `analyze` or `clear` on the conflict provider.

- [ ] **Step 2 · Add `ref.listen` at top of `build`**

Inside the screen's `build` method, before the existing `state = ref.watch(compilationEditorProvider)` line, add:

```dart
// Auto-trigger / clear conflict analysis when project selection or language
// changes. Replaces the prior Future.delayed(100ms) dance in onToggle/
// onSelectAll/onDeselectAll — state is already settled by the time the
// listener fires.
ref.listen<({Set<String> ids, String? langId})>(
  compilationEditorProvider.select(
    (s) => (ids: s.selectedProjectIds, langId: s.selectedLanguageId),
  ),
  (previous, next) {
    if (next.ids.length >= 2 && next.langId != null) {
      ref.read(compilationConflictAnalysisProvider.notifier).analyze(
            projectIds: next.ids.toList(),
            languageId: next.langId!,
          );
    } else {
      ref.read(compilationConflictAnalysisProvider.notifier).clear();
    }
  },
);
```

Adapt the `analyze` call signature to match the actual `compilationConflictAnalysisProvider.notifier` API — inspect the notifier file if needed:

```bash
grep -n "void analyze\|void clear\|Future<.*> analyze" lib/features/pack_compilation/providers/compilation_conflict_providers.dart
```

- [ ] **Step 3 · Remove the 3 `Future.delayed` calls in `_EditingView`'s `onToggle`/`onSelectAll`/`onDeselectAll`**

Example: before

```dart
onToggle: (id) {
  notifier.toggleProject(id);
  Future.delayed(const Duration(milliseconds: 100), () {
    final state = ref.read(compilationEditorProvider);
    if (state.selectedProjectIds.length >= 2 && state.selectedLanguageId != null) {
      ref.read(compilationConflictAnalysisProvider.notifier).analyze(...);
    }
  });
},
```

After:

```dart
onToggle: (id) => notifier.toggleProject(id),
```

Same simplification for `onSelectAll` and `onDeselectAll` — just delegate to the notifier without the post-delay analyze trigger.

### 3.2 P2 — controller sync via ref.listenManual

- [ ] **Step 4 · Inspect current controller sync in `build`**

```bash
grep -n "_nameCtl\|_packNameCtl\|_prefixCtl" lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
```

Find the block in `build` that mutates the controllers if `state.X != _ctl.text`.

- [ ] **Step 5 · Move sync logic to `initState` via `ref.listenManual`**

In `initState`, after the controllers are created (but before the post-frame callback), add:

```dart
// Keep text controllers in sync with external state mutations
// (loadCompilation, updateLanguage auto-fills prefix, etc.) without
// re-running on every rebuild.
ref.listenManual<CompilationEditorState>(
  compilationEditorProvider,
  (previous, next) {
    if (previous?.name != next.name && _nameCtl.text != next.name) {
      _nameCtl.text = next.name;
    }
    if (previous?.packName != next.packName && _packNameCtl.text != next.packName) {
      _packNameCtl.text = next.packName;
    }
    if (previous?.prefix != next.prefix && _prefixCtl.text != next.prefix) {
      _prefixCtl.text = next.prefix;
    }
  },
);
```

- [ ] **Step 6 · Remove the in-build sync block**

Find and delete the block inside `build` that previously handled controller sync (typically something like):

```dart
if (state.name != _nameCtl.text) {
  _nameCtl.value = _nameCtl.value.copyWith(text: state.name, selection: ...);
}
// ... similar for _packNameCtl, _prefixCtl
```

- [ ] **Step 7 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
```

Expected: no new issues.

- [ ] **Step 8 · Run pack compilation tests**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/
```

Expected: all PASS. If golden test drifts, the behaviour remains identical but 1-frame timing may differ — inspect the diff first.

- [ ] **Step 9 · Regen golden if drift is timing-only**

If `pack_compilation_editor_atelier.png` or `..._forge.png` drift, compare with previous PNG visually. If the drift is truly a timing change (e.g., conflict panel appears in a different frame but with identical pixels once stable), regen:

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart
C:/src/flutter/bin/flutter test test/features/pack_compilation/screens/pack_compilation_editor_screen_golden_test.dart
```

If the drift is structural (content changed), investigate — likely a regression, not a timing issue.

- [ ] **Step 10 · Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
# if goldens regenerated:
# git add test/features/pack_compilation/goldens/
git commit -m "refactor: replace Future.delayed race with ref.listen in pack editor"
```

---

## Task 4 · Help screen retokenization (β)

**Files:**
- Modify: `lib/features/help/screens/help_screen.dart`
- Modify: `lib/features/help/widgets/help_section_content.dart`
- Modify: `lib/features/help/widgets/help_toc_sidebar.dart`
- Create: `test/features/help/screens/help_screen_golden_test.dart`

### 4.1 Help screen

- [ ] **Step 1 · Read existing screen to understand structure**

```bash
cat lib/features/help/screens/help_screen.dart
```

Note : uses `FluentScaffold`, `_buildHeader` helper with Icon + Text, consumes `helpSectionsProvider` and `selectedSectionIndexProvider`, composes `HelpTocSidebar` + divider + `HelpSectionContent`.

- [ ] **Step 2 · Replace screen with token-themed version**

Overwrite `lib/features/help/screens/help_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../models/help_section.dart';
import '../providers/help_providers.dart';
import '../widgets/help_section_content.dart';
import '../widgets/help_toc_sidebar.dart';

/// Help screen — README documentation split by H2 sections.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sectionsAsync = ref.watch(helpSectionsProvider);
    final selectedIndex = ref.watch(selectedSectionIndexProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HelpHeader(),
          Container(height: 1, color: tokens.border),
          Expanded(
            child: sectionsAsync.when(
              data: (sections) => _buildContent(context, ref, sections, selectedIndex),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _HelpError(error: error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<HelpSection> sections,
    int selectedIndex,
  ) {
    final tokens = context.tokens;
    if (sections.isEmpty) {
      return Center(
        child: Text(
          'No documentation available.',
          style: tokens.fontBody.copyWith(color: tokens.textDim),
        ),
      );
    }
    final validIndex = selectedIndex.clamp(0, sections.length - 1);
    final currentSection = sections[validIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HelpTocSidebar(
          sections: sections,
          selectedIndex: validIndex,
          onSectionSelected: (i) =>
              ref.read(selectedSectionIndexProvider.notifier).select(i),
        ),
        Container(width: 1, color: tokens.border),
        Expanded(
          child: HelpSectionContent(
            key: ValueKey(currentSection.anchor),
            section: currentSection,
            onNavigateToSection: (anchor) {
              final targetIndex = sections.indexWhere((s) => s.anchor == anchor);
              if (targetIndex != -1) {
                ref.read(selectedSectionIndexProvider.notifier).select(targetIndex);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _HelpHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: tokens.panel),
      child: Row(
        children: [
          Icon(
            FluentIcons.question_circle_24_regular,
            size: 28,
            color: tokens.accent,
          ),
          const SizedBox(width: 12),
          Text(
            'Help',
            style: tokens.fontDisplay.copyWith(
              fontSize: 24,
              color: tokens.text,
              fontStyle:
                  tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'documentation',
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textDim,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpError extends StatelessWidget {
  final Object error;
  const _HelpError({required this.error});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load documentation',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4.2 Help TOC sidebar retoken

- [ ] **Step 3 · Read + retoken `help_toc_sidebar.dart`**

```bash
cat lib/features/help/widgets/help_toc_sidebar.dart
```

Replace all `Theme.of(context).colorScheme.xxx` with `context.tokens.xxx` equivalents:
- `colorScheme.surface` / `colorScheme.background` → `tokens.panel`
- `colorScheme.primary` → `tokens.accent`
- `colorScheme.primaryContainer` → `tokens.accentBg`
- `colorScheme.onSurface` / `.onPrimary` → `tokens.text` / `tokens.accent` respectively
- `colorScheme.outline` / `.outlineVariant` → `tokens.border`
- `Colors.xxxxxx` (any hardcoded color) → closest token equivalent

Typography:
- `textTheme.titleSmall` / `.bodyMedium` → `tokens.fontBody.copyWith(fontSize: ..., color: tokens.xxx)`
- Headings in the TOC → `tokens.fontDisplay`

Selected item : bg `tokens.accentBg`, fg `tokens.accent`, optional left border 2px `tokens.accent`.
Hover state : bg `tokens.panel2` (matches 5a/5b convention).

Preserve the widget API (props, callbacks) — only the styling changes.

### 4.3 Help section content retoken

- [ ] **Step 4 · Read + retoken `help_section_content.dart`**

```bash
cat lib/features/help/widgets/help_section_content.dart
```

Same replacements as Step 3 but extra attention to markdown / rich text rendering:
- Body text → `tokens.fontBody` + `tokens.text` / `tokens.textMid`.
- Headings (H1/H2/H3) → `tokens.fontDisplay` with italic-if-Atelier + font sizes 20/16/14.
- Code blocks / inline code → `tokens.fontMono` + `tokens.panel2` container + `tokens.text` text.
- Links → `tokens.accent` color.
- Dividers / borders → `tokens.border`.

Preserve `onNavigateToSection` callback wiring and `key: ValueKey(section.anchor)` identity.

### 4.4 Tests

- [ ] **Step 5 · Run existing help tests**

```bash
C:/src/flutter/bin/flutter test test/features/help/
```

Expected: existing tests still pass (structural refactor).

- [ ] **Step 6 · Create golden test**

Create `test/features/help/screens/help_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/help/models/help_section.dart';
import 'package:twmt/features/help/providers/help_providers.dart';
import 'package:twmt/features/help/screens/help_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

List<HelpSection> _sections() => const [
      HelpSection(
        anchor: 'getting-started',
        title: 'Getting started',
        markdown: '# Getting started\n\nWelcome to the translator.',
      ),
      HelpSection(
        anchor: 'translate-a-mod',
        title: 'Translate a mod',
        markdown: '# Translate a mod\n\nStep-by-step guide.',
      ),
      HelpSection(
        anchor: 'publish',
        title: 'Publish to Workshop',
        markdown: '# Publish\n\nUpload your pack.',
      ),
    ];

List<Override> _overrides() => [
      helpSectionsProvider.overrideWith((_) async => _sections()),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const HelpScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('help atelier', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(HelpScreen),
      matchesGoldenFile('../goldens/help_atelier.png'),
    );
  });

  testWidgets('help forge', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(HelpScreen),
      matchesGoldenFile('../goldens/help_forge.png'),
    );
  });
}
```

If `HelpSection` has a different constructor signature, inspect the model and adapt.

- [ ] **Step 7 · Generate goldens**

```bash
mkdir -p test/features/help/goldens
C:/src/flutter/bin/flutter test --update-goldens test/features/help/screens/help_screen_golden_test.dart
```

- [ ] **Step 8 · Re-run goldens for stability**

```bash
C:/src/flutter/bin/flutter test test/features/help/screens/help_screen_golden_test.dart
```

Expected: PASS.

- [ ] **Step 9 · Commit**

```bash
git add lib/features/help/ \
        test/features/help/screens/help_screen_golden_test.dart \
        test/features/help/goldens/help_atelier.png \
        test/features/help/goldens/help_forge.png
git commit -m "refactor: retokenise Help screen + widgets"
```

---

## Task 5 · Game Translation setup dialog retokenization (β)

**Files:**
- Modify: `lib/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart`
- Modify: `lib/features/game_translation/widgets/create_game_translation/step_select_source.dart`
- Modify: `lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart`
- Modify: `lib/features/game_translation/widgets/create_game_translation/add_language_wizard_dialog.dart`
- Create: `test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart`

### 5.1 Read the dialog + step files

- [ ] **Step 1 · Inspect structure**

```bash
cat lib/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart | head -100
cat lib/features/game_translation/widgets/create_game_translation/step_select_source.dart | head -60
cat lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart | head -60
cat lib/features/game_translation/widgets/create_game_translation/add_language_wizard_dialog.dart | head -60
```

Note : 2-step wizard (source pack, target languages) inside an `AlertDialog`. Step nav via internal `_currentStep` state and `_nextStep`/`_prevStep` methods. Import logs rendered during creation progress.

### 5.2 Retokenise the dialog

- [ ] **Step 2 · Refactor `create_game_translation_dialog.dart`**

Apply:
1. Add imports at top:
   ```dart
   import 'package:twmt/theme/twmt_theme_tokens.dart';
   import 'package:twmt/widgets/lists/small_icon_button.dart';
   import 'package:twmt/widgets/lists/small_text_button.dart';
   ```
2. Replace the `AlertDialog` body container's color with `context.tokens.panel` (use `backgroundColor` param on `AlertDialog` if available, or wrap the body in a `Material(color: tokens.panel)`).
3. Replace all `Theme.of(context).colorScheme.xxx` → `context.tokens.xxx` equivalents throughout the file (use mapping table from Task 4.2).
4. Above the step body, insert a `_StepHeader` widget:
   ```dart
   Container(
     padding: const EdgeInsets.only(bottom: 12),
     decoration: BoxDecoration(
       border: Border(bottom: BorderSide(color: tokens.border)),
     ),
     child: Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Text(
           'STEP ${_currentStep + 1}/2',
           style: tokens.fontMono.copyWith(
             fontSize: 10,
             color: tokens.textDim,
             letterSpacing: 1.2,
             fontWeight: FontWeight.w600,
           ),
         ),
         const SizedBox(height: 4),
         Text(
           _currentStep == 0 ? 'Select source pack' : 'Select target languages',
           style: tokens.fontDisplay.copyWith(
             fontSize: 18,
             color: tokens.text,
             fontStyle:
                 tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
             fontWeight: FontWeight.w500,
           ),
         ),
       ],
     ),
   ),
   ```
5. Replace the footer buttons (Cancel / Back / Next / Create) with `SmallTextButton` widgets:
   ```dart
   actions: [
     if (_currentStep > 0)
       SmallTextButton(
         label: 'Back',
         icon: FluentIcons.arrow_left_24_regular,
         onTap: _isLoading ? null : _prevStep,
       ),
     const Spacer(),
     SmallTextButton(
       label: 'Cancel',
       onTap: _isLoading ? null : () => Navigator.of(context).pop(),
     ),
     SmallTextButton(
       label: _currentStep == 0 ? 'Next' : 'Create',
       icon: _currentStep == 0
           ? FluentIcons.arrow_right_24_regular
           : FluentIcons.play_24_regular,
       onTap: _isLoading ? null : _nextStep,
     ),
   ],
   ```
6. Error messages / progress indicators: `CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(tokens.accent))`, error text `tokens.err`.

### 5.3 Retokenise step files

- [ ] **Step 3 · Retoken `step_select_source.dart`**

Apply:
1. Replace all `Theme.of(context).colorScheme.*` with `context.tokens.*`.
2. Replace any `TextFormField` or `TextField` with `TokenTextField` (from `package:twmt/widgets/wizard/token_text_field.dart`) if there's input.
3. Pack list items: rebuild container decoration with `BoxDecoration(color: isHovered ? tokens.panel2 : tokens.panel, border: Border.all(color: isSelected ? tokens.accent : tokens.border), borderRadius: BorderRadius.circular(tokens.radiusSm))`.
4. Empty / loading / error states use tokens (icon color `tokens.textFaint` / `tokens.err`, text `tokens.textDim`).

- [ ] **Step 4 · Retoken `step_select_targets.dart`**

Apply:
1. Same color/font replacement pass as Step 3.
2. Language tiles as grid cells with `bg: tokens.panel2, selected: tokens.accentBg, border: tokens.accent if selected else tokens.border`.
3. Checkboxes: `Checkbox(activeColor: tokens.accent, checkColor: tokens.accentFg)`.

- [ ] **Step 5 · Retoken `add_language_wizard_dialog.dart`**

Apply:
1. Same replacements.
2. Search field: `TokenTextField` + `prefixIcon` for search glass.
3. Language list: rows with `bg: tokens.panel` base, hover `tokens.panel2`, selected `tokens.accentBg`.

### 5.4 Tests

- [ ] **Step 6 · Run existing game_translation tests**

```bash
C:/src/flutter/bin/flutter test test/features/game_translation/
```

Expected: all PASS. If any test asserts on specific `Theme.of` values, rewrite to token lookups.

- [ ] **Step 7 · Create golden test**

Create `test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: ctx,
              builder: (_) => const CreateGameTranslationDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      theme: theme,
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets('create game translation dialog atelier step 1', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../goldens/create_game_translation_atelier.png'),
    );
  });

  testWidgets('create game translation dialog forge step 1', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../goldens/create_game_translation_forge.png'),
    );
  });
}
```

- [ ] **Step 8 · Generate goldens**

```bash
mkdir -p test/features/game_translation/goldens
C:/src/flutter/bin/flutter test --update-goldens test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart
```

- [ ] **Step 9 · Re-run for stability**

```bash
C:/src/flutter/bin/flutter test test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart
```

- [ ] **Step 10 · Commit**

```bash
git add lib/features/game_translation/widgets/create_game_translation/ \
        test/features/game_translation/widgets/create_game_translation_dialog_golden_test.dart \
        test/features/game_translation/goldens/create_game_translation_atelier.png \
        test/features/game_translation/goldens/create_game_translation_forge.png
git commit -m "refactor: retokenise Game Translation setup dialog + steps"
```

---

## Task 6 · New Project dialog retokenization (β)

**Files:**
- Modify: `lib/features/projects/widgets/create_project/create_project_dialog.dart`
- Modify: `lib/features/projects/widgets/create_project/step_basic_info.dart`
- Modify: `lib/features/projects/widgets/create_project/step_languages.dart`
- Modify: `lib/features/projects/widgets/create_project/step_settings.dart`
- Create: `test/features/projects/widgets/create_project_dialog_golden_test.dart`

### 6.1 Read the dialog + step files

- [ ] **Step 1 · Inspect structure**

```bash
cat lib/features/projects/widgets/create_project/create_project_dialog.dart | head -120
cat lib/features/projects/widgets/create_project/step_basic_info.dart | head -60
cat lib/features/projects/widgets/create_project/step_languages.dart | head -60
cat lib/features/projects/widgets/create_project/step_settings.dart | head -60
```

Note : 3-step wizard (basic info, languages, settings) inside `AlertDialog`. Step nav via `_currentStep` 0/1/2 with auto-skip of step 0 when `detectedMod != null`.

### 6.2 Retokenise the dialog

- [ ] **Step 2 · Refactor `create_project_dialog.dart`**

Apply the same transformations as Task 5.2:
1. Imports (tokens, SmallTextButton, SmallIconButton).
2. Replace `Theme.of` → `context.tokens`.
3. Insert `_StepHeader` widget with `'STEP ${_currentStep + 1}/3'` and title per step:
   - Step 0 : `'Basic info'`
   - Step 1 : `'Target languages'`
   - Step 2 : `'Translation settings'`
4. Footer buttons via `SmallTextButton` (Back / Cancel / Next / Create).
5. Error messages + progress indicator : tokens.

### 6.3 Retokenise step files

- [ ] **Step 3 · Retoken `step_basic_info.dart`**

Apply:
1. Replace all `Theme.of` with `context.tokens`.
2. Replace `TextField` / `TextFormField` for name with `TokenTextField`.
3. Game dropdown and source file picker : wrap in `LabeledField` with label, body-text + chevron icon.
4. If mod is auto-filled : show as `ReadonlyField` rows for name/game/source.

- [ ] **Step 4 · Retoken `step_languages.dart`**

Same pattern as Task 5.4 (language tiles grid with checkboxes).

- [ ] **Step 5 · Retoken `step_settings.dart`**

Apply:
1. `Theme.of` → `context.tokens`.
2. `TokenTextField` pour batch size (numeric), parallel batches (slider ou TokenTextField).
3. Custom prompt : `TokenTextField(maxLines: 6)`.
4. `LabeledField` wraps each input.

### 6.4 Tests

- [ ] **Step 6 · Run existing projects tests**

```bash
C:/src/flutter/bin/flutter test test/features/projects/
```

Expected: all PASS.

- [ ] **Step 7 · Create golden test**

Create `test/features/projects/widgets/create_project_dialog_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: ctx,
              builder: (_) => const CreateProjectDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      theme: theme,
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets('create project dialog atelier step 1', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../goldens/create_project_atelier.png'),
    );
  });

  testWidgets('create project dialog forge step 1', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../goldens/create_project_forge.png'),
    );
  });
}
```

- [ ] **Step 8 · Generate goldens**

```bash
mkdir -p test/features/projects/goldens
C:/src/flutter/bin/flutter test --update-goldens test/features/projects/widgets/create_project_dialog_golden_test.dart
```

- [ ] **Step 9 · Re-run for stability**

```bash
C:/src/flutter/bin/flutter test test/features/projects/widgets/create_project_dialog_golden_test.dart
```

- [ ] **Step 10 · Commit**

```bash
git add lib/features/projects/widgets/create_project/ \
        test/features/projects/widgets/create_project_dialog_golden_test.dart \
        test/features/projects/goldens/create_project_atelier.png \
        test/features/projects/goldens/create_project_forge.png
git commit -m "refactor: retokenise New Project dialog + steps"
```

---

## Task 7 · Final verification

**Files:** none (regression pass).

- [ ] **Step 1 · Full `flutter analyze`**

```bash
cd E:/Total-War-Mods-Translator/.worktrees/ui-cleanup
C:/src/flutter/bin/flutter analyze
```

Expected: no new issues beyond pre-existing 35.

- [ ] **Step 2 · Full test suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: **~1340 passing / 14 failing**. Failures : same 14 pre-existing `SidebarUpdateChecker` overflows.

- [ ] **Step 3 · Verify workshop goldens byte-identical**

If any of the 4 goldens in Task 1 have drifted, the extraction regressed. Inspect the diff before regenerating.

- [ ] **Step 4 · Verify pack_compilation_editor goldens**

Only regenerate if the drift is content-identical (timing shift only) — see Task 3 Step 9.

- [ ] **Step 5 · Manual smoke test (optional but recommended)**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Exercise:
- Help screen : TOC navigation, section content rendering, error state (disconnect network if possible).
- Projects list → "+ New Project" → 3-step wizard → create → verify flow green.
- Game Files → "Create game translation" → 2-step wizard → create → verify.
- Pack Compilation editor : toggle projects, verify conflict panel appears reliably without 100ms delay.
- Workshop Publish single : submit → verify progress flows.

- [ ] **Step 6 · Final commit (if fixups needed)**

```bash
git add -A
git commit -m "chore: Plan 5d — wrap-up (final verify)"
```

If no fixups, skip commit.

---

## Spec coverage check (self-review)

| Spec requirement | Task |
|---|---|
| §2 decision #1 (scope — dialogs + Help + 5c follow-ups) | Tasks 1-6 |
| §2 decision #2 (β retokenisation) | Tasks 4, 5, 6 |
| §2 decision #3 (3 primitives extraction) | Task 1 |
| §2 decision #4 (5c P1 refactor) | Task 3 |
| §2 decision #5 (5c P2 refactor) | Task 3 |
| §2 decision #6 (5c P3 refactor) | Task 2 |
| §2 decision #7 (5c P4 refactor) | Task 2 |
| §4.1 `TokenTextField` | Task 1.2 |
| §4.2 `LabeledField` | Task 1.1 |
| §4.3 `ReadonlyField` | Task 1.3 |
| §5.1 Help retoken | Task 4 |
| §5.2 Game Translation dialog | Task 5 |
| §5.3 New Project dialog | Task 6 |
| §5.4 5c follow-ups | Tasks 2 + 3 |
| §6 widget tests primitives (~8) | Task 1 |
| §6 goldens (6 new) | Tasks 4, 5, 6 |
| §7.1 Worktree setup | pre-Task 1 |
| §7.2 Task order | Tasks 1-7 |
| §8 Risques — workshop goldens drift | Task 1.4 Step 16 |
| §8 Risques — pack editor golden drift | Task 3 Step 9 |
| §8 Risques — ref.listen double-registration | Task 3 (separate build-scope + initState-scope listeners) |
| §8 Risques — dialog goldens sur AlertDialog | Tasks 5.4 + 6.4 (showDialog + pumpAndSettle pattern) |
| §10 Open Q1 Help header height | Task 4.1 (72 via padding 24 + inner row) |
| §10 Open Q2 `_StepHeader` widget | Task 5.2 + Task 6.2 (inline private Container — YAGNI) |
| §10 Open Q3 Dialog dimensions | Tasks 5 + 6 (preserve existing) |
| §10 Open Q4 `@visibleForTesting` import | Task 2 (`package:flutter/foundation.dart`) |
