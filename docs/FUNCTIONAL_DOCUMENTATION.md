# TWMT - Total War Mods Translator

## Functional Documentation

**Version:** 1.0.0
**Platform:** Windows 10/11 Desktop
**Technology:** Flutter with Fluent Design

---

## Table of Contents

1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Getting Started](#getting-started)
4. [User Interface](#user-interface)
5. [Project Management](#project-management)
6. [Translation Editor](#translation-editor)
7. [Translation Memory](#translation-memory)
8. [Glossary Management](#glossary-management)
9. [LLM Integration](#llm-integration)
10. [Validation System](#validation-system)
11. [Import & Export](#import--export)
12. [Settings & Configuration](#settings--configuration)
13. [Keyboard Shortcuts](#keyboard-shortcuts)
14. [Data Storage](#data-storage)

---

## Overview

TWMT (Total War Mods Translator) is a professional-grade Windows desktop application designed to streamline translation workflows for Total War Workshop mods. It combines AI-powered machine translation with Translation Memory, glossary management, and advanced quality validation to help modders translate content efficiently while maintaining consistency and quality.

### Supported Total War Games

- Warhammer III
- Warhammer II
- Warhammer
- Rome II
- Attila
- Three Kingdoms
- Troy
- Pharaoh

### Core Capabilities

- **AI-Powered Translation**: Leverage LLM providers (Anthropic Claude, OpenAI GPT, DeepL) for intelligent batch translation
- **Translation Memory**: Reuse previous translations with fuzzy matching algorithms
- **Glossary Management**: Maintain consistent terminology across projects
- **Quality Validation**: Automatic detection and fixing of translation issues
- **Steam Workshop Integration**: Auto-detect mods and track updates
- **Pack Compilation**: Export translations back to game-compatible formats

---

## Key Features

### LLM-Powered Translation

| Feature | Description |
|---------|-------------|
| Multiple Providers | Anthropic Claude (recommended), OpenAI GPT, DeepL |
| Batch Processing | Translate 25-100 entries per batch |
| Parallel Batches | Process up to 5 batches concurrently |
| Cost Tracking | Real-time token usage and cost estimation |
| Streaming Support | Real-time translation progress for compatible providers |
| Rate Limiting | Automatic handling of API quotas (RPM/TPM) |

### Translation Memory (TM)

| Feature | Description |
|---------|-------------|
| Exact Matching | O(1) hash-based lookup for identical phrases |
| Fuzzy Matching | 3-algorithm hybrid (Levenshtein, Jaro-Winkler, Token-based) |
| Auto-Accept | Automatically apply matches with >95% similarity |
| Quality Scoring | Confidence scores from 0.0 to 1.0 |
| Context Awareness | Category-based boost (+3% for matching context) |
| TMX Support | Import/Export in industry-standard TMX format |

### Glossary System

| Feature | Description |
|---------|-------------|
| Global Glossaries | Universal terminology for all games/projects |
| Game-Specific | Terminology scoped to specific Total War titles |
| Forbidden Terms | Mark terms that should not appear in translations |
| Variants | Handle term variations with notes |
| Import/Export | CSV, Excel, TBX format support |

### Quality Validation

| Check Type | Description |
|------------|-------------|
| Empty Detection | Ensure translations are not empty |
| Length Check | Warn if translation deviates >100% from source |
| Special Characters | Verify HTML/XML tags are preserved |
| Whitespace | Detect leading/trailing space differences |
| Punctuation | Ensure punctuation is preserved |
| Case Mismatch | Detect ALL CAPS/lowercase inconsistencies |
| Number Check | Verify all numbers from source are present |

---

## Getting Started

### System Requirements

- Windows 10 or Windows 11
- 8 GB RAM minimum (16 GB recommended)
- 500 MB free disk space
- Internet connection for LLM providers

### First Launch

1. **Configure Game Paths**: Go to Settings > General and set paths to your Total War game installations
2. **Setup LLM Provider**: Go to Settings > LLM Providers and configure at least one API key
3. **Scan for Mods**: Navigate to Mods screen and click Refresh to detect Workshop mods
4. **Create a Project**: Select a mod and create a new translation project

### Application Data Location

All application data is stored in:
```
%APPDATA%\TWMT\
├── twmt.db          # SQLite database
├── config\          # Configuration files
├── logs\            # Application logs
└── cache\           # Temporary cache
```

---

## User Interface

### Navigation Sidebar

The main navigation is located on the left side of the application window (250px width) with the following sections:

| Section | Shortcut | Description |
|---------|----------|-------------|
| Home | Ctrl+1 | Dashboard with statistics and recent projects |
| Mods | Ctrl+2 | Browse detected Steam Workshop mods |
| Projects | Ctrl+3 | Translation project management |
| Pack Compilation | Ctrl+4 | Compile translations into pack files |
| Glossary | Ctrl+5 | Manage terminology glossaries |
| Translation Memory | Ctrl+6 | Browse and manage TM entries |
| Settings | Ctrl+7 | Application configuration |

### Design System

TWMT uses Microsoft Fluent Design System for a native Windows experience:

- **Icons**: Fluent UI System Icons exclusively
- **Interactions**: Hover effects with opacity changes (no Material ripples)
- **Animations**: Smooth 100-200ms transitions
- **Theme**: Light and Dark mode support

---

## Project Management

### Creating a Project

1. Navigate to the **Mods** screen
2. Select a mod from the list
3. Click **Create Project**
4. Configure project settings:
   - Project name
   - Target languages
   - Batch size (default: 25)
   - Custom translation prompt (optional)

### Project Overview

The Project Detail screen shows:

- **Overview Section**: Project name, game, mod ID
- **Languages Section**: Progress cards for each target language
- **Statistics**: Total units, translated, pending, approved

### Project Status

| Status | Description |
|--------|-------------|
| Pending | Project created, no translations started |
| Translating | Translation in progress |
| Completed | All translations done |
| Error | Translation encountered errors |

---

## Translation Editor

The Translation Editor is the main workspace for translating content.

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Toolbar: [Translate All] [Translate Selected] [Validate]  │
├──────────┬──────────────────────────────────────────────────┤
│          │                                                  │
│  Filters │              DataGrid                            │
│          │  Key | Source | Translation | Status | Actions   │
│  Stats   │                                                  │
│          │                                                  │
├──────────┴──────────────────────────────────────────────────┤
│  History / Validation Issues / Progress                     │
└─────────────────────────────────────────────────────────────┘
```

### DataGrid Features

- **Virtualized**: Handles 10,000+ rows efficiently
- **Inline Editing**: Double-click to edit translations
- **Sorting**: Click column headers to sort
- **Filtering**: Filter by status, validation issues
- **Multi-Select**: Select multiple rows for batch operations

### Toolbar Actions

| Action | Description |
|--------|-------------|
| Translate All | Translate all pending entries |
| Translate Selected | Translate only selected entries |
| Validate | Run validation checks on translations |
| Export | Export translations to file |
| Settings | Configure translation parameters |

### Translation Workflow

1. **TM Exact Match**: Check for 100% matches in Translation Memory
2. **TM Fuzzy Match**: Check for similar matches (>85% similarity)
3. **LLM Translation**: Send remaining entries to LLM provider
4. **Validation**: Run quality checks
5. **Save**: Persist translations and update TM

### Batch Progress

During translation, a progress panel shows:

- Current phase (TM Lookup, LLM Translation, Validation, etc.)
- Units processed / total
- TM reuse rate
- Estimated time remaining
- Token usage

---

## Translation Memory

### How TM Works

Translation Memory stores previously translated content and reuses it for new translations. This saves time and ensures consistency.

### Matching Algorithms

TWMT uses a hybrid approach combining three algorithms:

| Algorithm | Weight | Best For |
|-----------|--------|----------|
| Levenshtein Distance | 40% | Edit distance calculation |
| Jaro-Winkler | 30% | Typo detection, similar prefixes |
| Token-Based | 30% | Word order independence |

**Final Score** = (Levenshtein × 0.4) + (Jaro-Winkler × 0.3) + (Token × 0.3) + Context Boost

### TM Browser

The TM Browser screen allows you to:

- Browse all TM entries with pagination
- Search entries using full-text search
- Filter by language pair, quality score
- Edit or delete entries
- Import/Export TMX files
- View usage statistics

### TM Statistics

| Metric | Description |
|--------|-------------|
| Total Entries | Number of stored translations |
| Average Quality | Mean quality score |
| Tokens Saved | Estimated tokens saved through reuse |
| Reuse Rate | Percentage of translations from TM |

---

## Glossary Management

### Glossary Types

| Type | Scope | Use Case |
|------|-------|----------|
| Global | All games/projects | Universal terms (UI elements, common phrases) |
| Game-Specific | Single game | Game-specific terminology (factions, locations) |

### Glossary Entry Structure

```
Source Term: "Bretonnian"
├── Target: "Bretonnien" (masculine)
├── Target: "Bretonnienne" (feminine)
├── Notes: "Relates to Bretonnia faction"
└── Forbidden: false
```

### Managing Glossaries

1. **Create**: Add new glossary from Glossary screen
2. **Add Terms**: Enter source/target pairs with optional notes
3. **Variants**: Add multiple translations for same source term
4. **Forbidden Terms**: Mark terms that should never appear
5. **Import/Export**: Use CSV, Excel, or TBX formats

### Integration with Translation

- Glossary terms are included in LLM prompts
- Terms provide context for consistent translation
- Forbidden terms are flagged during validation

---

## LLM Integration

### Supported Providers

#### Anthropic Claude (Recommended)

| Property | Value |
|----------|-------|
| Models | Claude Sonnet 4.5, Claude Haiku 3.5 |
| Max Context | 200,000 tokens |
| Default Batch Size | 25 items |
| Rate Limits | 50 RPM, 40,000 TPM |

#### OpenAI GPT

| Property | Value |
|----------|-------|
| Models | GPT-4.1, GPT-4 Turbo, GPT-3.5 Turbo |
| Max Context | 128,000 tokens (GPT-4.1) |
| Default Batch Size | 40 items |
| Rate Limits | 60 RPM, 90,000 TPM |

#### DeepL

| Property | Value |
|----------|-------|
| Type | Specialized translation service |
| Pricing | Character-based (not tokens) |
| Default Batch Size | 50 items |
| Rate Limits | 100 RPM |

### Provider Configuration

1. Go to **Settings > LLM Providers**
2. Enter your API key for the desired provider
3. Click **Test Connection** to verify
4. Select default model
5. Set as active provider

### Token Management

- **Estimation**: Calculate tokens before translating
- **Cost Tracking**: View cumulative costs per batch
- **Optimization**: Automatic batch splitting if too large

### Prompt Structure

Each LLM request includes:

1. **System Prompt**: Role and translation rules
2. **Game Context**: Setting, lore, tone
3. **Project Context**: Custom instructions
4. **Few-Shot Examples**: 2-5 examples from TM
5. **Glossary Terms**: Relevant terminology
6. **Translation Request**: Units to translate

---

## Validation System

### Validation Checks

| Check | Severity | Auto-Fix |
|-------|----------|----------|
| Empty Translation | Error | No |
| Length Mismatch (>100%) | Warning | No |
| Missing Special Characters | Warning | No |
| Whitespace Issues | Warning | Yes |
| Punctuation Mismatch | Warning | No |
| Case Mismatch | Warning | Yes |
| Missing Numbers | Error | Yes |

### Validation Review Screen

When validation issues are found:

1. Review flagged translations in Validation Review screen
2. Apply auto-fixes where available
3. Manually correct remaining issues
4. Re-validate to confirm fixes

### Severity Levels

| Level | Description | Action |
|-------|-------------|--------|
| Error | Critical issue | Must fix before approval |
| Warning | Potential issue | Review recommended |
| Info | Informational | No action required |

---

## Import & Export

### Supported Formats

| Format | Import | Export | Description |
|--------|--------|--------|-------------|
| CSV | Yes | Yes | Comma-separated values |
| Excel (.xlsx) | Yes | Yes | Microsoft Excel format |
| JSON | Yes | Yes | JavaScript Object Notation |
| .loc | Yes | Yes | Total War game format |
| TMX | Yes | Yes | Translation Memory eXchange |
| TBX | Yes | Yes | TermBase eXchange (glossaries) |

### Import Workflow

1. Click **Import** from toolbar
2. Select file format
3. Choose file to import
4. Review conflict detection results
5. Select merge strategy:
   - Skip duplicates
   - Overwrite existing
   - Create new entries
6. Confirm import

### Export Options

- **All Entries**: Export complete translation
- **Selected Only**: Export selected rows
- **By Status**: Filter by translation status
- **By Language**: Export specific language

### Pack Compilation

To create game-ready translation packs:

1. Go to **Pack Compilation**
2. Create new compilation
3. Select projects and languages to include
4. Configure output settings
5. Click **Generate** to create .pack file

---

## Settings & Configuration

### General Settings

#### Game Installations

Configure paths for Total War game installations:

```
Game Installation Path: D:\Steam\steamapps\common\Total War WARHAMMER III
Workshop Path: D:\Steam\steamapps\workshop\content\1142710
```

#### RPFM Configuration

RPFM (Rusted Pack File Manager) is required for .loc file operations:

```
RPFM CLI Path: C:\Tools\rpfm\rpfm_cli.exe
Schema Path: C:\Tools\rpfm\schemas
```

#### Language Preferences

- Default source language
- Default target languages
- Interface language

### LLM Provider Settings

For each provider, configure:

- API Key (stored securely)
- Default Model
- Temperature (0.0 - 1.0)
- Max tokens per request

### Translation Preferences

| Setting | Default | Description |
|---------|---------|-------------|
| Batch Size | 25 | Units per LLM batch |
| Parallel Batches | 3 | Concurrent batch processing |
| Auto-Save Interval | 5 min | Auto-save frequency |
| TM Similarity Threshold | 85% | Minimum match score |
| Auto-Accept Threshold | 95% | Auto-apply TM matches |

### Appearance

- **Theme**: Light / Dark / System
- **Language**: English (UI language)

---

## Keyboard Shortcuts

### Navigation

| Shortcut | Action |
|----------|--------|
| Ctrl+1 | Go to Home |
| Ctrl+2 | Go to Mods |
| Ctrl+3 | Go to Projects |
| Ctrl+4 | Go to Pack Compilation |
| Ctrl+5 | Go to Glossary |
| Ctrl+6 | Go to Translation Memory |
| Ctrl+7 | Go to Settings |

### Translation Editor

| Shortcut | Action |
|----------|--------|
| Ctrl+T | Translate selected |
| Ctrl+A | Select all rows |
| Ctrl+V | Validate translations |
| Ctrl+E | Export |
| Enter | Edit cell |
| Escape | Exit edit mode |
| Tab | Next cell |
| Shift+Tab | Previous cell |

### General

| Shortcut | Action |
|----------|--------|
| Ctrl+S | Save |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+F | Find/Search |
| Ctrl+R | Refresh |
| Alt+F4 | Exit application |

---

## Data Storage

### Database

TWMT uses SQLite for all data storage:

- **Location**: `%APPDATA%\TWMT\twmt.db`
- **Mode**: WAL (Write-Ahead Logging)
- **Features**: FTS5 full-text search, 40+ optimized indexes

### Key Data Entities

| Entity | Description |
|--------|-------------|
| Projects | Translation project definitions |
| Translation Units | Source text entries from mods |
| Translation Versions | Translated text per language |
| Translation Memory | Reusable translation pairs |
| Glossaries | Terminology definitions |
| Batches | Translation batch metadata |

### Backup

To backup your data:

1. Close TWMT application
2. Copy `%APPDATA%\TWMT\twmt.db` to backup location
3. Optionally copy entire `%APPDATA%\TWMT\` folder

### Security

- **API Keys**: Stored in Windows Credential Manager (encrypted)
- **Database**: Local storage, no external transmission
- **Privacy**: No telemetry or usage tracking

---

## Troubleshooting

### Common Issues

#### LLM Connection Failed

1. Verify API key is correct
2. Check internet connection
3. Verify provider status page
4. Try test connection in Settings

#### Mod Not Detected

1. Verify game installation path
2. Check Workshop subscription
3. Click Refresh to rescan
4. Verify mod has .loc files

#### Translation Memory Not Matching

1. Check language pair settings
2. Verify TM has entries for language
3. Lower similarity threshold in settings

#### Export Failed

1. Verify RPFM is installed
2. Check RPFM path in settings
3. Verify output directory permissions

### Logs

Application logs are stored in:
```
%APPDATA%\TWMT\logs\
```

---

## Support

For bug reports and feature requests, please visit:
- GitHub Issues: [Repository URL]

---

*TWMT - Making Total War mod translation efficient and consistent.*
