# Inspector Panel — Copyable "Unit" and "Source" Fields

## Context

In the translation editor's right inspector panel, the **Unit** key chip
(`sourceLocFile / key`) and the **Source** text block are both rendered as
plain `Text` widgets, which means the user cannot select or copy their content.
The **Target** field is already a `TextField`, so it is copyable natively.

Users frequently need to copy the unit key (to search the codebase, paste it
into a bug report, etc.) or fragments of the source text (to look up a glossary
entry or grep the original loc file). Today they have to retype it.

## Goal

Allow the user to select and copy the text shown in the **Unit** key chip and
the **Source** text block of `EditorInspectorPanel`, without changing the
visual design of the panel.

## Non-goals

- No changes to the **Target** field (already editable).
- No changes to the validation issues block, the bulk-select header, or the
  multi-select state — those are out of scope.
- No new "Copy" button UI; rely on standard text-selection + Ctrl+C +
  right-click context menu.

## Approach

Replace the two `Text` widgets that render user-visible content with
`SelectableText`:

1. `_KeyChip` (line ~457): the `Text` that displays the `sourceLocFile / key`.
2. `_SourceBlock` (line ~496): the `Text` inside the `SingleChildScrollView`
   that displays the escaped source string.

`SelectableText` is a drop-in replacement for `Text` for the styling we use
(no `TextSpan`, no `softWrap`/`overflow` overrides that conflict). It enables:

- Click-and-drag selection with the mouse.
- Ctrl+A / Ctrl+C keyboard shortcuts when the panel has focus.
- Right-click context menu with "Copy" / "Select all" on Windows desktop.

The `_SourceBlock` already wraps its `Text` in a `SingleChildScrollView`;
`SelectableText` is compatible with that wrapper, so vertical scrolling still
works for long source strings.

## Acceptance criteria

- Clicking and dragging across the unit key chip selects characters; Ctrl+C
  copies the selection to the clipboard.
- Clicking and dragging across the source text block selects characters;
  Ctrl+C copies the selection.
- Right-clicking either field on Windows desktop shows a context menu with
  "Copy" available when there is a selection.
- The visual appearance of the panel is unchanged at rest (same font, color,
  padding, background).
- The Target field continues to behave as before (editable, focus-commit).
- Long source strings still scroll vertically inside the source block.
