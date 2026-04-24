# Set Workshop ID before pack generation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `SteamActionCell` so users can save / edit a project's or compilation's Workshop ID before the local `.pack` file is generated.

**Architecture:** Add two sub-modes to the existing 3-state cell (no pack / pack-no-id / pack-and-id). A small pencil icon next to "Generate pack" toggles `_isEditingSteamId`, which now unconditionally renders the existing `_buildSteamIdInput` widget — `hasPack` is no longer a precondition for entering edit mode. No provider, persistence, or routing changes.

**Tech Stack:** Flutter, Riverpod, mocktail, flutter_test. File lives under `lib/features/steam_publish/widgets/`. Tests under `test/features/steam_publish/widgets/`.

---

## File Structure

**Modified:**
- `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` — add pencil icon to State A branches and reorder the `build()` dispatch so `_isEditingSteamId` takes precedence over the `!hasPack` check.
- `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart` — add regression tests locking the two new sub-modes and the new edit-without-pack flow.

No new files. No provider changes. No persistence changes.

---

## Reference: affordance tooltips

Tests and implementation both reference these exact strings. Keep them in sync.

| Affordance | Tooltip string |
|---|---|
| Save button (in input) | `'Save Workshop id'` |
| Open launcher (in input) | `'Open the in-game launcher'` |
| Cancel (in input) | `'Cancel'` |
| Open in Steam (non-edit) | `'Open in Steam Workshop'` |
| Edit id icon — **existing** (State C) | `'Edit Workshop id'` |
| Edit id icon — **new** (State A₁: has id, no pack) | `'Edit Workshop id'` *(reuse)* |
| Edit id icon — **new** (State A₀: no id, no pack) | `'Set Workshop id'` |

---

## Task 1: Lock A₀ pencil rendering with a failing test

**Files:**
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

- [ ] **Step 1: Add the failing test**

Append this test inside the existing `main()` block in `steam_publish_action_cell_state_test.dart`, after the `'State A (no pack) renders Generate pack'` test.

```dart
  testWidgets(
    'State A (no pack, no id) renders the Set Workshop id icon button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project()),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Generate pack must still render alongside the new pencil icon.
      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Set Workshop id'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "Set Workshop id icon button"`

Expected: FAIL with `Expected: exactly one matching candidate` for `find.byTooltip('Set Workshop id')` because A₀ currently returns only the Generate-pack button.

- [ ] **Step 3: Implement A₀ rendering**

In `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`, replace the final `return _buildGenerateButton(context);` at the bottom of the `!hasPack` branch in `build()` (currently at the end of the `if (!hasPack) { ... }` block) with a Row containing the generate button and the pencil icon.

Find this block (around lines 60–82):

```dart
    if (!hasPack) {
      // Legacy parity: when the local pack was deleted but the item is still
      // published on the Workshop, surface Generate alongside Open-in-Steam so
      // users can jump to their published listing without regenerating first.
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
```

Replace the final `return _buildGenerateButton(context);` (A₀ branch, no id case) with:

```dart
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(child: _buildGenerateButton(context, padded: false)),
            const SizedBox(width: 6),
            _iconButton(
              icon: FluentIcons.edit_24_regular,
              tooltip: 'Set Workshop id',
              onTap: _beginEditSteamId,
            ),
          ],
        ),
      );
```

Then add this private helper method to the `_SteamActionCellState` class (place it near `_openWorkshop`, around line 163):

```dart
  /// Pre-fills the text field with the current id (if any) and switches the
  /// cell into edit mode. Shared by the pencil icon in State A₀/A₁/C.
  void _beginEditSteamId() {
    _steamIdController.text = widget.item.publishedSteamId ?? '';
    setState(() => _isEditingSteamId = true);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "Set Workshop id icon button"`

Expected: PASS.

- [ ] **Step 5: Run the full state-test file so existing State-A / B / C regressions still pass**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: all existing tests + the new one PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart \
        test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "feat(steam_publish): add Set Workshop id pencil in State A (no pack)"
```

---

## Task 2: Add the pencil in State A₁ (no pack, with id)

**Files:**
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`

- [ ] **Step 1: Add the failing test**

Append this test after the A₀ test added in Task 1.

```dart
  testWidgets(
    'State A (no pack, with id) renders Generate + Open in Steam + Edit id',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(
          item: _project(publishedSteamId: '3456789012'),
        ),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
      expect(find.byTooltip('Edit Workshop id'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "Generate + Open in Steam + Edit id"`

Expected: FAIL with `Expected: exactly one matching candidate` for `find.byTooltip('Edit Workshop id')` in the no-pack branch.

- [ ] **Step 3: Append the pencil to the State A₁ Row**

In the same `!hasPack && hasPublishedId` block (lines 64–80), add the pencil after the existing `SmallTextButton` for Open in Steam:

