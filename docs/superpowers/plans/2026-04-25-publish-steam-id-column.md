# Steam ID column on the Publish on Steam list — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Steam ID` column to the *Publish on Steam* list that displays each mod's Workshop ID and lets the user edit it inline via a pencil icon, while disabling the action cell's `Update` button until an ID is set.

**Architecture:** A new stateful `SteamIdCell` widget owns the read / manual-edit / auto-edit (state-B) modes for the new column. A small top-level `saveWorkshopId(...)` helper holds the parse-and-persist logic shared between the cell and any future caller. The existing `SteamActionCell` loses its inline editor entirely; in state B it now renders a disabled `Update` button next to the launcher button, and in states A₀ / A₁ / C it loses the edit pencil.

**Tech Stack:** Flutter (Material 3) · Riverpod (`flutter_riverpod`) · `fluentui_system_icons` · `mocktail` for widget tests · `intl` for number formatting (already wired). Spec: `docs/superpowers/specs/2026-04-25-publish-steam-id-column-design.md`.

---

## File map

**Create:**
- `lib/features/steam_publish/widgets/steam_id_editing.dart` — `saveWorkshopId(...)` helper
- `lib/features/steam_publish/widgets/steam_id_cell.dart` — `SteamIdCell` widget (read / manual edit / auto-edit)
- `test/features/steam_publish/widgets/steam_id_cell_test.dart` — widget tests for the cell

**Modify:**
- `lib/features/steam_publish/widgets/steam_publish_list_cells.dart` — extend `steamPublishColumns` with the new column
- `lib/features/steam_publish/widgets/steam_publish_list.dart` — wire `SteamIdCell` into the row + add header label
- `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` — strip inline editor + pencils, add disabled-Update + Open-launcher pair for state B
- `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart` — drop pencil/inline-editor tests, add disabled-Update tests

---

## Task 1: Save helper (`saveWorkshopId`)

**Files:**
- Create: `lib/features/steam_publish/widgets/steam_id_editing.dart`

The helper centralises the parse-and-persist logic that lives in `SteamActionCell._saveSteamId` today (lines ~473–525). Same semantics: `parseWorkshopId` → repository update → invalidate `publishableItemsProvider`. Toast warnings/errors are surfaced through `FluentToast`.

- [ ] **Step 1: Create the helper file**

Create `lib/features/steam_publish/widgets/steam_id_editing.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../providers/steam_publish_providers.dart';
import '../utils/workshop_url_parser.dart';

/// Parses [rawInput] into a Workshop id and persists it on the right
/// repository for [item], then invalidates [publishableItemsProvider] so
/// downstream rows rebuild with the new id.
///
/// Surfaces a warning toast when [rawInput] doesn't parse and an error toast
/// when the repository call throws. Returns true on success, false otherwise.
/// Callers must check `mounted` themselves before consuming the result —
/// this helper does NOT touch widget state.
Future<bool> saveWorkshopId({
  required WidgetRef ref,
  required BuildContext context,
  required PublishableItem item,
  required String rawInput,
}) async {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) return false;

  final parsed = parseWorkshopId(trimmed);
  if (parsed == null) {
    FluentToast.warning(
      context,
      "Couldn't read a Workshop ID from that value.",
    );
    return false;
  }

  try {
    if (item is ProjectPublishItem) {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectResult = await projectRepo.getById(item.project.id);
      if (projectResult.isOk) {
        final updated = projectResult.value.copyWith(
          publishedSteamId: parsed,
          updatedAt: projectResult.value.updatedAt,
        );
        await projectRepo.update(updated);
      }
    } else if (item is CompilationPublishItem) {
      final compilationRepo = ref.read(compilationRepositoryProvider);
      // Preserve existing fallback semantics from SteamActionCell — when an
      // item has never been published, publishedAt is null and we write 0.
      await compilationRepo.updateAfterPublish(
        item.compilation.id,
        parsed,
        item.publishedAt ?? 0,
      );
    }
    ref.invalidate(publishableItemsProvider);
    return true;
  } catch (e) {
    FluentToast.error(context, 'Failed to save Workshop id: $e');
    return false;
  }
}
```

- [ ] **Step 2: Verify the file compiles in isolation**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter analyze lib/features/steam_publish/widgets/steam_id_editing.dart`
Expected: `No issues found!` (or only the standard project-wide noise — but no errors in this file).

- [ ] **Step 3: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_id_editing.dart
git commit -m "feat(steam_publish): add shared saveWorkshopId helper"
```

