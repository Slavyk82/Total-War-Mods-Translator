# Workflow improvements — design

**Date:** 2026-04-18
**Scope:** Targeted UX improvements to the translation workflow (Detect → Translate → Compile → Publish). No full redesign; preserve all existing functionality and flexibility.

## Goal

Reduce friction for first-time users without removing advanced paths (batch operations, multi-language, update loop, transverse tools). Make the end-to-end workflow feel logical and natural, including the Steam Workshop handoff that today requires leaving the app.

## Validated decisions

### 1. Workshop manual publish — guided, not abandoned

The first Workshop publication must still be done through the game launcher. Instead of leaving the user stranded, the Workshop screen guides them:

- **"Open game launcher" button** — uses the known install path to open the launcher directly.
- **Inline checklist** while they are in the launcher (e.g. "1. Right-click → Publish, 2. Copy the mod URL, 3. Paste it below").
- **Accept a full Workshop URL**, not just the numeric ID. Parse `steamcommunity.com/sharedfiles/?id=123` → extract `123`. Copy-paste of URL is more natural than hunting for the ID.

### 2. Workflow in the left sidebar (timeline-style)

Add a new `Workflow` group at the top of the sidebar (below brand header and game selector, above Home). The four items route to existing screens and serve as a **timeline anchor** — no state badges, no new screens.

**New sidebar structure:**

```
[Brand header]
[Game selector]

Workflow
  Detect       → AppRoutes.mods
  Translate    → AppRoutes.projects
  Compile      → AppRoutes.packCompilation
  Publish      → AppRoutes.steamPublish

Work
  Home

Resources
  Glossary
  Translation Memory
  Game Files        ← moved from Sources

System
  Settings
  Help
```

**Items removed from their previous groups:** Mods, Projects, Pack Compilation, Steam Workshop. These four screens are now reached exclusively via the Workflow group — no duplication.

**Sources group is dismantled:** Game Files moves to Resources (text material to translate, alongside Glossary and TM). Mods moves to Workflow as "Detect".

**Work group shrinks to Home only.**

Visual treatment: standard `NavItem` tiles, same density as the rest of the sidebar. The `Workflow` group label and the ordered labels (Detect / Translate / Compile / Publish) carry the timeline semantics — no extra badges.

### 3. "Next step" CTA at the end of each workflow screen

When the current workflow step is functionally done, a CTA surfaces the next one:

- End of translation editor → "Next: Compile this pack"
- End of pack compilation → "Next: Publish on Workshop"
- End of Workshop publish → (terminal; shows tracking state)

Conditioned on state (only appears when the step's outcome allows it). Reduces the navigation-mental-load of figuring out what comes next.

### 4. Merge "define target language" into project creation

Today, creating a project and then defining its target language are two separate user-facing steps. Fold the language choice into the project creation form, with the ability to add more languages later (preserves multi-language flexibility).

Net effect: one visible step instead of two, no loss of functionality.

### 5. One Workshop screen, three states per project row

The current steps "enter Workshop ID" and "check publish status" are two views of the same object. Collapse into a single Steam Workshop screen with one row per project that evolves through three states:

| State | Row affordance |
|-------|----------------|
| Draft (pack not yet compiled) | Greyed, CTA "Compile first" |
| Awaiting ID (pack compiled, no Workshop ID yet) | URL/ID input + launcher guidance from decision 1 |
| Tracking (ID saved) | Status + last update timestamp + CTA "Push update" |

No merge with the Projects screen — those remain separate concerns (translation data vs. publication lifecycle). Only the intra-Workshop states are consolidated.

### 6. First-time Workshop education

The manual-first-publish-then-automatic-updates contract is not obvious. On the Steam Workshop screen, show a **pedagogical card** (or tooltip above the ID input) explaining:

> "The first publication goes through the in-game launcher. After you paste the Workshop ID here, all future updates are handled automatically."

**Visibility behaviour:**

- By default, the card is shown **every time** the user opens the Workshop screen — it remains useful across sessions, especially for infrequent publishers.
- The card includes an **opt-in checkbox** labelled "Don't show this again" (or equivalent).
- Only when the user ticks that checkbox does the card become permanently hidden (persisted per user in settings).
- Re-showing the card after it has been permanently hidden is handled via a setting (e.g. a "Reset onboarding hints" control in Settings).

Rationale: publishing happens rarely enough that a one-time dismissal would leave the user stranded weeks later with no recall of the contract. Repeat display is cheap and beneficial; permanent hide is available for power users.

### 7. Empty state covers all five steps

Extend `EmptyStateGuide` (`lib/features/home/widgets/empty_state_guide.dart`) from 3 to 5 steps so a brand-new user sees the full journey on first launch. The two new steps are rendered **greyed and non-clickable** since the user cannot navigate to them yet:

1. Detect your mods in Sources *(clickable → Sources)*
2. Create a project from a mod *(clickable → Sources)*
3. Translate the units *(clickable → Projects)*
4. **Compile your pack** *(greyed, non-clickable)*
5. **Publish on Steam Workshop** *(greyed, non-clickable)*

**Layout fallback:** at 5 cards side-by-side the row may become too narrow. If the layout test shows cramping, switch to a grid (2 × 3 with the last slot empty, or 3 + 2 stacked). The row layout remains the default if it reads well.

## What is explicitly not changing

- Batch screens (`batch_pack_export_screen`, `batch_workshop_publish_screen`) — real advanced-user need.
- Multi-language per project — remains a first-class concept.
- The 4-step conceptual ribbon (Detect / Translate / Compile / Publish) — correct level of abstraction.
- The existing transverse tools (Glossary, Translation Memory) — remain accessible anywhere.
- Projects and Steam Workshop screens — stay separate.

## Open follow-ups

- Visual spec for the "Next step" CTA (decision 3) — placement, style, conditions — to be detailed in the implementation plan.
- Launcher-path detection for decision 1 — verify the resolution logic works across Steam install variants.
- Layout fallback check for decision 7 — validate that 5 cards in a row read well at default sidebar width; switch to grid if cramped.