```dart
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
              const SizedBox(width: 4),
              _iconButton(
                icon: FluentIcons.edit_24_regular,
                tooltip: 'Edit Workshop id',
                onTap: _beginEditSteamId,
              ),
            ],
          ),
        );
      }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "Generate + Open in Steam + Edit id"`

Expected: PASS.

- [ ] **Step 5: Run the full state-test file to confirm no regressions**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: every test passes.

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart \
        test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "feat(steam_publish): allow editing Workshop id in State A with existing id"
```

---

## Task 3: Allow entering edit mode without a pack

**Files:**
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`

The pencil now renders, but tapping it doesn't reveal the input — the `build()` dispatch checks `!hasPack` *before* `_isEditingSteamId`, so the A₀/A₁ branch keeps returning. We invert the precedence.

- [ ] **Step 1: Add the failing test**

Append this test after the Task 2 test.

```dart
  testWidgets(
    'State A pencil tap reveals the inline Workshop-id input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // The Workshop-id TextField requires a Material ancestor, so wrap the
      // cell in a Scaffold like the existing State-B tests do.
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Tap the pencil and expect the State-B input to render.
      await tester.tap(find.byTooltip('Set Workshop id'));
      await tester.pumpAndSettle();

      final inputFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Paste Workshop URL or ID...',
      );
      expect(inputFinder, findsOneWidget);

      // Launcher button remains visible per design decision.
      expect(find.byTooltip('Open the in-game launcher'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "pencil tap reveals the inline Workshop-id input"`

Expected: FAIL — after the tap, the cell still renders the A₀ row because the `!hasPack` branch runs before the edit check.

- [ ] **Step 3: Reorder the `build()` dispatch**

In `steam_publish_action_cell.dart`, the current `build()` method opens with (around line 50):

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
      // ...
    }

    if (!hasPublishedId || _isEditingSteamId) {
      return _buildSteamIdInput(context);
    }

    return _buildPublishButtons(context);
  }
```

Replace the section starting at `if (_isGenerating)` and ending at the final `return _buildPublishButtons(context);` with this reordered block. Put the edit-mode check **before** `!hasPack`, and simplify the State-B check to `!hasPublishedId` (since `_isEditingSteamId` is already handled above).

```dart
    if (_isGenerating) {
      return _buildGenerateProgress(context);
    }

    // Edit mode takes precedence: once the user taps the pencil we render the
    // shared Steam-id input regardless of pack presence. This is what lets the
    // user set or change the Workshop id before a pack is generated.
    if (_isEditingSteamId) {
      return _buildSteamIdInput(context);
    }

    if (!hasPack) {
      // Legacy parity: when the local pack was deleted but the item is still
      // published on the Workshop, surface Generate alongside Open-in-Steam so
      // users can jump to their published listing without regenerating first.
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
              const SizedBox(width: 4),
              _iconButton(
                icon: FluentIcons.edit_24_regular,
                tooltip: 'Edit Workshop id',
                onTap: _beginEditSteamId,
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(child: _buildGenerateButton(context, padded: false)),
            const SizedBox(width: 6),
            _iconButton(
              icon: FluentIcons.edit_24_regular,
              tooltip: 'Set Workshop id',
              onTap: _beginEditSteamId,
            ),
          ],
        ),
      );
    }

    if (!hasPublishedId) {
      return _buildSteamIdInput(context);
    }

    return _buildPublishButtons(context);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "pencil tap reveals the inline Workshop-id input"`

Expected: PASS.

- [ ] **Step 5: Run the full state-test file**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: all tests pass (State B / C regressions still green because State-B's `!hasPublishedId` branch remains and State-C still reaches the final `_buildPublishButtons`).

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart \
        test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "feat(steam_publish): allow entering Workshop-id edit mode without a pack"
```

---

## Task 4: Persist a Workshop URL saved without a pack

**Files:**
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

The save path (`_saveSteamId`) already handles projects without a pack — `publishedSteamId` is an independent field on `Project`. We add a regression test to lock the behaviour so a future change to `_saveSteamId` can't silently break the no-pack flow.

- [ ] **Step 1: Add the failing test**

Append this test after the Task 3 test. It mirrors the existing `'State B accepts a full Workshop URL and saves the extracted id'` test but uses a pack-less project.

```dart
  testWidgets(
    'State A saves a Workshop URL without a pack',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeRepo = _FakeProjectRepository();
      final savedIds = <String?>[];
      final baseProject = Project(
        id: 'p1',
        name: 'Sigmars Heirs',
        gameInstallationId: 'g1',
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
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          projectRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      ));
      await tester.pumpAndSettle();

      // Enter edit mode.
      await tester.tap(find.byTooltip('Set Workshop id'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012',
      );
      await tester.tap(find.byTooltip('Save Workshop id'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(savedIds, ['3456789012']);
    },
  );
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "saves a Workshop URL without a pack"`

