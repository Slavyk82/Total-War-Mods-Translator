# TWMT User Guide

**Version 1.0** | **Last Updated**: November 2025

Complete guide to using TWMT (Total War Mods Translator) for translating Total War Workshop mods.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Core Workflows](#core-workflows)
4. [Features Reference](#features-reference)
5. [Tips & Best Practices](#tips--best-practices)
6. [Troubleshooting](#troubleshooting)

---

## Introduction

### What is TWMT?

TWMT (Total War Mods Translator) is a professional Windows desktop application designed specifically for translating Total War Workshop mods. It combines advanced AI translation technology with powerful workflow tools to help you create high-quality translations efficiently.

### Who is it for?

- **Mod Translators**: Translate Total War mods to your language
- **Mod Authors**: Provide multilingual support for your mods
- **Translation Teams**: Collaborate on large-scale translation projects
- **Community Managers**: Manage translations across multiple mods

### What can you do with it?

- Translate thousands of text entries using AI (Claude, GPT, or DeepL)
- Maintain translation consistency with glossaries
- Reuse previous translations with Translation Memory
- Search and filter translations with lightning speed
- Track translation progress and quality
- Export translations in multiple formats
- Manage multiple projects simultaneously

---

## Getting Started

### Installation

#### Option 1: Using the Installer (Recommended)

1. Download the latest `TWMT-Setup-x.x.x.exe` from [GitHub Releases](https://github.com/yourusername/twmt/releases)
2. Double-click the installer
3. Follow the installation wizard
4. Launch TWMT from the Start Menu

#### Option 2: Portable Version

1. Download `TWMT-Portable-x.x.x.zip`
2. Extract to any folder
3. Run `TWMT.exe`

> **Note**: The portable version stores settings in the application folder instead of AppData.

### First Launch

When you first launch TWMT, you'll see a welcome screen guiding you through initial setup:

1. **Choose Language**: Select your UI language (default: English)
2. **Configure API Keys**: Set up at least one LLM provider
3. **Set Game Paths**: Let TWMT detect your Total War installations
4. **Create First Project**: Optional quick-start wizard

### Setting Up API Keys

TWMT requires API keys from translation providers. See the [API Setup Guide](api_setup.md) for detailed instructions.

**Quick Setup**:

1. Press `Ctrl+7` to open Settings
2. Click **LLM Providers** tab
3. Choose a provider (Anthropic, OpenAI, or DeepL)
4. Enter your API key
5. Click **Test Connection**
6. Click **Save**

> **Recommendation**: Start with Anthropic Claude 3.5 Sonnet for the best balance of quality and cost.

### Configuring Game Paths

TWMT needs to know where your Total War games are installed:

1. Go to **Settings** → **Games**
2. Click **Auto-detect** (TWMT will scan common Steam locations)
3. Verify the detected paths
4. Add custom paths if needed
5. Click **Save**

**Supported Games**:
- Total War: Warhammer III
- Total War: Three Kingdoms
- Total War: Warhammer II
- Total War: Rome II
- Total War: Attila
- (More games coming soon)

### Understanding the Interface

TWMT uses Microsoft's Fluent Design for a native Windows look and feel.

**Main Navigation** (Left Sidebar):
- **Home** (`Ctrl+1`): Dashboard with statistics and recent activity
- **Mods** (`Ctrl+2`): Browse installed Workshop mods
- **Projects** (`Ctrl+3`): Manage translation projects
- **Glossary** (`Ctrl+4`): Terminology management
- **Translation Memory** (`Ctrl+5`): Browse and manage TM entries
- **Statistics** (`Ctrl+6`): Detailed analytics and reports
- **Settings** (`Ctrl+7`): Application configuration

**Top Toolbar**:
- Quick actions (New Project, Import, Export)
- Search bar (global search across all projects)
- Notifications
- User menu

**Status Bar** (Bottom):
- Database status
- API connection status
- Translation progress
- Performance metrics

---

## Core Workflows

### 3.1 Translating a Mod

This is the primary workflow for translating a Total War Workshop mod.

#### Step 1: Browse Installed Mods

1. Navigate to **Mods** (`Ctrl+2`)
2. Select your game from the dropdown
3. TWMT displays all subscribed Workshop mods
4. Click on a mod to view details:
   - Title and description
   - Author information
   - Workshop ID
   - Last update date
   - Number of localizable strings

#### Step 2: Create a New Project

1. Click **Create Project** button
2. Fill in project details:
   - **Name**: Descriptive name (e.g., "SFO: Grimhammer III - French")
   - **Description**: Optional notes about the project
   - **Source Language**: Usually English
   - **Target Language(s)**: Select one or more languages
3. Configure translation settings:
   - **LLM Provider**: Choose Claude, GPT, or DeepL
   - **Model**: Select specific model (e.g., claude-3-5-sonnet)
   - **Quality Threshold**: TM match threshold (70-100%)
   - **Use Glossary**: Enable to apply project glossary
4. Click **Create**

#### Step 3: Select Target Languages

You can translate to multiple languages in one project:

1. Check languages you want to translate to
2. Each language creates a separate translation set
3. You can translate them sequentially or in parallel

**Supported Languages**:
- Major: English, French, German, Spanish, Italian, Russian, Chinese, Japanese, Korean
- Additional: Portuguese, Polish, Turkish, Czech, and more

#### Step 4: Configure Translation Settings

**Provider Settings**:
- **Temperature**: Controls creativity (0.0-1.0, default: 0.3)
- **Max Tokens**: Maximum response length
- **Context**: Enable context-aware translation
- **Preserve Formatting**: Keep XML/HTML tags intact

**Quality Settings**:
- **Enable Validation**: Check for errors after translation
- **Auto-fix**: Automatically fix common issues
- **Manual Review**: Flag entries for human review

**Cost Controls**:
- **Batch Size**: Translate N entries at once (default: 100)
- **Use Translation Memory**: Check TM before using API
- **Cost Limit**: Stop if estimated cost exceeds limit

#### Step 5: Run Batch Translation

1. Open the Translation Editor for your target language
2. Select entries to translate:
   - Click individual rows
   - Use `Ctrl+A` to select all
   - Use filters to select untranslated entries
3. Click **Translate Selected** (`Ctrl+T`)
4. Review the translation preview:
   - Estimated cost
   - Number of entries
   - Estimated time
   - TM matches (if applicable)
5. Click **Confirm**
6. Watch the progress bar
7. Review any errors or warnings

**Progress Indicators**:
- Overall progress (e.g., "450/1000 entries")
- Current batch progress
- Estimated time remaining
- Cost so far

#### Step 6: Review and Edit Translations

After batch translation, review the results:

1. **Quality Indicators**:
   - Green: High quality (90-100%)
   - Yellow: Medium quality (70-89%)
   - Red: Low quality (<70%)
   - Gray: Not validated

2. **Manual Editing**:
   - Double-click any entry to edit
   - Edit directly in the DataGrid
   - Press `Enter` to save, `Esc` to cancel

3. **Validation Issues**:
   - Red flags indicate problems
   - Hover for details
   - Click "Auto-fix" to attempt repair

4. **Search and Filter**:
   - Press `Ctrl+F` to search
   - Filter by status, quality, issues
   - Sort by any column

#### Step 7: Export Translated Files

When translation is complete:

1. Click **Export** button
2. Choose export format:
   - **.loc** (Total War native format)
   - **CSV** (for review in Excel)
   - **Excel** (.xlsx with formatting)
   - **JSON** (for custom tools)
3. Select export options:
   - Include only validated entries
   - Include source text
   - Add metadata
4. Choose destination folder
5. Click **Export**

#### Step 8: Package and Test

1. TWMT exports to a mod-compatible folder structure
2. Copy the `.loc` files to your mod folder
3. Test in-game to verify translations appear correctly
4. Report any issues and iterate

**Folder Structure**:
```
exported_translations/
└── [mod_name]/
    └── localisation/
        └── [language_code]/
            └── [mod_name]_[language].loc
```

---

### 3.2 Using Translation Memory

Translation Memory (TM) stores previous translations for reuse, saving time and money.

#### What is Translation Memory?

TM is a database of source-target translation pairs. When you translate new content, TWMT:
1. Checks if the exact same source text exists in TM
2. If found, reuses the translation (no API call needed)
3. If not found, checks for similar text (fuzzy matching)
4. Suggests the closest match with similarity score

**Benefits**:
- **Cost Savings**: Reuse translations instead of paying for API calls
- **Consistency**: Same source text always gets the same translation
- **Speed**: Instant retrieval vs. API latency
- **Quality**: Previously validated translations are high quality

#### How TM Saves Time and Cost

**Example Scenario**:

You're translating a 5,000-entry mod:
- 1,000 entries are exact duplicates (buttons, common UI)
- 500 entries have 90%+ similarity to previous translations
- 3,500 entries are unique

**Without TM**:
- All 5,000 entries sent to API
- Cost: $5.00 (assuming $1/1000 entries)
- Time: 10 minutes

**With TM**:
- 1,000 exact matches: $0.00 (instant)
- 500 high-quality fuzzy matches: $0.00 (with review)
- 3,500 unique entries: $3.50
- **Total Cost**: $3.50 (30% savings)
- **Total Time**: 7 minutes (30% faster)

#### Exact vs Fuzzy Matches

**Exact Match** (100% similarity):
- Source text is identical
- Translation reused automatically
- No API call needed
- No manual review required

**Fuzzy Match** (70-99% similarity):
- Source text is similar but not identical
- Translation suggested as starting point
- Requires manual review and adjustment
- Still faster than translating from scratch

**Example**:

| Type | Source (TM) | Source (New) | Similarity |
|------|-------------|--------------|------------|
| Exact | "Save Game" | "Save Game" | 100% |
| Fuzzy | "Load Game" | "Load Saved Game" | 85% |
| No Match | "Settings" | "Configure Audio Options" | 30% |

#### Managing TM Entries

**Browse Translation Memory** (`Ctrl+5`):

1. Navigate to **Translation Memory** screen
2. View all TM entries in a DataGrid
3. Columns:
   - Quality score
   - Source text
   - Target text
   - Language pair
   - Game context
   - Usage count
   - Last used date

**Filter Entries**:
- **By Language Pair**: EN-FR, EN-DE, etc.
- **By Quality**: High (≥90%), Medium (70-89%), Low (<70%)
- **By Game**: Filter by specific game or mod
- **By Usage**: Show only frequently used entries

**Search Entries**:
- Use the search bar for full-text search
- Searches both source and target text
- Powered by FTS5 for instant results

**Edit Entries**:
- Double-click any entry to edit
- Update translation
- Change quality score
- Add notes

**Delete Entries**:
- Select entry
- Press `Delete` key
- Confirm deletion

#### Importing/Exporting TM

**Import TMX File**:

TMX (Translation Memory eXchange) is an industry-standard format.

1. Click **Import** button
2. Select `.tmx` file
3. Choose import options:
   - **Overwrite existing**: Replace duplicates
   - **Skip existing**: Keep original
   - **Merge**: Take best quality
4. Preview first 10 entries
5. Click **Import**
6. Review import summary

**Export to TMX**:

1. Click **Export** button
2. Configure filters:
   - Language pair
   - Minimum quality threshold
   - Game context
3. Choose TMX version (1.4b recommended)
4. Include metadata (recommended)
5. Select destination
6. Click **Export**

**Supported Formats**:
- **TMX 1.4b**: Industry standard
- **TMX 1.1**: Legacy support
- **CSV**: For Excel editing
- **JSON**: For custom tools

**Use Cases**:
- Share TM with team members
- Backup TM before cleanup
- Import TM from other tools (Trados, MemoQ, etc.)
- Migrate TM between machines

#### TM Best Practices

1. **Regular Cleanup**: Remove low-quality or unused entries
2. **Quality Validation**: Review fuzzy matches before accepting
3. **Context Tagging**: Add game/mod context for better matching
4. **Backup**: Export TM regularly
5. **Share**: Collaborate by sharing TMX files

---

### 3.3 Managing Glossaries

Glossaries ensure consistent terminology across your translations.

#### Creating Glossaries

TWMT supports two types of glossaries:

**Global Glossaries**:
- Shared across all projects
- For general gaming terminology
- Examples: UI terms, common game mechanics

**Project Glossaries**:
- Specific to one project
- For mod-specific terms
- Examples: faction names, unique items

**Create a Glossary**:

1. Navigate to **Glossary** (`Ctrl+4`)
2. Click **New Glossary**
3. Enter details:
   - **Name**: Descriptive name
   - **Description**: Purpose and scope
   - **Type**: Global or Project
   - **Language Pair**: Source-target languages
4. Click **Create**

#### Adding Terms

**Manual Entry**:

1. Select a glossary
2. Click **Add Term**
3. Fill in fields:
   - **Source Term**: Original text
   - **Target Term**: Translation
   - **Category**: General, Technical, UI, Legal, Medical, Custom
   - **Case Sensitive**: Exact case matching
   - **Forbidden**: Flag as "do not translate this way"
   - **Notes**: Context or usage notes
4. Click **Save**

**Inline Editing**:

1. View glossary entries in DataGrid
2. Double-click any cell
3. Edit directly
4. Press `Enter` to save

**Bulk Operations**:

1. Select multiple entries (`Ctrl+Click` or `Shift+Click`)
2. Right-click for context menu
3. Actions:
   - Change category
   - Mark as forbidden
   - Delete entries

#### Project vs Global Glossaries

**When to Use Global**:
- Common UI terms (Settings, Save, Load, Exit)
- General gaming terms (Health, Mana, Experience)
- Platform terms (Steam, Workshop, Cloud Save)

**When to Use Project**:
- Faction names specific to a mod
- Custom units or items
- Lore-specific terminology
- Author's preferred translations

**Priority**: Project glossaries override global glossaries.

**Example**:

Global Glossary:
- "Empire" → "Empire" (keep in English)

Project Glossary (Warhammer mod):
- "Empire" → "L'Empire" (French translation)

Result: "L'Empire" is used (project overrides global)

#### Importing from CSV/TBX/Excel

**Import CSV**:

1. Prepare CSV file with columns:
   ```csv
   source_term,target_term,category,case_sensitive,forbidden,notes
   Health,Santé,UI,false,false,Player health bar
   Mana,Mana,UI,true,false,Keep original spelling
   ```

2. Click **Import** → **From CSV**
3. Map columns:
   - Auto-detection based on headers
   - Manual mapping if needed
4. Preview first 10 rows
5. Click **Import**

**Import Excel**:

1. Prepare `.xlsx` file with formatted table
2. Click **Import** → **From Excel**
3. Select sheet and column mapping
4. Preview and import

**Import TBX**:

TBX (TermBase eXchange) is the industry standard for terminology.

1. Click **Import** → **From TBX**
2. Select `.tbx` file
3. Choose import options
4. Preview and import

**Column Mapping**:

If your file has different column names, map them manually:
- Source Term → Column A
- Target Term → Column B
- Category → Column C
- Etc.

#### Ensuring Consistency

**Automatic Application**:

When enabled, TWMT automatically:
1. Checks each source text for glossary terms
2. Suggests or auto-applies the glossary translation
3. Highlights glossary matches in the editor
4. Warns if translation doesn't match glossary

**Manual Application**:

1. Select entries in Translation Editor
2. Click **Apply Glossary**
3. Preview changes
4. Confirm application

**Validation**:

TWMT validates that translations use glossary terms correctly:
- ✅ Source contains "Empire", target contains "L'Empire"
- ⚠️ Source contains "Empire", target contains "Empire" (should be "L'Empire")
- ❌ Source contains forbidden term

**Consistency Report**:

1. Go to **Statistics** → **Glossary Compliance**
2. View compliance metrics:
   - Percentage of entries using glossary terms correctly
   - Most frequently violated terms
   - Suggestions for improvement

---

### 3.4 Manual Editing

The Translation Editor is where you review and edit translations.

#### Using the Translation Editor

**Open the Editor**:

1. Go to **Projects** (`Ctrl+3`)
2. Select a project
3. Click **Open Editor** for target language
4. The editor opens in a new tab

**Editor Layout**:

- **Left**: Translation units DataGrid
- **Right**: Details panel with:
  - TM suggestions
  - Glossary matches
  - Validation issues
  - Edit history

**DataGrid Columns**:
- **Status**: Icon indicating state (untranslated, translated, validated, issue)
- **Key**: Unique identifier
- **Source**: Original text
- **Target**: Translation
- **Quality**: Score (0-100%)
- **Modified**: Last edit date
- **Actions**: Quick action buttons

#### Keyboard Shortcuts

**Navigation**:
- `Arrow Keys`: Move between cells
- `Tab`: Next editable cell
- `Shift+Tab`: Previous editable cell
- `Page Up/Down`: Scroll page
- `Home/End`: First/last row
- `Ctrl+Home/End`: First/last cell

**Editing**:
- `Enter`: Start editing cell
- `F2`: Start editing cell (alternative)
- `Esc`: Cancel editing
- `Ctrl+S`: Save changes
- `Ctrl+Z`: Undo
- `Ctrl+Y`: Redo
- `Ctrl+Shift+Z`: Redo (alternative)

**Selection**:
- `Click`: Select row
- `Ctrl+Click`: Toggle row selection
- `Shift+Click`: Select range
- `Ctrl+A`: Select all visible rows

**Actions**:
- `Ctrl+T`: Translate selected
- `Ctrl+C`: Copy selected
- `Ctrl+V`: Paste
- `Delete`: Clear translation
- `Ctrl+F`: Open search dialog
- `F3`: Find next
- `Shift+F3`: Find previous

#### Search and Filter

**Quick Search** (Top-right search bar):
- Type to search source and target text
- Results filter in real-time
- Press `Esc` to clear

**Advanced Search** (`Ctrl+F`):

1. Open search dialog
2. Configure search:
   - **Scope**: Source, Target, Both, Key, All
   - **Match**: Contains, Exact, Starts with, Ends with, Regex
   - **Case Sensitive**: Yes/No
3. Add filters:
   - **Status**: Untranslated, Translated, Validated, Issues
   - **Quality**: Range (e.g., 70-100%)
   - **Date Modified**: Date range
   - **Has TM Matches**: Yes/No
   - **Has Glossary Terms**: Yes/No
4. Click **Search**

**Save Search**:

1. Configure search
2. Click **Save Search**
3. Name the search
4. Access from **Saved Searches** panel

**Filter Panel** (Left sidebar):

Quick filters:
- **Status**: All, Untranslated, Translated, Validated, Issues
- **Quality**: All, High, Medium, Low
- **TM**: All, Has Matches, No Matches
- **Glossary**: All, Has Terms, No Terms
- **Modified**: Today, This Week, This Month, Custom

#### Bulk Operations

**Select Multiple Entries**:
- `Ctrl+Click`: Add/remove from selection
- `Shift+Click`: Select range
- `Ctrl+A`: Select all (filtered view)

**Batch Actions**:

1. Select entries
2. Right-click or use toolbar buttons:
   - **Translate**: Send to LLM
   - **Mark as Validated**: Set status
   - **Clear Translations**: Remove target text
   - **Apply Glossary**: Auto-apply glossary terms
   - **Copy**: Copy to clipboard
   - **Export**: Export selection to file
   - **Delete**: Remove entries (careful!)

**Batch Edit**:

1. Select entries
2. Click **Batch Edit**
3. Choose operation:
   - Find and replace
   - Add prefix/suffix
   - Change case (uppercase, lowercase, title case)
   - Trim whitespace
4. Preview changes
5. Apply

#### Quality Checks

**Automatic Validation**:

TWMT automatically checks for:
- **Placeholder Mismatch**: `{0}` in source but missing in target
- **HTML Tag Mismatch**: `<b>` in source but missing in target
- **Length Discrepancy**: Target is 300%+ longer than source
- **Untranslated**: Target is identical to source (for different languages)
- **Empty Translation**: Target is blank
- **Punctuation Issues**: Missing periods, commas, etc.
- **Number Mismatch**: Numbers in source don't match target
- **Glossary Violation**: Doesn't use required glossary term

**Validation Panel**:

Issues displayed in right sidebar:
- ⚠️ **Warning**: Should review but not critical
- ❌ **Error**: Must fix before export

Click on an issue to:
- Jump to entry
- See details
- Auto-fix (if available)
- Mark as false positive

**Manual Validation**:

1. Select entries
2. Click **Validate Selected**
3. Review results
4. Fix issues
5. Mark as validated

**Quality Score**:

Each entry gets a quality score (0-100%):
- **90-100%**: Excellent, no issues
- **70-89%**: Good, minor issues
- **50-69%**: Fair, some issues
- **<50%**: Poor, major issues

---

## Features Reference

### 4.1 Home Dashboard

The Home screen provides an overview of your translation work.

**Statistics Overview**:
- **Total Projects**: Number of active projects
- **Total Entries**: Sum of all translation units
- **Completion Rate**: Percentage translated
- **Validation Rate**: Percentage validated
- **TM Reuse Rate**: Percentage from Translation Memory
- **This Month**: Translation activity this month
- **Cost This Month**: API costs this month

**Recent Projects**:
- Last 5 accessed projects
- Quick open button
- Progress bars
- Last modified date

**Recent Activity**:
- Translation history
- Import/export events
- Errors and warnings

**Quick Actions**:
- **New Project**: Create project wizard
- **Import TM**: Import TMX file
- **Import Glossary**: Import terminology
- **Open Recent**: Quick access dropdown

**Charts and Graphs**:
- Translation progress over time
- Cost trends
- Language distribution
- Quality metrics

---

### 4.2 Projects Management

Manage all your translation projects from one screen.

**Project List**:

Displays all projects with:
- Name and description
- Source and target languages
- Progress (translated/total)
- Last modified date
- Status (Active, Paused, Complete)

**Actions**:
- **Open**: Open in Translation Editor
- **Edit**: Change project settings
- **Duplicate**: Create a copy
- **Archive**: Hide from active list
- **Delete**: Permanently remove

**Create New Project**:

1. Click **New Project**
2. Choose source:
   - **From Mod**: Select installed Workshop mod
   - **From Files**: Import .loc, CSV, or other files
   - **Blank**: Start from scratch
3. Configure settings
4. Click **Create**

**Project Settings**:

- **General**:
  - Name and description
  - Source language
  - Target languages
- **Translation**:
  - Default LLM provider
  - Model selection
  - Temperature and parameters
- **Quality**:
  - TM threshold
  - Auto-validation
  - Quality requirements
- **Glossary**:
  - Assign project glossary
  - Enable/disable glossary enforcement
- **Advanced**:
  - Custom metadata
  - Export templates

**Language Management**:

- Add new target languages
- Remove languages (with confirmation)
- Switch active language
- Compare translations across languages

**Progress Tracking**:

Each project shows:
- **Completion**: X/Y entries translated
- **Validation**: X/Y entries validated
- **Quality**: Average quality score
- **TM Reuse**: Percentage from TM
- **Cost**: Total API cost so far

**Filtering and Sorting**:

- Filter by status, language, or date
- Sort by name, progress, or last modified
- Search by project name

---

### 4.3 Translation Editor

The main workspace for translation.

**DataGrid Navigation**:

The DataGrid displays translation units in a virtualized table:
- Handles 10,000+ rows smoothly
- Only renders visible rows (performance)
- Smooth scrolling
- Column sorting (click header)
- Column resizing (drag border)
- Column reordering (drag header)

**Columns**:

Default columns (customizable):
1. **Status**: Icon (⚪ untranslated, 🟢 translated, ✅ validated, ⚠️ issue)
2. **Key**: Unique identifier (e.g., "ui_button_save")
3. **Source**: Original text
4. **Target**: Translated text (editable)
5. **Quality**: Score with color bar
6. **Modified**: Timestamp
7. **Actions**: Edit, Copy, Delete buttons

**Inline Editing**:

1. Double-click a cell or press `Enter`
2. Edit the text
3. Press `Enter` to save or `Esc` to cancel
4. Changes auto-save
5. Undo available (`Ctrl+Z`)

**TM Suggestions Panel**:

When you select an entry, the right panel shows:
- **Exact Matches**: 100% similarity (green)
- **Fuzzy Matches**: 70-99% similarity (yellow)
- **Low Matches**: <70% similarity (gray)

Click a suggestion to:
- **Use**: Replace target text
- **Copy**: Copy to clipboard
- **View**: See full details

**Validation Issues**:

Issues panel shows problems with selected entry:
- Issue type (error or warning)
- Description
- Auto-fix button (if available)
- Ignore button

**Edit History**:

History panel shows:
- All previous versions
- Who changed it (for multi-user setups)
- When it changed
- What changed (visual diff)

Actions:
- **Restore**: Revert to this version
- **Compare**: See side-by-side diff
- **Copy**: Use as reference

**Context Information**:

Additional info panel:
- **Game Context**: Which game/mod this is from
- **File**: Original file location
- **Usage Count**: How often this entry is used
- **Tags**: Custom labels
- **Notes**: Your comments

---

### 4.4 Settings

Configure TWMT to suit your workflow.

**General Settings**:

- **UI Language**: Choose interface language
- **Theme**: Light, Dark, or System
- **Auto-save Interval**: Minutes between auto-saves
- **Startup Behavior**: Show home, last project, or custom
- **Notifications**: Enable/disable toasts and alerts

**LLM Provider Configuration**:

**Anthropic (Claude)**:
- API key (stored in Windows Credential Manager)
- Default model (claude-3-5-sonnet, claude-3-opus, etc.)
- Organization ID (optional)
- Temperature (0.0-1.0)
- Max tokens

**OpenAI (GPT)**:
- API key
- Default model (gpt-4o, gpt-4-turbo, gpt-3.5-turbo)
- Organization ID (optional)
- Temperature
- Max tokens

**DeepL**:
- API key (Free or Pro)
- Formality (formal, informal, default)
- Preserve formatting

**Test Connection**:
- Verify API key is valid
- Check current usage/limits
- Test translation with sample text

**Game Installations**:

Manage Total War game paths:
- **Auto-detect**: Scan for Steam installations
- **Add Custom**: Manually add game path
- **Edit**: Change existing path
- **Remove**: Delete path
- **Set Default**: Choose default game

For each game:
- Game name and version
- Installation directory
- Workshop content directory
- Mods directory

**Translation Preferences**:

- **Default Quality Threshold**: 70-100% (for TM matching)
- **Default Batch Size**: 10-1000 (entries per API call)
- **Enable TM by Default**: Auto-check TM before translating
- **Enable Glossary by Default**: Auto-apply glossary terms
- **Auto-validate**: Run validation after translation
- **Context Window**: Include surrounding entries for context

**Database Settings**:

- **Location**: Database file path (read-only)
- **Size**: Current database size
- **Backup**: Create backup now
- **Vacuum**: Optimize database (reduces size)
- **Integrity Check**: Verify database health

**Advanced Options**:

- **Logging Level**: Info, Debug, Verbose
- **Log File Location**: Where logs are stored
- **Enable Crash Reports**: Auto-send crash data (off by default)
- **Cache Size**: Memory cache for better performance
- **Network Timeout**: Seconds before API timeout
- **Concurrent Requests**: Max simultaneous API calls

---

## Tips & Best Practices

### Cost Optimization

**1. Maximize Translation Memory Usage**

Before translating:
- Import existing TM from previous projects
- Set TM threshold to 70% (catches more matches)
- Review fuzzy matches instead of re-translating

**Savings**: 30-70% cost reduction

**2. Optimize Batch Sizes**

- Larger batches (500-1000): Better for simple, repetitive text
- Smaller batches (50-100): Better for complex, context-dependent text
- Test different sizes to find your sweet spot

**3. Choose the Right Model**

| Model | Cost | Quality | Best For |
|-------|------|---------|----------|
| Claude 3.5 Sonnet | Medium | Excellent | General use |
| GPT-4o | Medium | Excellent | General use |
| GPT-3.5 Turbo | Low | Good | Simple text, UI strings |
| Claude 3 Haiku | Low | Good | Bulk translation |

**4. Use Glossaries Effectively**

Pre-translate glossary terms:
- Create comprehensive glossaries before starting
- LLM doesn't need to "figure out" common terms
- Reduces token usage

**5. Monitor and Set Limits**

- Set project cost limits
- Get alerts at 50%, 75%, 90%
- Review expensive entries (long descriptions)

---

### Quality Improvement

**1. Create Comprehensive Glossaries**

Good glossary practices:
- Include UI terms (Save, Load, Settings, etc.)
- Add game-specific terms (faction names, unit types)
- Note forbidden translations
- Add context notes

**2. Use Project-Specific Context**

In LLM settings:
- Add project description
- Specify target audience (casual players, hardcore fans)
- Mention tone (formal, informal, humorous)
- Note special requirements (keep English names, etc.)

**3. Implement Review Workflow**

Three-pass approach:
1. **First Pass**: Batch translate everything
2. **Second Pass**: Review and fix validation issues
3. **Third Pass**: Manual QA review (read in context)

**4. Validate Regularly**

Run validation:
- After each batch translation
- Before marking as validated
- Before final export

Fix issues immediately:
- Placeholder mismatches
- Tag problems
- Glossary violations

**5. Use Version History**

Track changes:
- Review edit history
- Compare versions
- Restore good translations if edited poorly
- Learn from mistakes

---

### Performance Tips

**1. Use DataGrid Efficiently**

For large projects (10k+ entries):
- Keep page size at 20-50 entries
- Use filters to show relevant entries
- Don't select all (use batch operations on filtered view)

**2. Optimize Database**

Periodically:
- Run **Vacuum** (Settings → Database → Vacuum)
- Delete old history (keep last 30 days)
- Clean up low-quality TM entries

**3. Manage Memory**

For very large projects:
- Close unused projects
- Restart TWMT after long sessions
- Keep only 1-2 translation editors open

**4. Network Optimization**

- Use stable internet connection
- Increase timeout for slow connections
- Limit concurrent requests if experiencing errors

---

### Common Issues and Solutions

#### Issue: Translations are Low Quality

**Possible Causes**:
- Wrong model for content type
- Missing context
- Poor glossary

**Solutions**:
1. Switch to better model (Claude 3.5 Sonnet or GPT-4o)
2. Add project context in settings
3. Create/update glossary with key terms
4. Reduce batch size for context-dependent text
5. Provide few-shot examples in project description

---

#### Issue: API Costs are Too High

**Solutions**:
1. Enable Translation Memory and set threshold to 70%
2. Import TM from previous projects
3. Use cheaper model for simple text (Claude Haiku, GPT-3.5)
4. Increase batch size (reduces overhead)
5. Review and remove duplicate entries before translating

---

#### Issue: Translations Keep Formatting Tags

**Example**: `<b>Health</b>` becomes `<b>Santé</b>` (correct) or `<b> Santé </b>` (extra spaces)

**Solutions**:
1. Enable **Preserve Formatting** in LLM settings
2. Add formatting examples to project glossary
3. Use auto-fix validation
4. Add to project context: "Preserve XML/HTML tags exactly, no extra spaces"

---

#### Issue: Translation Memory Not Finding Matches

**Possible Causes**:
- TM threshold too high (only exact matches)
- Different language pair
- TM entries have different game context

**Solutions**:
1. Lower TM threshold to 70-75%
2. Verify language pair matches (EN-FR not EN-DE)
3. Import more TM entries from related projects
4. Check TM entries exist (Translation Memory screen)

---

## Troubleshooting

### API Key Issues

**Problem**: "Invalid API Key" error

**Solutions**:
1. Verify key is copied correctly (no extra spaces)
2. Check key hasn't expired
3. Verify billing is set up on provider account
4. Test connection in Settings
5. Try regenerating key on provider website

---

**Problem**: "Rate limit exceeded"

**Solutions**:
1. Wait a few minutes and retry
2. Reduce batch size
3. Reduce concurrent requests (Settings → Advanced)
4. Upgrade to higher-tier plan on provider

---

### Game Path Not Detected

**Problem**: Auto-detect doesn't find games

**Solutions**:
1. Verify Steam is installed
2. Verify games are installed (check Steam library)
3. Check Steam is on default drive (C:\)
4. Add path manually:
   - Find Steam Workshop folder
   - Typical: `C:\Program Files (x86)\Steam\steamapps\workshop\content\[APP_ID]`
   - Add in Settings → Games → Add Custom Path

**App IDs**:
- Warhammer III: `1142710`
- Three Kingdoms: `779340`
- Warhammer II: `594570`
- Rome II: `214950`

---

### Mod Extraction Failures

**Problem**: "Failed to extract mod files"

**Possible Causes**:
- Mod is encrypted
- File permissions issue
- Disk space issue
- Corrupted mod file

**Solutions**:
1. Verify mod is subscribed in Steam Workshop
2. Verify mod is downloaded (check Steam Downloads)
3. Re-subscribe to mod in Workshop
4. Check disk space (need ~500 MB free)
5. Run TWMT as administrator (right-click → Run as administrator)
6. Verify mod files exist in Workshop folder

---

### Translation Errors

**Problem**: "Translation failed" for specific entries

**Possible Causes**:
- Entry text too long (exceeds model limits)
- Entry contains unsupported characters
- Network timeout
- API service issue

**Solutions**:
1. Retry the failed entry
2. Shorten the text (if possible)
3. Try a different model
4. Increase network timeout (Settings → Advanced)
5. Check provider status page (status.anthropic.com, status.openai.com)

---

### Database Issues

**Problem**: Database errors or corruption

**Solutions**:
1. Close TWMT
2. Locate database: `%APPDATA%\TWMT\twmt.db`
3. Create backup copy
4. Open TWMT
5. Go to Settings → Database → Integrity Check
6. If check fails, restore from backup:
   - Close TWMT
   - Replace `twmt.db` with backup
   - Open TWMT

---

**Problem**: Database is very large (>1 GB)

**Solutions**:
1. Run Vacuum (Settings → Database → Vacuum)
2. Clean up old history:
   - Settings → History → Delete Old Versions
   - Keep last 30 days
3. Clean up TM:
   - Translation Memory → Cleanup
   - Delete low-quality entries
   - Delete unused entries (>365 days)

---

### Performance Problems

**Problem**: TWMT is slow or unresponsive

**Possible Causes**:
- Large project (10k+ entries)
- Too many projects open
- Memory issue
- Database needs optimization

**Solutions**:
1. Close unused project tabs
2. Reduce page size in DataGrid (20-30 entries)
3. Run database Vacuum
4. Restart TWMT
5. Close other applications (free up RAM)
6. Upgrade RAM (8 GB recommended)

---

### Need More Help?

- **Documentation**: [docs/](../docs/)
- **FAQ**: [faq.md](faq.md)
- **GitHub Issues**: Report bugs and request features
- **Discussions**: Ask questions and share tips

---

**Last Updated**: November 2025 | **Version**: 1.0