---

## Task 2: `SteamIdCell` — read modes (with and without id)

**Files:**
- Create: `lib/features/steam_publish/widgets/steam_id_cell.dart`
- Create: `test/features/steam_publish/widgets/steam_id_cell_test.dart`

This task introduces the cell skeleton + the two read modes only. Manual-edit and auto-edit modes are added in Tasks 3 and 4 — keep the cell stub simple here.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/steam_publish/widgets/steam_id_cell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_id_cell.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectPublishItem _project({String? publishedSteamId}) =>
    ProjectPublishItem(
      export: null,
      project: Project(
        id: 'p1',
        name: 'P1',
        gameInstallationId: 'g',
        createdAt: 0,
        updatedAt: 0,
        publishedSteamId: publishedSteamId,
        publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
      ),
      languageCodes: const ['en'],
    );

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('Read mode — shows the ID and the edit pencil when set',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '3024186382')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('3024186382'), findsOneWidget);
    expect(find.byTooltip('Edit Workshop id'), findsOneWidget);
    expect(find.byIcon(FluentIcons.edit_24_regular), findsOneWidget);
  });

  testWidgets('Read mode — shows em dash and pencil when ID is absent',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamIdCell(item: _project())),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
    expect(find.byTooltip('Set Workshop id'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: COMPILATION FAILURE — `steam_id_cell.dart` doesn't exist yet.

- [ ] **Step 3: Create the cell file with read modes only**

Create `lib/features/steam_publish/widgets/steam_id_cell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../providers/steam_publish_providers.dart';

/// Cell rendered in the Steam Publish list's Steam ID column.
///
/// Three modes selected from `(hasPack, hasPublishedId, _isEditing)`:
///   - Read (id present)  → mono ID + pencil
///   - Read (no id)       → em dash + pencil
///   - Edit               → TextField + Save + Cancel (added in later tasks)
class SteamIdCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamIdCell({super.key, required this.item});

  @override
  ConsumerState<SteamIdCell> createState() => _SteamIdCellState();
}

class _SteamIdCellState extends ConsumerState<SteamIdCell> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasId ? id : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: hasId ? tokens.textMid : tokens.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            context: context,
            icon: FluentIcons.edit_24_regular,
            tooltip: hasId ? 'Edit Workshop id' : 'Set Workshop id',
            onTap: () {
              // Filled in by Task 3.
            },
          ),
        ],
      ),
    );
  }

  /// Square 28×28 icon button — same shape as the action cell's `_iconButton`.
  Widget _iconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(icon, size: 14, color: tokens.textMid),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_id_cell.dart test/features/steam_publish/widgets/steam_id_cell_test.dart
git commit -m "feat(steam_publish): add SteamIdCell read modes"
```

---

## Task 3: `SteamIdCell` — manual edit mode (pencil → TextField + Save + Cancel)

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_id_cell.dart`
- Modify: `test/features/steam_publish/widgets/steam_id_cell_test.dart`

Tapping the pencil enters edit mode: TextField (pre-filled with current ID), Save icon, Cancel icon. Save uses `saveWorkshopId` from Task 1; Cancel restores the read view.

- [ ] **Step 1: Add the failing edit-mode tests**

Append to `test/features/steam_publish/widgets/steam_id_cell_test.dart` (above the closing `}`):

```dart
  testWidgets('Pencil tap reveals the inline TextField pre-filled with the ID',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '999')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Workshop id'));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, '999');
    expect(find.byTooltip('Save Workshop id'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });

  testWidgets('Cancel exits edit mode and restores the read view',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '999')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Workshop id'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('999'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: 2 new tests FAIL (no TextField appears, no Save/Cancel tooltips).

- [ ] **Step 3: Add edit-mode rendering to `SteamIdCell`**

Replace the contents of `lib/features/steam_publish/widgets/steam_id_cell.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../providers/steam_publish_providers.dart';
import 'steam_id_editing.dart';

/// Cell rendered in the Steam Publish list's Steam ID column.
///
/// Three modes selected from `(hasPack, hasPublishedId, _isEditing)`:
///   - Read (id present)  → mono ID + pencil
///   - Read (no id)       → em dash + pencil
///   - Edit               → TextField + Save + Cancel
class SteamIdCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamIdCell({super.key, required this.item});

  @override
  ConsumerState<SteamIdCell> createState() => _SteamIdCellState();
}

class _SteamIdCellState extends ConsumerState<SteamIdCell> {
  final TextEditingController _controller = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return _buildEdit(context);
    }
    return _buildRead(context);
  }

  // ---------------------------------------------------------------------------
  // Read mode (id present or em dash).
  // ---------------------------------------------------------------------------

  Widget _buildRead(BuildContext context) {
    final tokens = context.tokens;
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasId ? id : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: hasId ? tokens.textMid : tokens.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            context: context,
            icon: FluentIcons.edit_24_regular,
            tooltip: hasId ? 'Edit Workshop id' : 'Set Workshop id',
            onTap: _beginEdit,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit mode (TextField + Save + Cancel).
  // ---------------------------------------------------------------------------

  Widget _buildEdit(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _controller,
                enabled: !_isSaving,
                style: tokens.fontMono.copyWith(
                  fontSize: 12,
                  color: tokens.text,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste Workshop URL or ID...',
                  hintStyle: tokens.fontMono.copyWith(
                    fontSize: 12,
                    color: tokens.textFaint,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: tokens.panel2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
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
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            context: context,
            icon: _isSaving ? null : FluentIcons.save_24_regular,
            tooltip: 'Save Workshop id',
            onTap: _isSaving ? null : _save,
            busy: _isSaving,
            accent: true,
          ),
          const SizedBox(width: 4),
          _iconButton(
            context: context,
            icon: FluentIcons.dismiss_24_regular,
            tooltip: 'Cancel',
            onTap: _isSaving ? null : _cancel,
          ),
        ],
      ),
    );
  }

  void _beginEdit() {
    _controller.text = widget.item.publishedSteamId ?? '';
    setState(() => _isEditing = true);
  }

  void _cancel() {
    _controller.clear();
    setState(() => _isEditing = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final ok = await saveWorkshopId(
      ref: ref,
      context: context,
      item: widget.item,
      rawInput: _controller.text,
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (ok) _isEditing = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Square 28×28 icon button — same shape as the action cell's `_iconButton`.
  // ---------------------------------------------------------------------------

  Widget _iconButton({
    required BuildContext context,
    required IconData? icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
    bool accent = false,
  }) {
    final tokens = context.tokens;
    final fg = accent ? tokens.accent : tokens.textMid;
    final borderColor = accent ? tokens.accent : tokens.border;
    final bg = accent ? tokens.accentBg : tokens.panel2;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : (icon != null
                    ? Icon(icon, size: 14, color: fg)
                    : const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add a save-flow widget test**

Append to `test/features/steam_publish/widgets/steam_id_cell_test.dart` (above the closing `}`):

```dart
  testWidgets('Save persists the parsed id via the project repository',
      (tester) async {
    final fakeRepo = _FakeProjectRepository();
    final savedIds = <String?>[];
    final baseProject = Project(
      id: 'p1',
      name: 'P1',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
    );
    when(() => fakeRepo.getById('p1')).thenAnswer(
      (_) async => Ok<Project, TWMTDatabaseException>(baseProject),
    );
    when(() => fakeRepo.update(any())).thenAnswer((invocation) async {
      final updated = invocation.positionalArguments.first as Project;
      savedIds.add(updated.publishedSteamId);
      return Ok<Project, TWMTDatabaseException>(updated);
    });

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamIdCell(item: _project())),
      theme: AppTheme.atelierDarkTheme,
      overrides: [projectRepositoryProvider.overrideWithValue(fakeRepo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set Workshop id'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012',
    );
    await tester.tap(find.byTooltip('Save Workshop id'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(savedIds, ['3456789012']);
  });
```

Add the missing imports at the top of the test file:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
```

Add the `_FakeProjectRepository` class and a `setUpAll` registering the fallback at the top of `void main()`:

```dart
class _FakeProjectRepository extends Mock implements ProjectRepository {}
```

```dart
  setUpAll(() {
    registerFallbackValue(
      Project(
        id: '_',
        name: '_',
        gameInstallationId: '_',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });
```

- [ ] **Step 5: Run all `SteamIdCell` tests**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_id_cell.dart test/features/steam_publish/widgets/steam_id_cell_test.dart
git commit -m "feat(steam_publish): add manual edit mode to SteamIdCell"
```

---

## Task 4: `SteamIdCell` — auto-edit for state B + 2-step hint

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_id_cell.dart`
- Modify: `test/features/steam_publish/widgets/steam_id_cell_test.dart`

In state B (pack + no published id), the cell auto-opens into edit mode and renders the 2-step hint underneath the TextField. A local `_autoEditDismissed` flag keeps the cell in read mode after the user explicitly cancels the auto-open, so the editor doesn't immediately re-appear.

- [ ] **Step 1: Add the failing tests**

Add a helper at the top of `test/features/steam_publish/widgets/steam_id_cell_test.dart` (right after the imports / above `_project`):

```dart
String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-id-cell-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}
```

Add the matching imports at the top:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:twmt/models/domain/export_history.dart';
```

Update `_project` to optionally produce a pack:

```dart
ProjectPublishItem _project({
  String id = 'p1',
  String? publishedSteamId,
  bool hasPack = false,
}) {
  final outputPath = hasPack ? _createTempPack(id) : '';
  return ProjectPublishItem(
    export: hasPack
        ? ExportHistory(
            id: 'e-$id',
            projectId: id,
            languages: '["en"]',
            format: ExportFormat.pack,
            validatedOnly: false,
            outputPath: outputPath,
            entryCount: 10,
            exportedAt: 1_700_000_000,
          )
        : null,
    project: Project(
      id: id,
      name: 'P1',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
    ),
    languageCodes: const ['en'],
  );
}
```

Append two new test cases (above the closing `}` of `main`):

```dart
  testWidgets(
    'State B (pack + no id) auto-opens the editor and shows the 2-step hint',
    (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Save Workshop id'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(
        find.textContaining('Publish from the launcher'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'State B cancel falls back to read mode for the lifetime of the row',
    (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Cancel the auto-opened editor.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      // The cell sits in read mode (em dash + Set pencil).
      expect(find.byType(TextField), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.byTooltip('Set Workshop id'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: 2 new tests FAIL (no auto-open, no hint text).

- [ ] **Step 3: Add the auto-edit logic**

In `lib/features/steam_publish/widgets/steam_id_cell.dart`:

1. Add a flag to `_SteamIdCellState`:

```dart
  bool _autoEditDismissed = false;
```

2. Add a derived getter just below the flags:

```dart
  /// State-B auto-open: pack exists, no published id, and the user hasn't
  /// explicitly cancelled the auto-opened editor for this row instance.
  bool get _autoEdit {
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;
    return widget.item.hasPack && !hasId && !_autoEditDismissed;
  }
```

3. Replace the `build` method:

```dart
  @override
  Widget build(BuildContext context) {
    if (_isEditing || _autoEdit) {
      return _buildEdit(context, autoOpen: !_isEditing && _autoEdit);
    }
    return _buildRead(context);
  }
```

4. Update `_buildEdit` to accept the `autoOpen` flag and render the 2-step hint underneath when true. Replace the method signature and body:

```dart
  Widget _buildEdit(BuildContext context, {required bool autoOpen}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSaving,
                    style: tokens.fontMono.copyWith(
                      fontSize: 12,
                      color: tokens.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Paste Workshop URL or ID...',
                      hintStyle: tokens.fontMono.copyWith(
                        fontSize: 12,
                        color: tokens.textFaint,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: tokens.panel2,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
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
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconButton(
                context: context,
                icon: _isSaving ? null : FluentIcons.save_24_regular,
                tooltip: 'Save Workshop id',
                onTap: _isSaving ? null : _save,
                busy: _isSaving,
                accent: true,
              ),
              const SizedBox(width: 4),
              _iconButton(
                context: context,
                icon: FluentIcons.dismiss_24_regular,
                tooltip: 'Cancel',
                onTap: _isSaving ? null : _cancel,
              ),
            ],
          ),
          if (autoOpen) ...[
            const SizedBox(height: 4),
            Text(
              '1. Publish from the launcher · 2. Copy the mod URL here',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: tokens.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
```

5. Replace `_cancel` so the auto-open path also dismisses:

```dart
  void _cancel() {
    _controller.clear();
    setState(() {
      _isEditing = false;
      _autoEditDismissed = true;
    });
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_id_cell_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_id_cell.dart test/features/steam_publish/widgets/steam_id_cell_test.dart
git commit -m "feat(steam_publish): auto-open SteamIdCell editor in state B"
```

---

## Task 5: Wire `SteamIdCell` into the list (column + header + row)

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_list_cells.dart` (just the column spec)
- Modify: `lib/features/steam_publish/widgets/steam_publish_list.dart` (header + row)

Insert the new column at index 3 (between *title* and *subs*). Header label `Steam ID`. Width 180 px.

- [ ] **Step 1: Extend the column spec**

In `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`, replace the docstring + `steamPublishColumns` declaration (lines ~17–37) with:

```dart
/// Column spec for the Steam Publish list (§7.1 filterable list archetype).
/// Columns (fixed widths selected to match the checkbox + cover + action
/// density of the sibling Mods list):
///
/// 1. checkbox (batch-selection toggle)
/// 2. cover (pack preview)
/// 3. title + pack filename mono (flex)
/// 4. steam id + edit pencil
/// 5. subs (Workshop subscriber count)
/// 6. publish state badge
/// 7. last published / exported (mono)
/// 8. inline action
const List<ListRowColumn> steamPublishColumns = [
  ListRowColumn.fixed(40),  // checkbox
  ListRowColumn.fixed(80),  // cover
  ListRowColumn.flex(3),    // title + filename
  ListRowColumn.fixed(180), // steam id (new)
  ListRowColumn.fixed(100), // subs
  ListRowColumn.fixed(160), // status
  ListRowColumn.fixed(180), // last published — fits "Outdated · 12 months"
  ListRowColumn.fixed(180), // action
];
```

- [ ] **Step 2: Wire the cell into the row**

In `lib/features/steam_publish/widgets/steam_publish_list.dart`:

1. Add the import at the top:

```dart
import 'steam_id_cell.dart';
```

2. Insert `SteamIdCell` between `SteamTitleBlock` and `SteamSubsCell` in the `children` list (around line 49):

```dart
                  SteamTitleBlock(item: item),
                  SteamIdCell(item: item),
                  SteamSubsCell(item: item),
```

3. Update the header `labels` list (around line 83) to add the new entry:

```dart
      labels: const [
        '',
        '',
        'Pack',
        'Steam ID',
        'Subs',
        'Status',
        'Last published',
        '',
      ],
```

- [ ] **Step 3: Run the full steam_publish test suite**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/`
Expected: every test that doesn't depend on the action cell's old pencil/inline editor still passes. **The action-cell-state tests will fail** in Tasks 6 & 7 — they're updated alongside the action-cell strip in those tasks. For now: **expect failures only in `steam_publish_action_cell_state_test.dart`** (the column wiring change shouldn't break anything else).

If any other test fails, stop and investigate — the column insert may have shifted something else.

- [ ] **Step 4: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_list_cells.dart lib/features/steam_publish/widgets/steam_publish_list.dart
git commit -m "feat(steam_publish): wire Steam ID column into the list"
```

---

## Task 6: Strip pencil + inline editor from `SteamActionCell` (states A₀, A₁, C)

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`
- Modify: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

The action cell is no longer responsible for editing the Workshop id in states A₀, A₁ and C — only the new column owns that. Remove the `_iconButton` pencils, the controller, and the manual edit-mode branch. (State B is replaced wholesale in Task 7.)

- [ ] **Step 1: Update the failing tests in the action cell suite**

In `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`:

1. **Delete** these test cases (their contracts no longer hold):
   - `'State A (no pack, no id) renders the Set Workshop id icon button'` (lines ~113–129)
   - `'State A (no pack, with id) renders Generate + Open in Steam + Edit id'` (lines ~131–149)
   - `'State A pencil tap reveals the inline Workshop-id input'` (lines ~151–179)
   - `'State A saves a Workshop URL without a pack'` (lines ~181–227)
   - `'State A cancel returns to the non-edit rendering'` (lines ~229–254)

2. **Replace** the surviving `'State A (no pack) renders Generate pack'` test with two narrower tests that lock the new (id-free) behavior:

```dart
  testWidgets('State A₀ (no pack, no id) renders Generate pack only',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Generate pack'), findsOneWidget);
    expect(find.byTooltip('Set Workshop id'), findsNothing);
    expect(find.byTooltip('Edit Workshop id'), findsNothing);
  });

  testWidgets(
    'State A₁ (no pack, with id) renders Generate + Open in Steam (no pencil)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project(publishedSteamId: '3456789012')),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
      expect(find.byTooltip('Edit Workshop id'), findsNothing);
    },
  );
```

3. **Update** the State C test to assert the pencil is gone:

Replace:

```dart
  testWidgets('State C (pack + Workshop id) renders the Update action',
      (tester) async {
    ...
    expect(find.text('Update'), findsOneWidget);
  });
```

with:

```dart
  testWidgets('State C (pack + Workshop id) renders Update without a pencil',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(
        item: _project(hasPack: true, publishedSteamId: '123456'),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Update'), findsOneWidget);
    expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
    expect(find.byTooltip('Edit Workshop id'), findsNothing);
  });
```

- [ ] **Step 2: Run the action cell test suite — expect failures**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
Expected: FAIL — the new assertions about `findsNothing` for pencil tooltips don't yet hold (the production cell still renders pencils).

- [ ] **Step 3: Strip the pencil from `SteamActionCell` (states A₀, A₁, C)**

In `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`:

1. Update the class-level docstring (lines ~19–34) to drop pencil mentions:

```dart
/// State-machine action cell rendered in the action column of the Steam
/// Publish list.
///
/// Rendering modes:
///
/// - A₀ — No pack, no Workshop id → "Generate pack".
/// - A₁ — No pack, has Workshop id → "Generate pack" + "Open in Steam".
/// - B — Pack + no Workshop id → "Update" (disabled) + "Open launcher".
/// - C — Pack + Workshop id → "Update" + "Open in Steam".
///
/// Editing the Workshop id lives in [SteamIdCell] in the dedicated Steam ID
/// column — the action cell never owns the inline editor anymore.
```

2. Remove the local edit / save state and the controller from `_SteamActionCellState`:

```dart
class _SteamActionCellState extends ConsumerState<SteamActionCell> {
  bool _isGenerating = false;
  double _generateProgress = 0.0;
  String? _generateStep;

  // No more _steamIdController, _isSavingSteamId, _isEditingSteamId.
}
```

Delete the `dispose()` override that disposed `_steamIdController` (it had nothing else in it).

3. Replace the `build` method:

```dart
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasPack = item.hasPack;
    final hasPublishedId = item.publishedSteamId != null &&
        item.publishedSteamId!.isNotEmpty;

    if (_isGenerating) {
      return _buildGenerateProgress(context);
    }

    if (!hasPack) {
      // State A₀: Generate pack alone.
      // State A₁: Generate pack + Open in Steam.
      if (hasPublishedId) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(child: _buildGenerateButton(context, padded: false)),
              const SizedBox(width: 6),
              SmallTextButton(
                label: 'Open in Steam',
                tooltip: 'Open in Steam Workshop',
                icon: FluentIcons.open_24_regular,
                onTap: _openWorkshop,
              ),
            ],
          ),
        );
      }
      return _buildGenerateButton(context);
    }

    // State B is added in Task 7.
    if (!hasPublishedId) {
      return _buildPublishButtons(context, updateDisabled: true);
    }

    // State C.
    return _buildPublishButtons(context, updateDisabled: false);
  }
```

4. Delete the helpers that are no longer reachable:
   - `_buildSteamIdInput` (~lines 383–471)
   - `_saveSteamId` (~lines 473–525)
   - `_beginEditSteamId` (~lines 194–197)

5. Trim the imports: drop `'../utils/workshop_url_parser.dart'` and `'package:twmt/providers/shared/repository_providers.dart'` (neither is referenced anymore now that `_saveSteamId` is gone). **Keep** `FluentToast`, `openGameLauncher`, `singlePublishStagingProvider` — they're still used by the launcher branch (Task 7) and the publish navigation. `flutter analyze` may temporarily flag the launcher imports as unused after this task; ignore — Task 7 brings them back into use.

6. Update `_buildPublishButtons` to accept the `updateDisabled` flag — for now leave the implementation unchanged except for the new parameter. (The disabled rendering itself ships in Task 7.)

```dart
  Widget _buildPublishButtons(
    BuildContext context, {
    required bool updateDisabled,
  }) {
    // Body unchanged from the existing State-C version. Task 7 adds the
    // disabled-Update + Open-launcher branch.
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Update existing Workshop item',
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref
                        .read(singlePublishStagingProvider.notifier)
                        .set(widget.item);
                    context.goWorkshopPublishSingle();
                  },
                  child: Container(
                    height: 28,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: tokens.accentBg,
                      border: Border.all(color: tokens.accent),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.cloud_arrow_up_24_regular,
                            size: 14,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Update',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: tokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            icon: FluentIcons.open_24_regular,
            tooltip: 'Open in Steam Workshop',
            onTap: _openWorkshop,
          ),
        ],
      ),
    );
  }
```

(Note: the pencil that used to live at the end of this method is gone. The `updateDisabled` branch is wired in Task 7.)

- [ ] **Step 4: Run the action cell test suite — `Set Workshop id` / `Edit Workshop id` assertions should now pass**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
Expected: A₀, A₁, C tests pass. **State B tests are still failing** — they assert TextField + 2-step hint + launcher inside the action cell, all of which Task 7 will move/replace.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "refactor(steam_publish): remove inline Workshop-id editor from action cell"
```

---

## Task 7: State B — disabled Update + Open launcher in `SteamActionCell`

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`
- Modify: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

State B (pack + no published id) used to auto-render the inline editor in the action cell. It now renders **`[Update (disabled)] [Open launcher]`** — visually parallel to State C, with the Update button greyed out and inert.

- [ ] **Step 1: Replace the State B tests in the action cell suite**

In `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`, **delete** these now-stale test cases:
   - `'State B (pack, no Workshop id) renders the inline Workshop-id input'` (lines ~256–280)
   - `'State B accepts a full Workshop URL and saves the extracted id'` (lines ~282–325)
   - `'State B shows the two-step checklist text'` (lines ~348–362) — the hint moved to `SteamIdCell`

Keep `'State B shows the Open launcher icon button'` but **rewrite** its assertions:

```dart
  testWidgets(
    'State B (pack, no id) renders disabled Update + Open launcher',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Update label is rendered, but tap-handler is null (disabled).
      expect(find.text('Update'), findsOneWidget);
      expect(
        find.byTooltip('Set the Steam ID first to enable updating'),
        findsOneWidget,
      );

      // Launcher button still present.
      expect(find.byTooltip('Open the in-game launcher'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byTooltip('Open the in-game launcher'),
          matching: find.byIcon(FluentIcons.play_24_regular),
        ),
        findsOneWidget,
      );

      // Inline editor is gone — that's now SteamIdCell's job.
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Save Workshop id'), findsNothing);
    },
  );
```

If `_FakeProjectRepository` and the `setUpAll` `registerFallbackValue` block end up unused after the deletions, remove them too — `flutter analyze` will surface the warnings.

- [ ] **Step 2: Run the test — expect failure**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
Expected: FAIL — `'Set the Steam ID first to enable updating'` tooltip not found, and `'Open the in-game launcher'` tooltip absent in state B (the action cell currently renders nothing for state B beyond the inherited state-C path).

- [ ] **Step 3: Implement the disabled-Update + Open-launcher rendering**

In `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`:

Replace the entire body of `_buildPublishButtons` with the dual-branch version below. The key change: when `updateDisabled` is true, the Update visual switches to muted tokens, has `onTap: null`, and the row's trailing icon is the **Open launcher** play button instead of `Open in Steam`.

```dart
  Widget _buildPublishButtons(
    BuildContext context, {
    required bool updateDisabled,
  }) {
    final tokens = context.tokens;

    final updateFg = updateDisabled ? tokens.textFaint : tokens.accent;
    final updateBorder = updateDisabled ? tokens.border : tokens.accent;
    final updateBg = updateDisabled ? tokens.panel2 : tokens.accentBg;
    final updateTooltip = updateDisabled
        ? 'Set the Steam ID first to enable updating'
        : 'Update existing Workshop item';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: updateTooltip,
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: updateDisabled
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: updateDisabled
                      ? null
                      : () {
                          ref
                              .read(singlePublishStagingProvider.notifier)
                              .set(widget.item);
                          context.goWorkshopPublishSingle();
                        },
                  child: Container(
                    height: 28,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: updateBg,
                      border: Border.all(color: updateBorder),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.cloud_arrow_up_24_regular,
                            size: 14,
                            color: updateFg,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Update',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: updateFg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (updateDisabled)
            _iconButton(
              icon: FluentIcons.play_24_regular,
              tooltip: 'Open the in-game launcher',
              onTap: _openLauncher,
            )
          else
            _iconButton(
              icon: FluentIcons.open_24_regular,
              tooltip: 'Open in Steam Workshop',
              onTap: _openWorkshop,
            ),
        ],
      ),
    );
  }
```

`_openLauncher` is preserved across Task 6 (Task 6 only deletes `_buildSteamIdInput`, `_saveSteamId`, `_beginEditSteamId`). Same for the `openGameLauncher` and `FluentToast` imports — leave them alone in Task 6 so this branch can use them. If `flutter analyze` reported them as unused after Task 6, ignore the warning since they come back into use here.

- [ ] **Step 4: Run the action cell test suite**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
Expected: PASS (all surviving tests).

- [ ] **Step 5: Run the full Steam Publish test suite**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test test/features/steam_publish/`
Expected: PASS (all tests including `SteamIdCell`, `SteamSubsCell`, the action cell suite, and the toolbar / onboarding suites).

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "feat(steam_publish): show disabled Update + launcher in state B action cell"
```

---

## Task 8: Full project verification

**Files:** none (verification-only).

- [ ] **Step 1: Run `flutter analyze` on the whole project**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter analyze`
Expected: `No issues found!` (or only the pre-existing background noise — no new warnings/errors in the files this plan touched).

- [ ] **Step 2: Run the full test suite**

Run: `cd /mnt/e/Total-War-Mods-Translator && C:/src/flutter/bin/flutter test`
Expected: PASS, no regressions.

- [ ] **Step 3: Manual smoke test on Windows**

The user runs the dev build and exercises the *Publish on Steam* screen:

```bash
C:/src/flutter/bin/flutter run -d windows
```

Verify in the running app:
1. The list shows a `Steam ID` column header between `Pack` and `Subs`.
2. Rows with a published Workshop id show the id in monospace + a pencil to the right.
3. Rows without an id show `—` + a pencil.
4. Clicking the pencil reveals an inline TextField with Save and Cancel buttons.
5. For a row in **state B** (pack present, no Workshop id), the cell auto-opens the editor and shows the 2-step hint underneath. Cancel collapses it back to `—`.
6. The action cell for state B shows a **disabled** Update button (greyed, inert, tooltip explains why) plus the `Open launcher` play button.
7. Pasting a full Workshop URL into the cell and clicking Save persists the id; the row redraws with the id + status pill `Published`.
8. The action cell for states A₀ / A₁ / C no longer has an edit pencil (verify by hover).

If any step fails, file the discrepancy and fix before committing.

- [ ] **Step 4: Final commit (only if any cleanup was needed during Step 3)**

```bash
git add -A
git commit -m "chore(steam_publish): post-smoke-test cleanup"
```

(Skip this step if Step 3 found nothing to fix.)

---

## Self-review notes

**Spec coverage check:**
- Column inserted at position 4, width 180 px → Task 5 ✅
- Header label `Steam ID` → Task 5 ✅
- Read mode (id present) — mono + pencil → Task 2 ✅
- Read mode (no id) — `—` + pencil → Task 2 ✅
- Manual edit (pencil → TextField + Save + Cancel) → Task 3 ✅
- Auto edit in state B + 2-step hint moves under TextField → Task 4 ✅
- `_autoEditDismissed` flag + Cancel always visible → Task 4 ✅
- Save helper `saveWorkshopId(...)` with the exact signature spec'd → Task 1 ✅
- Action cell A₀ / A₁ / C lose the pencil → Task 6 ✅
- Action cell B replaces editor with `[Update (disabled)] [Open launcher]` → Task 7 ✅
- Disabled Update tooltip text matches spec ("Set the Steam ID first to enable updating") → Task 7 ✅

**Type / signature consistency:**
- `saveWorkshopId` defined in Task 1, called in Task 3 — signatures match (`ref`, `context`, `item`, `rawInput`, returns `Future<bool>`) ✅
- `_iconButton` shape (28×28, accent / busy variants) lifted into `SteamIdCell` matches the action cell's idiom ✅
- `parseWorkshopId` import path is correct (`'../utils/workshop_url_parser.dart'`) ✅
- `publishableItemsProvider` invalidation lives only in `saveWorkshopId` — single source of truth ✅
