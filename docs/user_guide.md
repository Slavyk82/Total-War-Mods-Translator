## Introduction

### What is TWMT?

TWMT (Total War Mods Translator) is a Windows application designed to translate Total War mods from Steam Workshop. It combines AI translation with workflow tools to ease creation and maintenance of translations efficiently.

> **Requirement:** This tool uses [RPFM CLI](https://github.com/Frodo45127/rpfm) to extract files and create packs. You will need this in order for TWMT to work.

### Main Features

- **AI translation** of thousands of entries (Claude, GPT, or DeepL)
- **Glossaries** for consistency maintenance
- **Translation Memory (TM)** for translation reuse
- **Fast search and filtering** across all entries
- **Progress tracking** per language
- **Direct pack export** for in-game use
- **Multi-project management** for simultaneous work

### Supported Games

| Game | Code |
|------|------|
| Total War: Warhammer III | wh3 |
| Total War: Warhammer II | wh2 |
| Total War: Warhammer | wh |
| Total War: Rome II | rome2 |
| Total War: Attila | attila |
| Total War: Troy | troy |
| Total War: Three Kingdoms | 3k |
| Total War: Pharaoh | pharaoh |

## Getting Started

### First Launch

On first launch, you need to configure:

1. **Default Language** — Settings > Translation Language Preferences
2. **Game Paths** — Settings > Folders > Auto-detect
3. **RPFM Path** — Settings > Folders > RPFM Tool
4. **RPFM Schema Path** — Settings > Folders > RPFM Tool
5. **API Keys** — Settings > LLM Providers > Enter your API key

### Configuring Game Paths

1. Go to **Settings** > **Folders**
2. Click **Detect All Games** to scan Steam installations
3. Verify the detected paths
4. Add custom paths if needed

### Configuring API Keys

1. Go to **Settings** > **LLM Providers**
2. Click the **LLM Providers** tab
3. Expand the section for your chosen provider (Anthropic, OpenAI, or DeepL)
4. Enter your API key
5. Click **Test Connection**

> **Recommendation:** Start with OpenAI GPT 5.1 for the best quality/cost balance.

## Global Workflow

TWMT supports two translation workflows depending on whether you are translating mods or the base game.

### Mod Translation Workflow

The typical workflow for translating Steam Workshop mods:

```
1. Mods Screen        →  Scan and discover mods from Steam Workshop
2. Project Creation   →  Create a translation project from a detected mod
3. Translation Editor →  Translate entries manually or with AI assistance
4. Export             →  Generate a translation pack file for use in-game
```

### Game Translation Workflow

The workflow for translating the base game's localization:

```
1. Game Translation   →  Access via sidebar under your selected game
2. Create Project     →  Select source pack and target languages
3. Translation Editor →  Translate entries manually or with AI assistance
4. Export             →  Generate a translation pack to the game's data folder
```

> **Choosing Between Workflows:**
> - Use **Mod Translation** when translating content from Steam Workshop mods
> - Use **Game Translation** when translating the base game itself (fan translations, missing languages)

## Game Translation

The Game Translation feature allows you to translate the base game's localization files rather than individual mods. This is useful for creating complete language support for Total War games that may not have official translations in your language.

![](assets/screenshots/screen_game_translation.png)

### Purpose and Overview

#### What is Game Translation?

Game Translation creates translation projects from the game's core localization files (`local_*.pack`) found in the game's `data` folder. Unlike mod translation which works with Steam Workshop content, Game Translation targets the base game text.

| Concept | Description |
|---------|-------------|
| Source Pack | The game's localization file to translate from (e.g., `local_en.pack`) |
| Target Languages | The languages you want to translate the game into |
| Output Location | Generated packs are saved to the game's `data` folder for immediate use |

#### Why Use Game Translation?

| Benefit | Description |
|---------|-------------|
| **Complete Localization** | Translate the entire game, not just mods |
| **Missing Languages** | Add support for languages without official translations |
| **Custom Terminology** | Use your preferred translations for game terms |
| **Community Projects** | Collaborate on fan translations for the community |

---

### Game Translation Screen

Access the Game Translation screen from the sidebar by clicking "Game Translation" under your selected game.

Each game translation project displays:

| Element | Description |
|---------|-------------|
| Project Name | Auto-generated from game name and target languages |
| Language Progress | Progress bars for each target language |
| Status Badge | Translation completion status |

---

### Creating a Game Translation Project

Creating a game translation project is a two-step wizard process.

#### Prerequisites

Before creating a game translation project:

1. **Game Installation** — The game must be installed and detected in Settings > Folders
2. **Localization Packs** — The game's `data` folder must contain `local_*.pack` files
3. **RPFM Configuration** — RPFM CLI and schema paths must be configured
4. **Target Languages** — At least one target language must be configured in Settings

#### Starting the Wizard

1. Navigate to **Game Translation** in the sidebar
2. If no projects exist, click **Create Game Translation**
3. The creation wizard dialog opens

---

### Step 1: Select Source Pack

The first step is selecting which language pack to use as the translation source.

#### Available Localization Packs

TWMT scans the game's `data` folder for files matching the `local_*.pack` pattern. For each detected pack, the following information is displayed:

| Element | Description |
|---------|-------------|
| Language Name | Full name of the language (e.g., "English", "French") |
| Pack Filename | The filename (e.g., `local_en.pack`) |
| File Size | Size of the pack file |
| Last Modified | Date and time of last modification |

#### Selecting a Source

1. Click on the desired source pack to select it
2. A radio indicator shows the current selection
3. Selected packs are highlighted with a primary color border

> **Recommendation:** Use English (`local_en.pack`) as the source for the most complete text coverage, as it is typically the primary development language.

---

### Step 2: Select Target Languages

The second step is choosing which languages to translate into.

![](assets/screenshots/screen_game_translation_step2.png)

#### Source Language Display

The selected source language is displayed at the top:
- Shows "Translating from: [Language Name]"
- The source language is automatically excluded from target options

#### Language Selection

Available target languages are displayed as selectable chips:

| Control | Description |
|---------|-------------|
| Language Chips | Click to toggle selection |
| Select All | Select all available languages |
| Clear | Deselect all languages |
| Add Language | Open dialog to add a custom language |

#### Adding Custom Languages

If your target language is not in the default list:

1. Click **Add Language**
2. Enter the language code (ISO 639-1)
3. Enter the display name
4. Optionally set as default for future projects
5. Click **Add**

---

### Project Creation Process

After completing both steps, click **Create** to start the project creation.

#### Creation Steps

1. **Project Creation** — Database entry created with project metadata
2. **Language Configuration** — Target languages registered for the project
3. **File Extraction** — RPFM extracts localization files from the source pack
4. **Unit Import** — Translation units imported into the database

#### Automatic Naming

Project names are automatically generated using the pattern:
```
{Game Name} - Game Translation ({Target Languages})
```

Example: `Total War: WARHAMMER III - Game Translation (French, German, Spanish)`

---

### Working with Game Translation Projects

Once created, game translation projects function identically to mod translation projects.

#### Project Detail Screen

Navigate to a game translation project to see:

- **Overview Section** — Project metadata and delete option
- **Target Languages Section** — Progress for each language with editor access
- **Translation Statistics** — Aggregate statistics across all languages

#### Translation Editor

Open the Translation Editor for any target language to:

- View and edit translations
- Run AI-assisted batch translation
- Validate translations
- Generate output packs

> **Note:** Game translation projects typically contain hundreds of thousands of entries. Use filters and search to navigate efficiently.

---

### Output and Export

#### Generate Pack

When you generate a pack from a game translation project:

1. Click **Generate pack** in the Translation Editor
2. TWMT creates a localization pack with your translations
3. The pack is saved to the game's `data` folder

#### Output Naming

Generated packs follow the pattern:
```
!!!!!!!!!!_{language_code}_translation_twmt.pack
```

The leading exclamation marks ensure the translation pack loads after the base game files, allowing your translations to override the defaults.

#### Pack Priority

| Pack Type | Load Order | Override Behavior |
|-----------|------------|-------------------|
| Base game (`local_*.pack`) | Early | Original text |
| Translation pack (`!!!!...*.pack`) | Late | Overrides base text |

---

### Tips and Best Practices

> 1. **Start with English Source** — English packs typically have the most complete text coverage
>
> 2. **Plan for Scale** — Game translation projects can have 200,000+ entries; budget time accordingly
>
> 3. **Use Translation Memory** — TM is especially valuable for game translation due to repeated phrases
>
> 4. **Build Glossaries First** — Create comprehensive glossaries before starting to ensure consistent terminology
>
> 5. **Translate in Phases** — Focus on high-visibility text first (UI, menus, common dialogs)
>
> 6. **Test In-Game Regularly** — Generate packs periodically and test in-game to catch issues early
>
> 7. **Use Filters** — The data grid filters help navigate large translation sets efficiently
>
> 8. **Leverage AI Batch Translation** — AI translation is especially efficient for the repetitive patterns in game text
>
> 9. **Validate Before Release** — Run validation to catch tag mismatches and formatting issues

---

## Mods Screen

The Mods screen is the starting point for discovering and managing Steam Workshop mods that can be translated. It automatically scans your Steam Workshop folders to find mods containing localization files.

![](assets/screenshots/screen_mods.png)

### Purpose

The Mods screen allows you to:

- Discover mods subscribed via Steam Workshop that contain translatable text
- View mod details including name, subscriber count, and last update date
- Track which mods have already been imported as translation projects
- Monitor update status and detect when mod authors publish new versions
- Create translation projects directly from detected mods

### Scanning for Mods

When you navigate to the Mods screen, TWMT automatically scans your configured Steam Workshop folders for mods containing localization (`.loc`) files.

**Initial scan behavior:**

1. TWMT reads the Workshop folder path from your game installation settings
2. It scans each mod directory for pack files
3. Pack files are analyzed using RPFM to detect localization content
4. Steam Workshop API is queried to retrieve mod metadata (name, image, subscribers, update date)
5. Results are cached to speed up subsequent scans

**Manual refresh:**

- Click the **Refresh** button (circular arrow icon) in the toolbar to rescan for mods
- A terminal-style progress window displays scan progress in real-time
- Useful after subscribing to new mods or when Steam has downloaded mod updates

### Data Grid Columns

| Column | Description |
|--------|-------------|
| Image | Mod thumbnail from Steam Workshop |
| ID | Steam Workshop ID (numeric identifier) |
| Mod Name | Name of the mod as shown on Steam |
| Subs | Number of Steam subscribers |
| Last Updated | Time since the mod was last updated on Steam Workshop |
| Status | Import status ("Imported" or "Not Imported") |
| Changes | Update analysis for imported mods |
| Hide | Checkbox to hide mods from the list |

> **Tip:** Click any column header to sort the list by that column.

### Filtering and Search

The toolbar provides several filtering options:

**Search box:**
- Type to filter mods by name or Workshop ID
- The counter shows "X / Y mods" where X is filtered results and Y is total mods

**Filter chips:**

| Filter | Description |
|--------|-------------|
| All | Show all mods (default) |
| Not imported | Show only mods without translation projects |
| Needs update | Show only mods with pending updates or changes |

**Hidden mods toggle:**
- Click the **Hidden** button to switch between viewing normal and hidden mods
- The badge shows the count of hidden mods
- Use this to organize mods you are not interested in translating

### Understanding Update Status

The Mods screen tracks three types of update status indicators:

| Status | Icon | Description |
|--------|------|-------------|
| **Up to date** | Checkmark | The mod is current and synchronized with your project. No action required. |
| **Download required** | Red download | Steam Workshop has a newer version than your local file. Launch the game to download the update. |
| **Changes detected** | Orange sync | The local file is current, but translation differences were detected. |

> **Quick fix for "Download required":** Click the badge in the Changes column to delete the local file and force a redownload.

### Creating a Translation Project

To create a translation project from a detected mod:

1. **Click on a mod row** in the data grid
2. If the mod is not yet imported:
   - TWMT validates that RPFM schema is configured
   - A project is created with your default target language
   - An initialization dialog shows progress as localization files are extracted
   - You are redirected to the project detail screen upon completion
3. If the mod is already imported:
   - You are redirected to the existing project

**Requirements:**
- RPFM CLI path must be configured in Settings
- RPFM schema path must be configured in Settings
- The mod must contain at least one `.loc` file with translatable content

### Hiding Mods

To keep your mod list organized, you can hide mods you do not want to translate:

1. Check the checkbox in the **Hide** column for the mod
2. The mod moves to the hidden list
3. Toggle **Hidden** in the toolbar to view hidden mods
4. Uncheck the checkbox to restore a mod to the main list

> **Note:** Hidden mods are still tracked for updates but are not shown in the default view.

### Pending Changes Notification

When imported projects have pending mod updates that affect translations, a warning badge appears in the toolbar:

- **"X projects pending"**: Number of projects with unreviewed changes
- Click the badge to navigate to the Projects screen with the "Needs update" filter active

---

### Tips and Best Practices

> 1. **Regular scanning** — Scan periodically to catch mod updates, especially before releasing translation packs
>
> 2. **Hide irrelevant mods** — Use the hide feature for mods without text content or those you do not plan to translate
>
> 3. **Check before downloading** — If "Download required" appears, review what changed before updating (hover for details)
>
> 4. **Batch project creation** — For multiple mods, create projects in sequence from the Mods screen
>
> 5. **Use filters** — The "Needs update" filter quickly shows which mods require attention
>
> 6. **Workshop metadata** — Subscriber count helps prioritize popular mods for translation

## Projects Screen

The Projects screen is the central hub for managing your translation projects. It provides a comprehensive overview of all translation work organized by game and allows you to track progress, manage target languages, and access the Translation Editor.

![](assets/screenshots/screen_projects.png)

### Projects List Screen

The main Projects screen displays all translation projects for the currently selected game as interactive cards.

#### Purpose

- View all translation projects at a glance
- Track translation progress across multiple languages
- Filter and sort projects by various criteria
- Navigate to project details or directly to the Translation Editor
- Monitor projects that require attention due to mod updates

#### Project Cards

Each project is displayed as a card containing:

| Element | Description |
|---------|-------------|
| Mod Image | Preview thumbnail from the mod directory or a game-specific fallback icon |
| Project Name | Name of the translation project |
| Steam Workshop ID | Cloud icon with the mod's Steam Workshop numeric ID |
| Status Badge | Update status indicator |
| Language Progress | Progress bars showing translation completion percentage for each target language |

**Progress Bar Colors:**

| Color | Range | Status |
|-------|-------|--------|
| Green | 100% | Complete |
| Blue | 50-99% | In progress |
| Orange | 1-49% | Started |
| Gray | 0% | Not started |

#### Status Badges

| Badge | Icon | Description |
|-------|------|-------------|
| **Up to date** | Green checkmark | The project is synchronized with the source mod |
| **Mod updated** | Orange sync | The project was impacted by a mod update |
| **Changes detected** | Warning | Pending changes from mod source that need to be applied |

#### Toolbar and Filtering

**Search Box:**
- Type to filter projects by name or Steam Workshop ID
- Click the X button to clear the search

**Quick Filter Buttons:**

| Filter | Description |
|--------|-------------|
| Needs Update | Projects requiring attention due to mod source changes |
| Incomplete | Projects not yet 100% translated in all configured languages |
| Has Complete | Projects with at least one language fully translated |

> **Tip:** Click a filter button to activate it, click again to deactivate. When a filter is active, a "Clear" button appears to reset all filters.

**Sort Options:**

- **Name** — Alphabetical order
- **Date Modified** — Most recently updated first (default)
- **Progress** — Overall translation completion percentage

#### Navigation

- **Click a project card** — Navigate to the Project Detail screen
- **Empty state** — If no projects exist or match filters, a message suggests going to the Mods screen to create projects

---

### Project Detail Screen

The Project Detail screen provides comprehensive information about a single project and is the gateway to translation work.

![](assets/screenshots/screen_project_overview.png)

#### Project Overview Section

The top section displays:

- **Steam Workshop ID** — The mod's numeric identifier with a button to open the Steam Workshop page in your browser
- **Delete Project button** — Red trash icon to permanently delete the project (requires confirmation)

#### Target Languages Section

This section lists all configured target languages for the project.

**Language Card Elements:**

| Element | Description |
|---------|-------------|
| Language Name | Full display name (e.g., "French", "German", "Spanish") |
| Language Code | ISO code in uppercase (e.g., "FR", "DE", "ES") |
| Status Badge | Pending, Translating, or Completed based on progress |
| Progress Bar | Visual representation of translation completion |
| Progress Percentage | Numeric percentage with color coding |
| Unit Count | "X / Y units translated" showing translated vs total |
| Open Editor Button | Blue button to launch the Translation Editor for this language |
| Delete Button | Trash icon to remove this language from the project |

**Status Badge Values:**

| Status | Icon | Progress |
|--------|------|----------|
| Pending | Clock | 0% |
| Translating | Translate | 1-99% |
| Completed | Checkmark | 100% |

**Add Language Button:**

1. Click "Add Language" in the section header
2. Select one or more languages from the available list
3. Languages already in the project are filtered out
4. Click "Add Languages" to create translation version entries

#### Translation Statistics Section

The right panel displays project-wide statistics:

| Statistic | Description |
|-----------|-------------|
| Total Units | Number of translation units in the project |
| Translated | Units with completed translations (green) |
| Pending | Units awaiting translation (orange) |
| Validated | Units that have been validated/reviewed (blue) |
| Errors | Units with translation errors (red) |
| TM Reuse Rate | Percentage of translations matched from Translation Memory |
| Tokens Used | Estimated LLM tokens consumed (approx. 150 per translation) |

#### Available Actions

**From the Target Languages section:**
- **Open Editor** — Launch the Translation Editor for a specific language
- **Delete Language** — Remove a target language and all its translations (confirmation required)

**From the Overview section:**
- **Open in Steam** — View the original mod on Steam Workshop
- **Delete Project** — Permanently delete the project and all associated data

**Navigation:**
- **Back Arrow** — Return to the Projects list screen

---

### Creating Projects

Projects are created from the Mods screen by clicking on a detected mod.

When creating, TWMT automatically:

1. Extracts localization files from the .pack file using RPFM
2. Imports translation units into the database
3. Creates translation version entries for each target language
4. Shows real-time progress with a log viewer

### Editing Projects

Click the **Open Editor** button via the project detail screen to access the Translation Editor screen.

---

### Tips and Best Practices

> 1. **Organize by Game** — TWMT automatically filters projects by the selected game in the sidebar
>
> 2. **Use Quick Filters** — The "Needs Update" filter helps identify projects requiring attention after mod updates
>
> 3. **Monitor Progress** — Use the "Incomplete" filter to find projects that need more translation work
>
> 4. **Add Languages Early** — Add all target languages before starting translation to ensure Translation Memory benefits all languages
>
> 5. **Review After Updates** — When you see the "Mod updated" badge, review the project to check for new or modified source texts
>
> 6. **Check Statistics** — The TM Reuse Rate indicates how effectively Translation Memory is reducing AI costs

## Translation Editor

The Translation Editor is the primary workspace for translating mod content. It provides a comprehensive interface for manual editing, AI-assisted batch translation, and quality validation.

![](assets/screenshots/screen_editor.png)

### Overview

The Translation Editor screen consists of three main areas:

1. **Top Toolbar** — LLM model selection, translation controls, and search
2. **Left Sidebar** — Status filters, TM source filters, and statistics
3. **Main Data Grid** — All translation units with inline editing capabilities

---

### Toolbar

#### LLM Model Selector

A dropdown showing all configured and enabled LLM models:

- Displays models in format: `Provider: Model Name` (e.g., "OpenAI: GPT-5.1")
- The selected model is used for all AI translation operations
- Model selection persists during the session
- If no model is selected, the default model for the active provider is used

#### Skip TM Checkbox

Toggle to bypass Translation Memory lookup:

| State | Behavior |
|-------|----------|
| Unchecked (default) | Translation Memory is consulted first; only unmatched units are sent to LLM |
| Checked | All units are sent directly to the LLM, bypassing TM lookup |

> **Note:** The checkbox is highlighted in red when active to indicate non-standard behavior. Useful for retranslating content with updated glossary or prompt rules.

#### Settings Button

Opens the Translation Settings dialog:

| Setting | Description | Range |
|---------|-------------|-------|
| Units per batch | Number of translation units per LLM request | 1-1000 or Auto |
| Parallel batches | Number of concurrent LLM requests | 1-20 |

> **Recommendation:** Use **Auto mode** — TWMT calculates optimal batch size based on token limits for each request. Use manual mode with lower values (e.g., 10) if you experience timeout errors.

#### Mod Rule Button

Create or edit a mod-specific translation rule:

- **No rule** — Button appears with outline style
- **Rule exists** — Button appears highlighted with filled style

**Mod Rule Editor:**
- Enter custom instructions specific to this mod
- Example: "This mod uses fantasy names that should not be translated"
- The rule is appended to global translation rules for every LLM request
- Toggle enable/disable without deleting the rule

#### Action Buttons

| Button | Description |
|--------|-------------|
| Translate All | Translate all untranslated units in the project |
| Translate Selected | Translate only the selected units (enabled when rows are selected) |
| Validate | Run validation on all translations and open the Validation Review screen |
| Generate pack | Export translations to a .pack file for game use |

#### Search Field

- Type to filter translations by key, source text, or translated text
- Search is case-insensitive and matches partial text
- Click the X icon to clear the search

---

### Left Sidebar

#### Status Filters

Filter translations by their current status:

| Status | Icon | Description |
|--------|------|-------------|
| Pending | Circle | Units with no translation yet |
| Translated | Checkmark | Units with completed translations |
| Needs Review | Warning | Units flagged for review (validation issues detected) |

> **Tip:** Click a filter to toggle it on/off. Multiple filters can be active simultaneously.

#### TM Source Filters

Filter by how the translation was obtained:

| Source | Description |
|--------|-------------|
| Exact Match | Translation from TM with 100% source text match |
| Fuzzy Match | Translation from TM with similarity above threshold |
| LLM | Translation generated by AI model |
| Manual | Translation entered or edited by user |
| None | No translation yet |

#### Statistics Panel

Real-time statistics for the current language:

| Statistic | Description |
|-----------|-------------|
| Total | Total number of translation units |
| Pending | Units awaiting translation |
| Translated | Units with completed translations |
| Needs Review | Units with validation issues |

A progress bar shows overall completion percentage.

#### Clear Filters Button

Appears when any filter is active. Click to reset all filters and show all translation units.

---

### Data Grid

The main data grid displays all translation units:

| Column | Description |
|--------|-------------|
| Checkbox | Select rows for batch operations |
| Status | Visual indicator of translation status |
| Loc File | Name of the source .loc file containing this unit |
| Key | Unique identifier for the translation entry |
| Source Text | Original text to be translated |
| Translated Text | Target language translation (editable) |
| TM Source | Origin of the translation |

#### Column Features

- **Sorting** — Click any column header to sort
- **Resizing** — Drag column borders to resize
- **Auto-height** — Rows automatically adjust height to fit multiline text

#### Row Selection

| Action | Result |
|--------|--------|
| Click checkbox | Toggle selection for single row |
| Click header checkbox | Select/deselect all visible rows |
| Ctrl+Click | Add/remove individual row from selection |
| Shift+Click | Select range from last clicked row |

The header checkbox shows:
- Empty: No rows selected
- Checkmark: All rows selected
- Dash: Some rows selected (indeterminate state)

#### Inline Editing

To edit a translation directly in the grid:

1. Double-click the Translated Text cell, or
2. Right-click and select "Edit" from the context menu
3. Type or modify the translation
4. Press **Enter** to save or **Escape** to cancel

**Special character handling:**
- Newlines are displayed as `\n` in the editor
- Type `\n` to insert an actual newline
- Other escape sequences: `\r\n`, `\r`, `\t`

---

### Context Menu

Right-click any row to access the context menu:

| Option | Description |
|--------|-------------|
| Edit | Open inline editor for the translated text cell |
| Select All | Select all visible rows |
| Force Retranslate | Send selected units to LLM even if already translated |
| Mark as Translated | Set selected units status to "Translated" |
| Clear Translation | Remove translated text from selected units |
| View History | Open history dialog showing all changes to this translation |
| View Prompt | Preview the exact LLM prompt that would be sent for this unit |
| Delete | Delete selected translation units (requires confirmation) |

> **Note:** If you right-click a row not in the current selection, that row becomes the only selected row. Actions with count (e.g., "Clear Translation (5)") show number of affected rows.

---

### AI Translation

#### Translate All

Translates all untranslated units in the project:

1. Click "Translate All" in the toolbar
2. TWMT identifies all units with status "Pending"
3. If no untranslated units exist, an info dialog appears
4. Confirm the number of units to translate
5. The Translation Progress screen opens

#### Translate Selected

Translates only the selected rows:

1. Select one or more rows using checkboxes
2. Click "Translate Selected" in the toolbar
3. TWMT filters to only untranslated units among selection
4. Confirm the number of units to translate
5. The Translation Progress screen opens

#### Force Retranslate

Retranslate units that already have translations:

1. Select one or more rows
2. Right-click and choose "Force Retranslate"
3. Confirm the warning that existing translations will be overwritten
4. The Translation Progress screen opens

> **When to use Force Retranslate:**
> - Glossary was updated and you want consistent terminology
> - Mod rule was added or modified
> - LLM model was changed to a better one
> - Previous translations had quality issues

---

### Translation Progress Screen

When AI translation starts, a full-screen progress view appears.

#### Progress Display

| Element | Description |
|---------|-------------|
| Project Name | Shows which project is being translated |
| Phase | Current translation phase (Preparing, Translating, Finalizing) |
| Progress Bar | Visual progress indicator with percentage |
| Completed/Total | Count of completed vs total units |
| Elapsed Time | Time since translation started |

#### Statistics Cards

| Card | Description |
|------|-------------|
| TM Matches | Units matched from Translation Memory (saved API cost) |
| LLM Translated | Units translated by the AI model |
| Errors | Units that failed translation (will be retried) |

#### Log Terminal

A real-time terminal view showing:
- Translation progress events
- LLM responses
- Error messages with details
- Timing information

#### Stop Button

Click "Stop" to gracefully cancel the translation:
- Current batch completes
- Progress is saved
- You can resume later with "Translate All"

> **Important:** You cannot navigate away from this screen during active translation. Click "Stop" first if you need to leave.

#### Auto-close Behavior

When translation completes:
1. Statistics are displayed for 2-3 seconds
2. Screen automatically closes
3. Data grid refreshes to show new translations

---

### Translation Memory Integration

#### Automatic TM Lookup

Before sending units to the LLM:

1. Each source text is checked against Translation Memory
2. Exact matches (100% similarity) are applied automatically
3. Fuzzy matches are suggested

#### TM Source Column

| Value | Meaning |
|-------|---------|
| Exact Match | 100% match from TM, applied automatically |
| Fuzzy Match | Partial match from TM, used as reference |
| LLM | Generated by AI translation |
| Manual | Typed directly by user |
| None | No translation yet |

#### Skip TM Option

Enable "Skip TM" in the toolbar to bypass TM lookup:
- All units sent directly to LLM
- Useful when TM contains outdated translations
- TM is still updated with new translations

---

### Glossary Integration

Glossary terms are automatically incorporated into translation prompts.

#### How It Works

1. When translation starts, glossary entries for the target language are loaded
2. Entries include both global glossary and game-specific terms
3. Terms are included in the LLM system prompt
4. The AI is instructed to use glossary translations consistently

#### Term Matching

- Source terms are matched in the text being translated
- Both case-sensitive and case-insensitive matching supported
- Multiple variants of a term can have different translations

---

### Validation

#### Validate Button

Click "Validate" in the toolbar to:
1. Run validation checks on all translations
2. Open the Validation Review screen with results

#### Validation Review Screen

**Header:**
- Total validated count
- Error count (red)
- Warning count (orange)
- Passed count (green)
- Export report button

**Filters:**
- All issues
- Errors only
- Warnings only
- Search by key, text, or description

**Data Grid Columns:**

| Column | Description |
|--------|-------------|
| Checkbox | Select for bulk operations |
| Severity | Error or Warning icon |
| Issue Type | Category of the issue |
| Key | Translation unit key |
| Description | What the issue is |
| Source Text | Original text |
| Translation | Current translation |
| Actions | Accept, Reject, Edit buttons |

**Actions per issue:**
- **Accept** — Mark as reviewed, keep translation
- **Reject** — Clear translation, mark for retranslation
- **Edit** — Open dialog to fix the translation

**Bulk operations:**
- Select multiple issues with checkboxes
- "Accept All Selected" or "Reject All Selected"

#### Issue Types

| Issue Type | Severity | Description |
|------------|----------|-------------|
| Missing Tags | Error | Source has markup tags not present in translation |
| Extra Tags | Error | Translation has tags not in source |
| Mismatched Tags | Error | Tag structure differs between source and translation |
| Length Warning | Warning | Translation is significantly longer/shorter than source |
| Untranslated | Warning | Translation matches source text exactly |
| Format Specifiers | Error | Printf-style specifiers (%s, %d) differ |

---

### View History

View the complete change history for any translation:

1. Right-click a row and select "View History"
2. The Translation History dialog opens

**History Entry Information:**
- Timestamp of change
- Status at that time (Pending, Translated, Needs Review)
- Changed by (Manual, LLM, TM)
- The translation text at that point
- Change reason (if recorded)

> **Use cases:** Recover a previous translation version, understand when and how a translation changed, audit translation workflow.

---

### View Prompt

Preview the exact prompt sent to the LLM for any translation unit:

1. Right-click a row and select "View Prompt"
2. The Prompt Preview dialog opens

**Tabs:**
- **System Prompt** — Instructions, context, glossary terms
- **User Message** — The actual translation request with source text
- **API Payload** — Complete JSON payload for each configured provider

**Features:**
- Token count estimate
- Copy buttons for each section
- Provider selector to view different API formats

> **Use cases:** Debug translation issues, understand how glossary and rules affect prompts, share prompts for external review.

---

### Generate Pack

Export translations directly to a game-ready pack file:

1. Click "Generate pack" in the toolbar
2. The Export Progress screen opens

**Export Progress:**
- Shows current step (Preparing, Generating .loc files, Creating pack)
- Progress bar with percentage
- Log terminal with details
- Elapsed time

**On completion:**
- Output path displayed
- Entry count shown
- Click "Close" to return to editor

> **Note:** The generated pack is saved to the project's output folder and is ready to be placed in the game's data folder.

---

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Enter | Save current cell edit |
| Escape | Cancel current cell edit |
| Ctrl+A | Select all visible rows |
| Ctrl+Z | Undo last action |
| Ctrl+Y | Redo last undone action |

---

### Tips and Best Practices

> 1. **Use filters effectively** — Large mods may have thousands of units. Use status filters to focus on pending translations.
>
> 2. **Check TM matches** — Review "Exact Match" and "Fuzzy Match" translations to ensure they fit the context.
>
> 3. **Configure optimal batch settings** — Auto mode works well for most cases. If you experience timeouts, reduce units per batch.
>
> 4. **Add mod rules for unique content** — If a mod has special terminology or style requirements, create a mod-specific rule.
>
> 5. **Validate before exporting** — Always run validation to catch missing tags or format issues that could break the game.
>
> 6. **Review LLM translations** — AI translations are generally good but may miss context. Spot-check critical dialogue.
>
> 7. **Use force retranslate sparingly** — It consumes API tokens. Use it when glossary updates or quality issues require it.
>
> 8. **Export regularly** — Generate pack files periodically to test translations in-game.
>
> 9. **Check the history** — If a translation seems wrong, check history to understand when it changed.
>
> 10. **Preview prompts for debugging** — If translations are consistently wrong, preview the prompt to check if rules and glossary are correct.

## Pack Compilation

The Pack Compilation feature allows you to combine translations from multiple projects into a single `.pack` file. This is essential for distributing translation packs that cover multiple mods in one convenient download.

![](assets/screenshots/screen_compilation.png)

### Purpose and Overview

#### What is a Compilation Pack?

A compilation pack is a combined translation file that merges translations from multiple individual mod projects into a single `.pack` file. Instead of requiring users to download separate translation files for each mod, a compilation pack provides all translations in one package.

#### Why Use Compilation Packs?

| Benefit | Description |
|---------|-------------|
| **Simplified Distribution** | Users download one file instead of many |
| **Consistent Load Order** | A single pack with a controlled prefix ensures proper game loading |
| **Community Collections** | Create translation packs for themed mod collections |
| **Easier Maintenance** | Update multiple translations by regenerating a single compilation |
| **Steam Workshop Publishing** | Generate BBCode links automatically for your Workshop description |

#### Overall Workflow

```
1. Create individual translation projects for each mod
2. Translate each project to your desired completion level
3. Create a new compilation and select the projects to include
4. Configure the compilation settings (name, prefix, language)
5. Generate the combined pack file
6. Distribute the pack file or upload to Steam Workshop
```

---

### Compilation List Screen

When you navigate to Pack Compilations from the sidebar, you see the main compilation list screen.

#### Header

- **Title**: "Pack Compilations" with an icon
- **New Compilation Button**: Click to create a new compilation

#### Compilation Cards

Each existing compilation is displayed as a card:

| Element | Description |
|---------|-------------|
| Icon | Box icon indicating a compilation pack |
| Name | The compilation name you assigned |
| Project Count | Number of projects included (e.g., "5 projects") |
| Game | The game this compilation is for |
| Pack Filename | The output filename in monospace format |

#### Card Actions

Hover over a compilation card to reveal action buttons:

| Button | Description |
|--------|-------------|
| Generate Pack | Regenerate the pack file with current translations |
| Edit | Open the compilation editor to modify settings |
| Delete | Remove the compilation (does not delete projects or generated files) |

---

### Creating a New Compilation

Click "New Compilation" in the header to open the compilation editor.

**Prerequisites:**

1. Select a game in the sidebar (compilations are game-specific)
2. Ensure you have translation projects with translations in your target language
3. Verify RPFM is configured in Settings (required for pack generation)

---

### Compilation Editor

The compilation editor is divided into two main panels:

- **Left Panel** — Configuration settings, action buttons, and BBCode section
- **Right Panel** — Project selection list

#### Configuration Section

##### Compilation Name

A descriptive name for your compilation (e.g., "French SFO Translation Pack").
- Used for display purposes only
- Does not affect the output filename

##### Language

Select the target language for this compilation:
- Dropdown lists all available languages
- Only projects with translations in the selected language will be shown
- Changing the language automatically updates the prefix and clears project selection

##### Prefix

The filename prefix that determines load order in Total War games:
- Auto-generated based on language (e.g., `!!!!!!!!!!_fr_compilation_twmt_`)
- The exclamation marks ensure the pack loads early in the game's load order
- Can be customized if needed

> **Important:** Total War games load packs in alphabetical order. Packs with more leading exclamation marks load first, allowing translation packs to override original mod text.

##### Pack Name

The base name for your pack file (e.g., `my_translations`):
- Combined with prefix to create the full filename
- Should use lowercase letters and underscores
- Avoid spaces and special characters

##### Output Filename Preview

Displays the complete filename:

```
{prefix}{pack_name}.pack
```

Example: `!!!!!!!!!!_fr_compilation_twmt_my_translations.pack`

---

### Project Selection

The right panel displays all available projects for the selected language.

#### Project Requirements

A project appears in the selection list when:
1. It belongs to the currently selected game
2. It has translations in the selected language

#### Selection Controls

| Control | Description |
|---------|-------------|
| Select All | Select all available projects |
| Deselect All | Clear all selections |
| Individual Checkbox | Toggle selection for a single project |

#### Project Information

Each project item displays:

| Element | Description |
|---------|-------------|
| Checkbox | Selection state |
| Mod Image | Thumbnail from the mod |
| Project Name | Name of the translation project |
| Progress Bar | Translation completion percentage |
| Progress Percent | Numeric percentage value |

**Progress Color Coding:**

| Color | Range |
|-------|-------|
| Green | 100% |
| Blue | 50-99% |
| Orange | 1-49% |
| Gray | 0% |

---

### Action Section

Located below the configuration section.

#### Messages

- **Error Messages** — Displayed in red when validation fails
- **Success Messages** — Displayed in green when operations complete successfully

#### Buttons

| Button | Description |
|--------|-------------|
| Save | Save the compilation configuration without generating |
| Generate Pack | Save and generate the combined pack file |

#### Validation Requirements

To enable the Save and Generate buttons:

- Name must not be empty
- Language must be selected
- Prefix must not be empty
- Pack name must not be empty
- At least one project must be selected
- A game must be selected in the sidebar

---

### BBCode Section

When projects are selected, the BBCode section appears below the action buttons.

#### Purpose

Generates BBCode-formatted links for Steam Workshop descriptions. When you publish a compilation pack, you can include links to all the original mods.

#### Generated Format

```bbcode
[url=https://steamcommunity.com/sharedfiles/filedetails/?id={steam_id}]{mod_name}[/url]
```

**Example output:**

```bbcode
[url=https://steamcommunity.com/sharedfiles/filedetails/?id=2787468514]SFO Grimhammer III[/url]
[url=https://steamcommunity.com/sharedfiles/filedetails/?id=2789948771]Legendary Lore[/url]
[url=https://steamcommunity.com/sharedfiles/filedetails/?id=2790683844]Mixu's Tabletop Lords[/url]
```

#### Copy Functionality

- Click the "Copy" button to copy the BBCode to your clipboard
- Button shows "Copied!" with a checkmark for 2 seconds after copying
- Paste directly into your Steam Workshop description

---

### Generating Compilation Packs

#### Generation Process

When you click "Generate Pack":

1. **Saving** — If this is a new compilation, it is saved first
2. **Preparation** — The system prepares a temporary directory for processing
3. **Project Processing** — Each selected project is processed sequentially
4. **Pack Creation** — RPFM creates the combined pack file with all localization entries
5. **Cleanup** — Temporary files are removed

#### Progress Display

During generation, the editor switches to a progress view:

| Element | Description |
|---------|-------------|
| Spinner | Indicates active processing |
| Title | "Generating Pack..." |
| Progress Bar | Visual progress indicator |
| Percentage | Numeric completion percentage |
| Current Step | Description of current operation |
| Selection Summary | Number of projects being processed |
| Stop Button | Cancel the generation |
| Log Terminal | Real-time output of processing steps |

#### Progress Steps

1. **Preparing...** (0-5%)
2. **Processing: {Project Name} (X/Y)** (5-80%)
3. **Creating pack file...** (80-95%)
4. **Completed!** (100%)

#### Output Location

The generated pack file is saved to:

```
{game_installation_path}/data/{prefix}{pack_name}.pack
```

> **Note:** This location ensures the pack is immediately usable in the game without manual file moving.

---

### Editing Compilations

To edit an existing compilation:

1. Click anywhere on the compilation card, or
2. Hover and click the "Edit" button

The editor opens with all existing settings loaded.

---

### Deleting Compilations

To delete a compilation:

1. Hover over the compilation card
2. Click the "Delete" button (trash icon)
3. Confirm in the dialog

> **Important:**
> - Deleting a compilation does NOT delete the included projects
> - Deleting a compilation does NOT delete previously generated pack files
> - This action only removes the compilation configuration

---

### Quick Generate

Regenerate a compilation pack without entering the editor:

1. Hover over the compilation card
2. Click the "Generate Pack" button (sync icon)
3. Wait for generation to complete
4. A success or error notification appears

---

### Tips and Best Practices

> 1. **Plan Your Compilations** — Group mods logically (e.g., by theme, author, or mod series)
>
> 2. **Use Descriptive Names** — Name compilations clearly so users know what is included
>
> 3. **Keep Translations Updated** — Before generating, ensure all included projects have up-to-date translations
>
> 4. **Test the Output** — After generating, launch the game to verify translations load correctly
>
> 5. **Document Included Mods** — Use the generated BBCode in your Steam Workshop description
>
> 6. **Mind the Prefix** — The default prefix ensures proper load order; only change it if you understand the implications
>
> 7. **Regenerate After Changes** — If you update translations in any included project, regenerate the compilation
>
> 8. **One Language Per Compilation** — Each compilation targets a single language; create separate compilations for different languages
>
> 9. **Check Project Completion** — The progress bars help identify projects that may need more translation work
>
> 10. **Backup Generated Packs** — Keep copies of generated packs before regenerating

## Glossary

The Glossary feature enables consistent terminology translation by defining how specific terms should be translated. This is essential for maintaining quality and coherence across translations.

![](assets/screenshots/screen_glossary.png)

### Purpose and Overview

#### What is a Glossary?

A glossary is a collection of term pairs that define how specific source terms should be translated into a target language.

**Example:**

| Source Term | Target Term (French) |
|-------------|---------------------|
| Empire | Empire |
| Chaos | Chaos |
| Bretonnian | Bretonnien |
| High Elves | Hauts Elfes |

#### Why Use Glossaries?

| Benefit | Description |
|---------|-------------|
| **Consistency** | Same term always translated the same way |
| **Accuracy** | Prevents AI from inventing translations for proper nouns |
| **Context** | Notes provide hints about gendered terms or contextual usage |
| **Efficiency** | Reduces manual correction of recurring terminology errors |

#### How Glossary Terms Are Used During AI Translation

1. Glossary entries for the target language are loaded
2. Both universal and game-specific glossaries are included
3. Terms are embedded in the LLM system prompt with their translations
4. The AI is instructed to use glossary translations consistently
5. Notes provide additional context

---

### Glossary Types

TWMT supports two types of glossaries:

#### Universal Glossaries

- Shared across **all games and all projects**
- Ideal for common terms that appear in multiple Total War games
- Examples: "Chaos", "Empire", "Lord", "Hero"
- Marked with a globe icon

#### Game-Specific Glossaries

- Shared across **all projects of one game**
- Ideal for terms unique to a specific game
- Examples: "Kislev" (Warhammer III), "Pontus" (Rome II)
- Marked with a game controller icon
- Requires selecting a game when creating

---

### Glossary List Screen

#### Header

- **Title**: "Glossary Management" with a book icon
- **New Glossary Button**: Click to create a new glossary

#### Glossary Cards

| Element | Description |
|---------|-------------|
| Type Icon | Globe (universal) or game controller (game-specific) |
| Name | The glossary name |
| Type Badge | "Universal" or the game name |
| Entry Count | Number of term pairs in the glossary |
| Description | Optional description (if provided) |
| Last Updated | Time since last modification |
| Delete Button | Red trash icon to delete the glossary |

#### Card Grouping

1. **Universal Glossaries** — Listed first, sorted alphabetically
2. **Game-specific Glossaries** — Listed second, sorted alphabetically

---

### Creating a New Glossary

Click "New Glossary" in the header to open the creation dialog.

#### Creation Form Fields

| Field | Description |
|-------|-------------|
| Name | Unique name for the glossary (required, max 100 characters) |
| Description | Optional description (max 300 characters) |
| Scope | Universal (all games) or Game-specific |
| Game | Required only for game-specific glossaries |
| Target Language | The language for target translations (required) |

---

### Glossary Editor View

When you select a glossary, the screen changes to the editor view with three main areas:

1. **Header** — Glossary name, type, and action buttons
2. **Left Panel** — Statistics panel
3. **Main Area** — Search toolbar and data grid

#### Editor Header

| Element | Description |
|---------|-------------|
| Back Button | Returns to the glossary list |
| Type Icon | Globe or game controller |
| Glossary Name | The name of the glossary |
| Type Label | "Universal Glossary" or "Game: [Game Name]" |
| Import Button | Import entries from file |
| Export Button | Export entries to file |
| Delete Button | Delete the glossary (red) |

---

### Statistics Panel

#### Overview Statistics

| Statistic | Description |
|-----------|-------------|
| Total Entries | Number of term pairs in the glossary |

#### Usage Statistics

| Statistic | Description |
|-----------|-------------|
| Used in translations | Entries that matched source text during translation |
| Unused | Entries that have not been used in any translation |
| Usage rate | Percentage of entries that have been used |

#### Quality Metrics

| Statistic | Description |
|-----------|-------------|
| Duplicates | Number of duplicate entries detected (highlighted in red if > 0) |
| Missing translations | Entries without target terms (highlighted in red if > 0) |

---

### Glossary Data Grid

| Column | Description |
|--------|-------------|
| Source Term | The original term to match in source text |
| Target Term | The translation to use in the target language |
| Case | Indicates if matching is case-sensitive |
| Actions | Edit and delete buttons for each entry |

---

### Adding and Editing Entries

#### Adding a New Entry

1. Click "Add Entry" in the toolbar
2. Fill in the entry form:

| Field | Description |
|-------|-------------|
| Source Term | The term to match (required, max 200 characters) |
| Target Term | The translation (required, max 200 characters) |
| Notes | Optional hints for the AI translator (max 500 characters) |
| Case Sensitive | If checked, matches exact case only |

3. Click "Save"

#### Notes Field

The Notes field provides context to the AI translator:

- "Bretonnian is not gendered in English but can be Bretonnien/Bretonnienne in French"
- "This is a proper noun and should not be translated"
- "Use formal tone for this term"

#### Case Sensitivity

| Setting | Behavior |
|---------|----------|
| Enabled | "Emperor" and "emperor" are treated as different terms |
| Disabled (default) | "Emperor", "emperor", and "EMPEROR" all match the same entry |

---

### Search and Filter

#### Search Box

- Type to filter by source term or target term
- Matching is case-insensitive
- Click the X icon to clear the search
- Results update in real-time

---

### Import and Export

#### Supported Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| CSV | .csv | Comma-separated values |
| TBX | .tbx | TermBase eXchange (industry standard) |
| Excel | .xlsx | Excel workbook format |

#### Import Process (CSV)

1. Click "Import" in the editor header
2. Click to select a CSV file
3. Select the target language
4. Choose whether to skip duplicates (recommended)
5. Click "Import"
6. View the import summary

**CSV Format Requirements:**
- Two columns: source_term, target_term
- UTF-8 encoding recommended
- Header row optional

#### TBX Format

TBX (TermBase eXchange) is an industry-standard XML format:
- Compatible with other CAT tools
- Supports multiple languages in a single file
- Preserves metadata like notes and case sensitivity

---

### Integration with Translation

#### Automatic Term Matching

During AI translation:
1. Source text is scanned for glossary terms
2. Matching entries are included in the translation prompt
3. The AI is instructed to use the specified translations
4. Notes provide additional context for ambiguous terms

#### Term Priority

When the same term exists in multiple glossaries:
1. Game-specific glossary entries take priority
2. Universal glossary entries are used as fallback

---

### Tips and Best Practices

> 1. **Start with common terms** — Add faction names, character names, and location names first
>
> 2. **Use notes for context** — For terms that can be translated differently based on context, add explanatory notes
>
> 3. **Be specific with proper nouns** — Add entries for all proper nouns that should not be translated
>
> 4. **Use game-specific glossaries** — Create separate glossaries for game-unique terms
>
> 5. **Export regularly** — Export glossaries as backup before making major changes
>
> 6. **Review duplicates** — Check the statistics panel for duplicate entries and resolve conflicts
>
> 7. **Test translations** — After adding glossary entries, retranslate a few entries to verify
>
> 8. **Case sensitivity matters** — Enable for terms where capitalization distinguishes meaning
>
> 9. **Keep entries concise** — Glossary entries work best for individual terms or short phrases
>
> 10. **Document decisions** — Use the Notes field to document why specific translation choices were made

## Translation Memory

![](assets/screenshots/screen_tm.png)

Translation Memory (TM) is a core feature that stores previously translated text pairs and enables their reuse across projects. By leveraging TM, TWMT can significantly reduce translation costs and improve consistency.

### Purpose and Overview

#### What is Translation Memory?

Translation Memory is a database that stores source-target text pairs from your previous translations.

| Concept | Description |
|---------|-------------|
| Source Text | The original English text from the mod |
| Target Text | The translation in your target language |
| Language Pair | Combination of source and target languages (e.g., EN to FR) |
| Match | A TM entry that matches or is similar to text being translated |

#### Why Use Translation Memory?

| Benefit | Description |
|---------|-------------|
| **Cost Savings** | Reuse existing translations instead of paying for AI translation |
| **Consistency** | Same phrase always translated the same way |
| **Speed** | TM lookup is instant compared to AI responses |
| **Quality Improvement** | Translations improve over time |
| **Knowledge Preservation** | Your translation work is never lost |

#### How TM Works During Translation

1. **Exact Match Check** — Fast hash-based lookup (O(1) performance)
2. **Fuzzy Match Check** — Search for similar texts using multiple similarity algorithms
3. **Auto-Apply** — Matches with 95%+ similarity are automatically applied
4. **LLM Fallback** — Only texts without good TM matches are sent to AI
5. **TM Update** — New AI translations are automatically added to TM

---

### Translation Memory Screen

Access from the sidebar by clicking "Translation Memory".

#### Screen Layout

1. **Header** — Title and action buttons (Import, Export, Cleanup)
2. **Left Sidebar** — Statistics panel showing TM metrics
3. **Main Content** — Search bar, data grid, and pagination

---

### Statistics Panel

#### Overview Statistics

| Statistic | Description |
|-----------|-------------|
| Total Entries | Total number of translation pairs stored in TM |

#### Language Pairs

Displays entry counts broken down by language pair (e.g., "EN to FR: 5,234 entries").

#### Performance Statistics

| Statistic | Description |
|-----------|-------------|
| Total Reuse | Total times TM entries have been reused |
| Tokens Saved | Estimated API tokens saved by using TM |
| Reuse Rate | Percentage of translations from TM vs. AI |

> **Tip:** The Reuse Rate is a key metric. A higher rate means more cost savings and better consistency.

---

### TM Browser Data Grid

| Column | Description |
|--------|-------------|
| Source Text | The original text that was translated |
| Target Text | The translation in the target language |
| Usage | How many times this entry has been reused |
| Actions | Copy and Delete buttons for each entry |

#### Viewing Entry Details

Double-click any row to open a detailed view showing:
- Source Text (full content, selectable)
- Target Text (full content, selectable)
- Usage Count
- Last Used timestamp
- Created timestamp

#### Row Actions

| Button | Description |
|--------|-------------|
| Copy | Copies both source and target text to clipboard |
| Delete | Removes the entry from TM (with confirmation) |

---

### Search and Filtering

#### Search Bar

- Type to search in both source and target text
- Search is case-insensitive and matches partial text
- Click the X icon to clear the search
- Uses FTS5 full-text search for fast results

#### Language Filter

Filter entries by target language using the filter dropdown in the statistics panel.

---

### Pagination

| Control | Description |
|---------|-------------|
| First Page | Jump to the first page |
| Previous | Go to the previous page |
| Page Numbers | Click a specific page number |
| Next | Go to the next page |
| Last Page | Jump to the last page |

---

### TMX Import

TMX (Translation Memory eXchange) is the industry-standard XML format for exchanging translation memories.

#### Import Process

1. **Select File** — Click to browse and select a .tmx file
2. **Review File Info** — The dialog shows filename and file size
3. **Configure Options** — Set import preferences
4. **Import** — Click "Import" to start the process

#### Import Options

| Option | Description |
|--------|-------------|
| Overwrite existing entries | Imported entries replace existing ones with the same source text |
| Validate entries | Entries are validated before import |

#### Import Results

| Statistic | Description |
|-----------|-------------|
| Total entries | Number of entries found in the TMX file |
| Imported | Number of entries successfully added |
| Skipped (duplicates) | Number of entries skipped |
| Failed (validation errors) | Number of entries that failed validation |

---

### TMX Export

Export your TM entries to a TMX file for backup or sharing.

#### Export Options

**Filters:**

| Option | Description |
|--------|-------------|
| Target Language | Export only entries for a specific language, or "All" |

**What to Export:**

| Option | Description |
|--------|-------------|
| All entries | Export all entries matching filter criteria |
| Frequently used only | Export only entries used more than 5 times |

**Format Options:**

| Option | Description |
|--------|-------------|
| Include metadata | Add quality scores, usage counts, and other metadata |
| Include statistics | Add export summary to the file header |

---

### TM Cleanup

Maintain database health by removing unused entries.

#### Cleanup Configuration

| Option | Description |
|--------|-------------|
| Delete if unused for (days) | Slider to set the age threshold (0-730 days) |

> **Warning:** Cleanup is permanent and cannot be undone. Consider exporting your TM before running cleanup for the first time.

---

### Match Types

#### Exact Match (100% Similarity)

- **Lookup Method** — Hash-based (instant)
- **Application** — Automatically applied during translation
- **Display** — Shown as "Exact Match" in the TM Source column

#### Fuzzy Match (85-99% Similarity)

- **Lookup Method** — Multiple similarity algorithms
- **Threshold** — Minimum 85% similarity
- **Application** — Auto-applied if >=95%, otherwise suggested
- **Display** — Shown as "Fuzzy Match"

#### Context Match

- **Category Boost** — +3% for matching category
- **Purpose** — Prioritize contextually relevant translations

---

### Similarity Calculation

TWMT calculates similarity using three algorithms:

| Algorithm | Weight | Description |
|-----------|--------|-------------|
| Levenshtein Distance | 40% | Edit distance-based similarity (character level) |
| Jaro-Winkler | 30% | Good for typos and short strings |
| Token-Based (Jaccard) | 30% | Word-level overlap, order-independent |

**Combined Score:**

```
Score = (Levenshtein × 0.4) + (Jaro-Winkler × 0.3) + (Token × 0.3) + Context Boost
```

**Thresholds:**

| Threshold | Value | Behavior |
|-----------|-------|----------|
| Minimum Similarity | 85% | Matches below this are ignored |
| Auto-Accept | 95% | Matches at or above are automatically applied |

---

### Integration with Translation Editor

#### TM Source Column

| Value | Meaning |
|-------|---------|
| Exact Match | 100% match from TM |
| Fuzzy Match | Partial match from TM |
| LLM | Generated by AI |
| Manual | Typed by user |
| None | No translation yet |

#### Skip TM Option

| State | Behavior |
|-------|----------|
| Unchecked (default) | TM is consulted first |
| Checked | All units go directly to LLM |

> **Note:** Even with Skip TM enabled, new translations are still added to TM.

---

### Tips and Best Practices

> 1. **Start Small, Build Gradually** — Your TM will naturally grow as you translate
>
> 2. **Translate Similar Mods First** — Translate mods from the same author or genre together to maximize TM reuse
>
> 3. **Review Auto-Applied Matches** — Occasionally review 95% matches to ensure they fit the context
>
> 4. **Export Regularly** — Export your TM periodically as a backup
>
> 5. **Use Cleanup Carefully** — Export your TM before running cleanup
>
> 6. **Monitor Reuse Rate** — A high reuse rate (50%+) indicates effective TM usage
>
> 7. **Share TM Across Languages** — Each language pair has its own TM entries
>
> 8. **Import Community TMX** — If available, import TMX files shared by other translators
>
> 9. **Check Usage Counts** — High-usage entries are your most valuable translations
>
> 10. **Understand Token Savings** — Higher values indicate significant savings from TM reuse

## Settings

The Settings screen provides centralized configuration for all TWMT features. It is organized into three tabs: **General**, **Folders**, and **LLM Providers**.

Access Settings from the sidebar by clicking the gear icon.

---

### General Tab

The General tab contains language preferences, ignored source texts configuration, and database maintenance tools.

#### Translation Language Preferences

Manage the languages available for translation projects and set the default target language.

##### Language Table

| Column | Description |
|--------|-------------|
| Default | Radio button to set the default language for new projects |
| Code | ISO language code (e.g., "fr", "de", "es") |
| Language | Full display name (e.g., "French", "German", "Spanish") |
| Actions | Delete button for custom languages |

**Setting the Default Language:**
- Click the radio button in the Default column
- This language will be pre-selected when creating new translation projects
- Default value: French (fr)

**Built-in Languages:**
TWMT includes common translation target languages. These system languages cannot be deleted.

##### Adding Custom Languages

Click "Add Language" to add a custom language:

1. **Language Code** — Enter the ISO 639-1 code (2-3 letters)
2. **Language Name** — Enter the display name
3. Click "Add" to save

---

#### Ignored Source Texts

Define source texts that should be skipped during translation.

**Purpose:**
- Skip placeholder texts
- Exclude mod-specific patterns that are not translatable
- Reduce unnecessary API costs

> **Note:** Texts fully enclosed in brackets like `[PLACEHOLDER]` are automatically skipped without needing to be added to this list.

**Default Values:**
- `placeholder`
- `dummy`

##### Managing Ignored Texts

| Action | Description |
|--------|-------------|
| Add Text | Add a new source text to ignore |
| Toggle checkbox | Enable or disable individual entries |
| Delete | Permanently remove an entry |
| Reset to Defaults | Delete all entries and restore defaults |

---

#### Database Maintenance

##### Reanalyze Translations

Scans all translation entries and fixes status inconsistencies.

**When to use:**
- Progress percentages appear incorrect
- Translations show wrong status
- After recovering from a crash

##### Clear Mod Update Cache

Removes stale "pending changes" badges from projects.

**When to use:**
- Projects show "pending changes" but no actual changes exist
- After manually modifying mod files outside TWMT
- To force a fresh update check

---

### Folders Tab

The Folders tab configures paths to game installations, Steam Workshop, and the RPFM tool.

#### Game Installations

Configure paths to your Total War game installations.

##### Auto-Detect All Games

Click "Auto-Detect All Games" to automatically scan your Steam installation.

**Detection process:**
1. Reads Steam configuration files
2. Scans all Steam library folders
3. Identifies Total War games by their App ID
4. Fills in detected paths automatically

##### Per-Game Configuration

| Button | Description |
|--------|-------------|
| Detect | Auto-detect this specific game's installation path |
| Browse | Manually select the game folder |
| Path field | Shows the current path; can be edited directly |

**Path Requirements:**
- Point to the game's root installation folder
- Example: `C:\Steam\steamapps\common\Total War WARHAMMER III`
- The folder must contain the game's `data` directory

---

#### Steam Workshop

Configure the base path to Steam Workshop content.

**Default Path:**
```
C:\Program Files (x86)\Steam\steamapps\workshop\content
```

> **Note:** TWMT automatically appends the game's Steam App ID to this base path when scanning for mods.

---

#### RPFM Tool

RPFM (Rusted PackFile Manager) is required for extracting localization files from mod packs.

> **Download:** https://github.com/Frodo45127/rpfm

##### RPFM Executable

| Button | Description |
|--------|-------------|
| Test | Validate the RPFM executable and display version |
| Browse | Select the rpfm_cli.exe file |

**Requirements:**
- Must point to `rpfm_cli.exe` (the command-line interface, not the GUI)
- RPFM version 4.x or later recommended

##### RPFM Schema Folder

| Button | Description |
|--------|-------------|
| Default | Set to the standard RPFM schema path |
| Browse | Manually select the schema folder |

**Default Path:**
```
C:\Users\{USERNAME}\AppData\Roaming\FrodoWazEre\rpfm\config\schemas
```

> **Note:** Schemas are typically installed when you first run the RPFM GUI application and update schemas from its menu.

---

### LLM Providers Tab

The LLM Providers tab configures AI translation services.

#### Provider Overview

| Provider | Type | Best For |
|----------|------|----------|
| Anthropic (Claude) | LLM | High-quality translations with nuanced context understanding |
| OpenAI | LLM | Balance of quality and cost; wide model selection |
| DeepL | Translation API | Fast, cost-effective translations for simpler content |

---

#### Anthropic (Claude)

##### API Key

1. Expand the "Anthropic (Claude)" section
2. Enter your Anthropic API key
3. Click the connection test button (plug icon) to verify

**Getting an API Key:**
- Create an account at https://console.anthropic.com
- Navigate to API Keys
- Generate a new key

> **Security:** API keys are stored securely using Windows Credential Manager, not in plain text.

##### Models

| Element | Description |
|---------|-------------|
| Checkbox | Enable/disable the model for use |
| Model Name | Friendly display name |
| Model ID | API identifier |
| Default badge | Indicates the current default model |
| Star icon | Click to set as global default |

---

#### OpenAI

##### API Key

1. Expand the "OpenAI" section
2. Enter your OpenAI API key
3. Click the connection test button to verify

**Getting an API Key:**
- Create an account at https://platform.openai.com
- Navigate to API Keys
- Generate a new key

---

#### DeepL

##### API Key

1. Expand the "DeepL" section
2. Enter your DeepL API key
3. Click the connection test button to verify

**Getting an API Key:**
- Create an account at https://www.deepl.com/pro-api
- Choose Free or Pro plan
- Copy your Authentication Key

> **Note:** DeepL is a translation-specific API, not an LLM. It provides fast, accurate translations but with less contextual understanding.

---

#### Custom Translation Rules

Define global instructions that are appended to every translation prompt.

**Purpose:**
- Enforce consistent style
- Define terminology preferences
- Set tone and formality requirements
- Add language-specific instructions

##### Managing Rules

| Action | Description |
|--------|-------------|
| Add Rule | Create a new translation instruction |
| Toggle | Enable/disable the rule |
| Edit | Modify the rule text |
| Delete | Remove the rule |

**Rule Examples:**
- "Always use formal language and avoid contractions"
- "Preserve all proper nouns without translation"
- "Use passive voice for UI instructions"
- "Maintain the original sentence length where possible"

---

#### Advanced Settings

##### Rate Limit

Controls the maximum number of API requests per minute.

| Setting | Range | Default |
|---------|-------|---------|
| Rate Limit | 10-500 requests/minute | 500 |

**Recommendations:**
- Start with default (500) for most users
- Reduce to 100-200 if experiencing timeout errors
- Reduce to 50-100 for free-tier API accounts

---

### Connection Testing

Each provider section includes a connection test button (plug icon).

**Common Errors:**

| Error | Solution |
|-------|----------|
| No API key configured | Enter an API key first |
| No model enabled | Enable at least one model before testing |
| Invalid API key | Check the key is correct and active |
| Rate limited | Wait and try again |

---

### Settings Best Practices

> 1. **Configure RPFM First** — TWMT cannot import mods or generate packs without RPFM
>
> 2. **Detect Games Early** — Run auto-detection after installing TWMT
>
> 3. **Test Connections** — Always test API connections after entering keys
>
> 4. **Enable Multiple Models** — Enable several models to compare quality and costs
>
> 5. **Use Custom Rules Sparingly** — Too many rules can confuse the AI
>
> 6. **Secure Your Keys** — Avoid sharing screenshots of the Settings screen
>
> 7. **Adjust Rate Limits as Needed** — Start with defaults and reduce only if experiencing errors
>
> 8. **Maintain Database Regularly** — Run "Reanalyze Translations" if you notice inconsistencies
>
> 9. **Keep RPFM Updated** — Update RPFM and its schemas periodically
>
> 10. **Back Up Settings** — Export settings periodically if you have complex configurations