Expected: PASS on first try — `_saveSteamId` already routes through `projectRepo.update` regardless of pack presence.

If it FAILS: inspect `_saveSteamId` (lines 432–484 in `steam_publish_action_cell.dart`); the most likely breakage is a premature `hasPack` guard. There is no such guard today, so a failure here is a signal something else changed.

- [ ] **Step 3: Run the full state-test file**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: every test passes.

- [ ] **Step 4: Commit**

```bash
git add test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "test(steam_publish): lock save-Workshop-id flow without a generated pack"
```

---

## Task 5: Lock the cancel-from-A-edit transition

**Files:**
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Cancel already flips `_isEditingSteamId` back to false (line 409–413 in `steam_publish_action_cell.dart`). We add a regression test so State-A edit cancellation can't silently regress.

- [ ] **Step 1: Add the failing test**

Append this test after the Task 4 test.

```dart
  testWidgets(
    'State A cancel returns to the non-edit rendering',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Enter edit mode.
      await tester.tap(find.byTooltip('Set Workshop id'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Cancel and verify the A₀ row is back.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Set Workshop id'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart --plain-name "cancel returns to the non-edit rendering"`

Expected: PASS on first try.

- [ ] **Step 3: Run the full state-test file**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: every test passes.

- [ ] **Step 4: Commit**

```bash
git add test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart
git commit -m "test(steam_publish): lock cancel-edit flow in State A"
```

---

## Task 6: Update the class docstring

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` (docstring, lines 19–25)

- [ ] **Step 1: Replace the 3-mode docstring with the new 5-mode description**

Find the existing docstring above the `SteamActionCell` class declaration:

```dart
/// State-machine action cell rendered in column 6 of the Steam Publish list.
///
/// Three rendering modes:
///
/// - No pack → "Generate pack" (project) or "Open compilation" (compilation).
/// - Pack + no Workshop id → inline Steam-id input + save.
/// - Pack + Workshop id → "Update" + "Open in Steam" + edit-id buttons.
class SteamActionCell extends ConsumerStatefulWidget {
```

Replace it with:

```dart
/// State-machine action cell rendered in column 6 of the Steam Publish list.
///
/// Rendering modes:
///
/// - A₀ — No pack, no Workshop id → "Generate pack" + edit-id pencil.
/// - A₁ — No pack, has Workshop id → "Generate pack" + "Open in Steam" +
///   edit-id pencil.
/// - B — Pack + no Workshop id → inline Steam-id input + save.
/// - C — Pack + Workshop id → "Update" + "Open in Steam" + edit-id pencil.
///
/// Tapping any edit-id pencil (or being in A where `hasPublishedId` is false
/// before any save) switches `_isEditingSteamId` on and renders the shared
/// inline input regardless of pack presence. Cancel restores the pre-edit
/// rendering; save persists the parsed id via the relevant repository and
/// invalidates [publishableItemsProvider] so the cell recomputes.
class SteamActionCell extends ConsumerStatefulWidget {
```

- [ ] **Step 2: Run the full state-test file as a sanity check**

Run: `flutter test test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

Expected: every test still passes (docstring change is compile-only).

- [ ] **Step 3: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart
git commit -m "docs(steam_publish): update SteamActionCell docstring for A₀/A₁ sub-modes"
```

---

## Task 7: Broader regression sweep

**Files:** none modified.

- [ ] **Step 1: Run the full steam_publish test suite**

Run: `flutter test test/features/steam_publish/`

Expected: every test passes. If a test that is not part of `steam_publish_action_cell_state_test.dart` fails, inspect whether it relied on the old `if (!hasPack)` being the first dispatch branch; fix only what is necessary without changing tests' intent.

- [ ] **Step 2: Run the widget test layer beyond `steam_publish/`**

Run: `flutter test test/features/`

Expected: every test passes. A failure here signals an unintended dependency; do not proceed to step 3 until it is root-caused.

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`

Expected: every test passes.

- [ ] **Step 4: Manual verification on Windows**

From the repo root, run:

```bash
/c/src/flutter/bin/flutter run -d windows
```

In the running app: navigate to Publish on Steam, pick a project **without** a generated pack, click the new pencil icon, paste a Workshop URL, click Save. Confirm the row re-renders to the A₁ form (`Generate pack` + `Open in Steam` + `Edit Workshop id`). Then click the pencil again, change the id to an invalid string (e.g. `abc`), click Save — expect the warning toast `"Couldn't read a Workshop ID from that value."`. Click Cancel, confirm the original id is preserved.

- [ ] **Step 5: Final commit (only if any polish changes were required above)**

If steps 1–4 exposed any fixes, commit them with a narrowly-scoped message. Otherwise skip.

```bash
git status
# If staged changes exist:
git commit -m "fix(steam_publish): <specific fix>"
```
