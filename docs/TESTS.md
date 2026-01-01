# TWMT Test Suite Documentation

This document provides a comprehensive overview of all tests in the TWMT application.

## Test Summary

| Category | Files | Tests |
|----------|-------|-------|
| Widget/Screen Tests | 14 | 352 |
| Service Tests | 7 | 241 |
| Repository Tests | 6 | 182 |
| Provider Tests | 7 | 232 |
| Smoke Test | 1 | 1 |
| **Total** | **35** | **1008** |

---

## Test Structure

```
test/
├── features/                          # Widget/Screen tests (352 tests)
│   ├── game_translation/screens/
│   │   └── game_translation_screen_test.dart
│   ├── glossary/screens/
│   │   └── glossary_screen_test.dart
│   ├── help/screens/
│   │   └── help_screen_test.dart
│   ├── home/screens/
│   │   └── home_screen_test.dart
│   ├── mods/screens/
│   │   └── mods_screen_test.dart
│   ├── pack_compilation/screens/
│   │   └── pack_compilation_screen_test.dart
│   ├── projects/screens/
│   │   ├── projects_screen_test.dart
│   │   └── project_detail_screen_test.dart
│   ├── settings/screens/
│   │   └── settings_screen_test.dart
│   ├── translation_editor/screens/
│   │   ├── export_progress_screen_test.dart
│   │   ├── translation_editor_screen_test.dart
│   │   ├── translation_progress_screen_test.dart
│   │   └── validation_review_screen_test.dart
│   └── translation_memory/screens/
│       └── translation_memory_screen_test.dart
├── unit/                              # Unit tests
│   ├── services/                      # Service tests (241 tests)
│   │   ├── diff_calculator_test.dart
│   │   ├── glossary_matcher_test.dart
│   │   ├── glossary_matching_service_test.dart
│   │   ├── settings_service_test.dart
│   │   ├── similarity_calculator_test.dart
│   │   ├── text_normalizer_test.dart
│   │   └── translation_validation_service_test.dart
│   └── repositories/                  # Repository tests (182 tests)
│       ├── game_installation_repository_test.dart
│       ├── glossary_repository_test.dart
│       ├── language_repository_test.dart
│       ├── project_repository_test.dart
│       ├── settings_repository_test.dart
│       └── translation_unit_repository_test.dart
├── providers/                         # Provider tests (232 tests)
│   ├── batch_operations_provider_test.dart
│   ├── batch_selection_provider_test.dart
│   ├── batch_state_provider_test.dart
│   ├── export_provider_test.dart
│   ├── import_provider_test.dart
│   ├── mod_update_provider_test.dart
│   └── translation_statistics_provider_test.dart
├── helpers/                           # Test utilities
│   ├── test_helpers.dart
│   └── mock_providers.dart
└── widget_test.dart                   # Smoke test
```

---

# Part 1: Service Tests

## 1. SettingsService Tests

**File:** `test/unit/services/settings_service_test.dart`

### getSetting
| Test | Description |
|------|-------------|
| should return setting when found | Retrieves existing setting |
| should return null when setting not found | Handles missing setting |
| should throw when repository throws | Error propagation |

### getString
| Test | Description |
|------|-------------|
| should return string value when setting exists | String retrieval |
| should return null when setting not found | Missing string handling |

### getInt
| Test | Description |
|------|-------------|
| should return int value when setting exists | Integer retrieval |
| should return null when setting not found | Missing int handling |

### getBool
| Test | Description |
|------|-------------|
| should return bool value when setting exists | Boolean retrieval |
| should return null when setting not found | Missing bool handling |

### getJson
| Test | Description |
|------|-------------|
| should return decoded JSON when setting exists | JSON parsing |
| should return null when setting not found | Missing JSON handling |

### setString / setInt / setBool
| Test | Description |
|------|-------------|
| should create or update string setting | String persistence |
| should create or update int setting | Integer persistence |
| should create or update bool setting | Boolean persistence |

### Batch Size Settings
| Test | Description |
|------|-------------|
| should set default batch size with valid value | Valid batch size |
| should throw when batch size is less than 1 | Minimum validation |
| should throw when batch size exceeds 100 | Maximum validation |
| should get default batch size | Retrieval |

### Parallel Batches Settings
| Test | Description |
|------|-------------|
| should set default parallel batches with valid value | Valid parallel batches |
| should throw when parallel batches is less than 1 | Minimum validation |
| should throw when parallel batches exceeds 10 | Maximum validation |
| should get default parallel batches | Retrieval |

### Path Settings
| Test | Description |
|------|-------------|
| should get RPFM path | RPFM path retrieval |
| should get Total War game | Game retrieval |
| should get default game ID | Game ID retrieval |

### getAllSettings
| Test | Description |
|------|-------------|
| should return all settings | Full settings list |

---

## 2. GlossaryMatchingService Tests

**File:** `test/unit/services/glossary_matching_service_test.dart`

### findMatchingTerms
| Test | Description |
|------|-------------|
| should return matching terms from glossary | Basic matching |
| should return multiple matches | Multiple term matching |
| should return empty list when no matches | No matches handling |
| should handle database errors | Error handling |

### applySubstitutions
| Test | Description |
|------|-------------|
| should replace matched terms in target text | Term replacement |
| should handle multiple substitutions | Multiple replacements |
| should preserve non-matched text | Text preservation |

### checkConsistency
| Test | Description |
|------|-------------|
| should validate glossary term consistency | Consistency check |
| should return issues for inconsistent terms | Issue detection |
| should handle errors gracefully | Error handling |

---

## 3. TranslationValidationService Tests

**File:** `test/unit/services/translation_validation_service_test.dart`

### Empty Translation Detection
| Test | Description |
|------|-------------|
| should return error when translation is empty | Empty detection |
| should return error when translation is whitespace only | Whitespace detection |
| should not return issue when translation has content | Valid content |

### Length Difference Validation
| Test | Description |
|------|-------------|
| should return warning when translation is significantly longer | Long translation |
| should not return issue when length difference is acceptable | Acceptable length |

### Missing Variables Detection
| Test | Description |
|------|-------------|
| should return error when {0} variable is missing | Curly brace vars |
| should return error when %s variable is missing | Printf vars |
| should return error when [%s] variable is missing | Bracket vars |
| should return error when ${var} variable is missing | Dollar vars |
| should not return issue when all variables are present | Valid variables |

### Whitespace Issues
| Test | Description |
|------|-------------|
| should return warning for leading whitespace | Leading whitespace |
| should return warning for trailing whitespace | Trailing whitespace |
| should return warning for double spaces | Double spaces |
| should not return issue for clean whitespace | Clean text |

### Punctuation Mismatch
| Test | Description |
|------|-------------|
| should return info when ending punctuation differs | Punctuation diff |
| should not return issue when punctuation matches | Matching punctuation |
| should handle question mark vs period | Mixed punctuation |

### Case Mismatch
| Test | Description |
|------|-------------|
| should return info when source starts uppercase but translation lowercase | Case detection |
| should not return issue when case matches | Matching case |

### Number Validation
| Test | Description |
|------|-------------|
| should return warning when number is missing | Missing number |
| should not return issue when all numbers are present | Valid numbers |
| should return error when number has been reformatted | Reformatted number |
| should return error when thousand separators added | Separator changes |

### Auto-Fix
| Test | Description |
|------|-------------|
| should apply fix when issue is auto-fixable | Apply fix |
| should return error when issue is not auto-fixable | Non-fixable |
| should return error when autoFixValue is null | Null fix value |
| should apply whitespace fix | Whitespace fix |
| should return original text when no auto-fixable issues | No fixes needed |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle very long text | Long text |
| should handle special characters | Special chars |
| should handle unicode characters | Unicode |
| should handle multiple issues at once | Multiple issues |

---

## 4. SimilarityCalculator Tests

**File:** `test/unit/services/similarity_calculator_test.dart`

### calculateSimilarity
| Test | Description |
|------|-------------|
| should return 1.0 for identical strings | Identical strings |
| should return 0.0 for completely different strings | Different strings |
| should return value between 0 and 1 for similar strings | Partial similarity |
| should handle empty strings | Empty strings |
| should be case-insensitive by default | Case insensitivity |

### calculateLevenshteinSimilarity
| Test | Description |
|------|-------------|
| should return 1.0 for identical strings | Identical |
| should calculate correct distance for one edit | One edit |
| should calculate correct distance for multiple edits | Multiple edits |

### calculateJaroWinklerSimilarity
| Test | Description |
|------|-------------|
| should return 1.0 for identical strings | Identical |
| should give prefix bonus | Prefix bonus |
| should handle transpositions | Transpositions |

### calculateTokenSimilarity
| Test | Description |
|------|-------------|
| should return 1.0 for identical token sets | Identical tokens |
| should handle different word order | Word order |
| should handle partial overlap | Partial overlap |

### calculateNGramSimilarity
| Test | Description |
|------|-------------|
| should return 1.0 for identical strings | Identical |
| should handle short strings | Short strings |
| should calculate bigram overlap | Bigram calculation |

### areSimilar
| Test | Description |
|------|-------------|
| should return true when above threshold | Above threshold |
| should return false when below threshold | Below threshold |
| should use default threshold of 0.85 | Default threshold |

### Context Boost
| Test | Description |
|------|-------------|
| should boost similarity for matching categories | Category match |
| should not boost for different categories | No category match |

### Models
| Test | Description |
|------|-------------|
| SimilarityBreakdown should store all scores | Breakdown storage |
| ScoreWeights should have correct defaults | Default weights |

---

## 5. DiffCalculator Tests

**File:** `test/unit/services/diff_calculator_test.dart`

### calculateDiff
| Test | Description |
|------|-------------|
| should return empty list for identical strings | Identical |
| should detect insertions | Insertions |
| should detect deletions | Deletions |
| should detect replacements | Replacements |
| should handle empty strings | Empty strings |
| should handle special characters | Special chars |

### calculateWordDiff
| Test | Description |
|------|-------------|
| should return empty list for identical strings | Identical |
| should detect word insertions | Word insertions |
| should detect word deletions | Word deletions |
| should detect word changes | Word changes |
| should preserve word boundaries | Word boundaries |

### DiffSegment
| Test | Description |
|------|-------------|
| should store type and text correctly | Storage |
| should support equality comparison | Equality |

### DiffStats
| Test | Description |
|------|-------------|
| should calculate insertions count | Insertion count |
| should calculate deletions count | Deletion count |
| should calculate unchanged count | Unchanged count |
| should calculate total changes | Total changes |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle very long strings | Long strings |
| should handle unicode characters | Unicode |
| should handle mixed content | Mixed content |

---

## 6. TextNormalizer Tests

**File:** `test/unit/services/text_normalizer_test.dart`

### normalize
| Test | Description |
|------|-------------|
| should return normalized text with default options | Default normalization |
| should normalize whitespace | Whitespace normalization |
| should convert to lowercase when enabled | Lowercase conversion |
| should remove XML/HTML tags | Tag removal |
| should remove BBCode | BBCode removal |
| should remove Markdown formatting | Markdown removal |
| should preserve printf placeholders | Placeholder preservation |

### Curly Quotes and Dashes
| Test | Description |
|------|-------------|
| should normalize curly single quotes | Single quotes |
| should normalize curly double quotes | Double quotes |
| should normalize em dashes | Em dashes |
| should normalize en dashes | En dashes |
| should normalize ellipsis | Ellipsis |

### tokenize
| Test | Description |
|------|-------------|
| should split text into tokens | Basic tokenization |
| should handle punctuation | Punctuation handling |
| should handle multiple spaces | Space handling |

### getNGrams
| Test | Description |
|------|-------------|
| should generate bigrams | Bigram generation |
| should generate trigrams | Trigram generation |
| should handle short strings | Short strings |

### NormalizationOptions
| Test | Description |
|------|-------------|
| default should have standard settings | Default settings |
| strict should enable all normalizations | Strict settings |
| lenient should disable most normalizations | Lenient settings |

---

## 7. GlossaryMatcher Tests

**File:** `test/unit/services/glossary_matcher_test.dart`

### findMatches
| Test | Description |
|------|-------------|
| should find basic term matches | Basic matching |
| should support whole word matching | Whole word |
| should handle case sensitivity | Case sensitivity |
| should handle case insensitivity | Case insensitivity |
| should prioritize longer matches | Overlap handling |
| should find multiple occurrences | Multiple occurrences |

### applySubstitutions
| Test | Description |
|------|-------------|
| should replace matched terms | Term replacement |
| should handle multiple matches | Multiple replacements |
| should preserve case when configured | Case preservation |

### highlightMatches
| Test | Description |
|------|-------------|
| should add markers around matches | Marker addition |
| should handle nested markers | Nested handling |

### getMatchStatistics
| Test | Description |
|------|-------------|
| should calculate match count | Match count |
| should calculate coverage percentage | Coverage calculation |
| should handle empty text | Empty text |

---

# Part 2: Repository Tests

## 1. ProjectRepository Tests

**File:** `test/unit/repositories/project_repository_test.dart`

### CRUD Operations
| Test | Description |
|------|-------------|
| should insert project and return ID | Insert |
| should get project by ID | Get by ID |
| should return null for non-existent ID | Missing ID |
| should get all projects | Get all |
| should update project | Update |
| should delete project | Delete |

### Custom Queries
| Test | Description |
|------|-------------|
| should get projects by status | Filter by status |
| should get projects by game installation | Filter by game |

### Mod Update Impact
| Test | Description |
|------|-------------|
| should set mod update impact | Set impact |
| should clear mod update impact | Clear impact |
| should count projects with mod update impact | Count impact |

### Project Types
| Test | Description |
|------|-------------|
| should get projects by type | Filter by type |
| should get game translations by installation | Game translations |
| should get mod translations by installation | Mod translations |

---

## 2. LanguageRepository Tests

**File:** `test/unit/repositories/language_repository_test.dart`

### CRUD Operations
| Test | Description |
|------|-------------|
| should insert language and return ID | Insert |
| should get language by ID | Get by ID |
| should get all languages | Get all |
| should update language | Update |
| should delete language | Delete |

### Custom Queries
| Test | Description |
|------|-------------|
| should get language by code | Get by code |
| should get active languages | Filter active |
| should get languages by IDs | Batch get |
| should check if code exists | Code exists |
| should get custom languages | Custom languages |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle unicode characters | Unicode |
| should handle status updates | Status changes |

---

## 3. GlossaryRepository Tests

**File:** `test/unit/repositories/glossary_repository_test.dart`

### Glossary CRUD
| Test | Description |
|------|-------------|
| should insert glossary | Insert |
| should get glossary by ID | Get by ID |
| should get glossary by name | Get by name |
| should get all glossaries | Get all |
| should update glossary | Update |
| should delete glossary | Delete |

### GlossaryEntry CRUD
| Test | Description |
|------|-------------|
| should insert entry | Insert entry |
| should get entry by ID | Get entry by ID |
| should get all entries | Get all entries |
| should update entry | Update entry |
| should delete entry | Delete entry |

### Entry Queries
| Test | Description |
|------|-------------|
| should get entries by glossary | Filter by glossary |
| should find duplicate entry | Duplicate detection |
| should search entries | Search |
| should get entry count | Count |

### Usage Tracking
| Test | Description |
|------|-------------|
| should increment usage count | Increment usage |
| should get usage stats | Usage statistics |

### DeepL Mappings
| Test | Description |
|------|-------------|
| should create DeepL mapping | Create mapping |
| should get mapping by glossary | Get mapping |
| should update sync status | Update status |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle special characters | Special chars |
| should handle unicode | Unicode |

---

## 4. SettingsRepository Tests

**File:** `test/unit/repositories/settings_repository_test.dart`

### CRUD Operations
| Test | Description |
|------|-------------|
| should insert setting | Insert |
| should get setting by ID | Get by ID |
| should get all settings | Get all |
| should update setting | Update |
| should delete setting | Delete |

### Key-Based Access
| Test | Description |
|------|-------------|
| should get setting by key | Get by key |
| should get value by key | Get value |
| should set value by key | Set value |
| should create setting if not exists | Upsert |

### Value Types
| Test | Description |
|------|-------------|
| should handle string values | String |
| should handle integer values | Integer |
| should handle boolean values | Boolean |
| should handle JSON values | JSON |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle empty values | Empty values |
| should handle special characters | Special chars |
| should handle unicode | Unicode |
| should handle long values | Long values |

---

## 5. GameInstallationRepository Tests

**File:** `test/unit/repositories/game_installation_repository_test.dart`

### CRUD Operations
| Test | Description |
|------|-------------|
| should insert game installation | Insert |
| should get by ID | Get by ID |
| should get all | Get all |
| should update | Update |
| should delete | Delete |

### Custom Queries
| Test | Description |
|------|-------------|
| should get by game code | Filter by code |
| should get valid installations | Filter valid |

### Boolean Fields
| Test | Description |
|------|-------------|
| should handle isAutoDetected flag | Auto-detected |
| should handle isValid flag | Valid flag |

### Nullable Fields
| Test | Description |
|------|-------------|
| should handle nullable path | Null path |
| should handle nullable version | Null version |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle paths with special characters | Special chars |
| should handle very long paths | Long paths |

---

## 6. TranslationUnitRepository Tests

**File:** `test/unit/repositories/translation_unit_repository_test.dart`

### CRUD Operations
| Test | Description |
|------|-------------|
| should insert translation unit | Insert |
| should get by ID | Get by ID |
| should get all | Get all |
| should update | Update |
| should delete | Delete |

### Project Queries
| Test | Description |
|------|-------------|
| should get by project | Filter by project |
| should get by key | Filter by key |

### Obsolete Handling
| Test | Description |
|------|-------------|
| should mark as obsolete | Mark obsolete |
| should get active units | Filter active |
| should get obsolete units | Filter obsolete |

### Batch Operations
| Test | Description |
|------|-------------|
| should get by IDs | Batch get |
| should mark obsolete by keys | Batch obsolete |
| should reactivate by keys | Batch reactivate |
| should update source texts | Batch update |

### Joined Queries
| Test | Description |
|------|-------------|
| should get translation rows joined | JOIN query |
| should include version data | Version data |

### Edge Cases
| Test | Description |
|------|-------------|
| should handle special characters | Special chars |
| should handle unicode | Unicode |
| should handle long text | Long text |

---

# Part 3: Provider Tests

## 1. BatchSelectionProvider Tests

**File:** `test/providers/batch_selection_provider_test.dart`

### BatchSelectionState
| Test | Description |
|------|-------------|
| should have empty initial state | Initial state |
| should track selected IDs | Selection tracking |
| should calculate selectedCount | Count calculation |
| should detect hasSelection | Has selection |
| should support copyWith | Copy with |

### BatchSelectionNotifier
| Test | Description |
|------|-------------|
| should toggle selection on | Toggle on |
| should toggle selection off | Toggle off |
| should select single item | Select |
| should deselect single item | Deselect |
| should select multiple items | Select multiple |
| should select all from list | Select all |
| should clear selection | Clear |
| should select range | Range selection |
| should invert selection | Invert |

---

## 2. BatchOperationsProvider Tests

**File:** `test/providers/batch_operations_provider_test.dart`

### BatchOperationState
| Test | Description |
|------|-------------|
| should have correct initial state | Initial state |
| should track operation type | Operation type |
| should track progress | Progress tracking |
| should calculate percentage | Percentage |
| should detect isActive | Active detection |
| should detect isComplete | Complete detection |

### BatchOperationType
| Test | Description |
|------|-------------|
| should have all operation types | Type completeness |
| should support translate type | Translate type |
| should support validate type | Validate type |
| should support export type | Export type |

### BatchTranslateState
| Test | Description |
|------|-------------|
| should track translation progress | Progress |
| should track errors | Error tracking |
| should calculate success rate | Success rate |

### BatchValidationState
| Test | Description |
|------|-------------|
| should track validation issues | Issue tracking |
| should categorize by severity | Severity categories |
| should calculate issue counts | Issue counts |

---

## 3. BatchStateProvider Tests

**File:** `test/providers/batch_state_provider_test.dart`

### BatchState
| Test | Description |
|------|-------------|
| should have correct initial state | Initial state |
| should track batch status | Status tracking |
| should track items processed | Progress |
| should calculate remaining items | Remaining |
| should detect completion | Completion |

### BatchStatus
| Test | Description |
|------|-------------|
| should have idle status | Idle |
| should have running status | Running |
| should have paused status | Paused |
| should have completed status | Completed |
| should have failed status | Failed |
| should have cancelled status | Cancelled |

### Lifecycle Simulation
| Test | Description |
|------|-------------|
| should simulate start to completion | Full lifecycle |
| should simulate start to failure | Failure path |
| should simulate pause and resume | Pause/resume |
| should simulate cancellation | Cancellation |

---

## 4. TranslationStatisticsProvider Tests

**File:** `test/providers/translation_statistics_provider_test.dart`

### TranslationStats
| Test | Description |
|------|-------------|
| should have correct initial values | Initial values |
| should track total translations | Total count |
| should track translations today | Today count |
| should track last translation time | Last time |
| should detect hasTranslations | Has translations |
| should detect hasTranslationsToday | Has today |
| should calculate timeSinceLastTranslation | Time since |

### State Accumulation
| Test | Description |
|------|-------------|
| should accumulate translation counts | Accumulation |
| should update last translation time | Time update |

---

## 5. ImportProvider Tests

**File:** `test/providers/import_provider_test.dart`

### ImportProgressState
| Test | Description |
|------|-------------|
| should have correct initial state | Initial state |
| should track current step | Step tracking |
| should track items processed | Progress |
| should calculate progress percentage | Percentage |
| should detect isComplete | Completion |

### ImportSettingsStateNotifier
| Test | Description |
|------|-------------|
| should update file path | File path |
| should update import options | Options |
| should reset settings | Reset |

### ImportPreviewDataNotifier
| Test | Description |
|------|-------------|
| should store preview data | Preview storage |
| should calculate statistics | Statistics |
| should clear preview | Clear |

### ImportConflictsDataNotifier
| Test | Description |
|------|-------------|
| should detect conflicts | Conflict detection |
| should categorize conflicts | Categorization |
| should calculate conflict counts | Counts |

### ConflictResolutionsDataNotifier
| Test | Description |
|------|-------------|
| should store resolutions | Resolution storage |
| should update resolution | Update |
| should apply bulk resolution | Bulk apply |

### ImportProgressNotifier
| Test | Description |
|------|-------------|
| should track import progress | Progress |
| should handle errors | Error handling |
| should complete import | Completion |

### ImportResultDataNotifier
| Test | Description |
|------|-------------|
| should store import result | Result storage |
| should track success/failure counts | Counts |

---

## 6. ExportProvider Tests

**File:** `test/providers/export_provider_test.dart`

### ExportProgressState
| Test | Description |
|------|-------------|
| should have correct initial state | Initial state |
| should track current step | Step tracking |
| should track items processed | Progress |
| should calculate progress percentage | Percentage |
| should detect isComplete | Completion |

### ExportSettingsStateNotifier
| Test | Description |
|------|-------------|
| should update export format | Format |
| should update export options | Options |
| should reset settings | Reset |

### ExportPreviewDataNotifier
| Test | Description |
|------|-------------|
| should store preview data | Preview storage |
| should calculate row count | Row count |
| should clear preview | Clear |

### ExportProgressNotifier
| Test | Description |
|------|-------------|
| should track export progress | Progress |
| should handle errors | Error handling |
| should complete export | Completion |

### ExportResultDataNotifier
| Test | Description |
|------|-------------|
| should store export result | Result storage |
| should store file path | File path |

### ExportFormat/ExportColumn Enums
| Test | Description |
|------|-------------|
| should have all format options | Format options |
| should have all column options | Column options |

---

## 7. ModUpdateProvider Tests

**File:** `test/providers/mod_update_provider_test.dart`

### ModUpdateStatus
| Test | Description |
|------|-------------|
| should have pending status | Pending |
| should have checking status | Checking |
| should have available status | Available |
| should have downloading status | Downloading |
| should have installing status | Installing |
| should have completed status | Completed |
| should have failed status | Failed |

### ModUpdateInfo
| Test | Description |
|------|-------------|
| should track mod ID | Mod ID |
| should track update status | Status |
| should track progress | Progress |
| should track error message | Error |
| should support copyWith | Copy with |

### ModUpdateQueueNotifier
| Test | Description |
|------|-------------|
| should add to queue | Add |
| should remove from queue | Remove |
| should process queue | Process |
| should handle errors | Error handling |
| should clear queue | Clear |

### Lifecycle Simulation
| Test | Description |
|------|-------------|
| should simulate full update cycle | Full cycle |
| should handle update failure | Failure |
| should handle cancellation | Cancellation |

---

# Part 4: Widget/Screen Tests

For detailed widget/screen test documentation, see [UNIT_TESTS.md](./UNIT_TESTS.md).

## Screen Test Summary

| Screen | Test Groups | Tests |
|--------|-------------|-------|
| HomeScreen | 7 | 14 |
| ProjectsScreen | 11 | 16 |
| ProjectDetailScreen | 12 | 17 |
| TranslationEditorScreen | 11 | 18 |
| TranslationProgressScreen | 12 | 17 |
| ValidationReviewScreen | 12 | 18 |
| ExportProgressScreen | 13 | 19 |
| GlossaryScreen | 10 | 18 |
| SettingsScreen | 12 | 21 |
| HelpScreen | 10 | 17 |
| ModsScreen | 14 | 27 |
| GameTranslationScreen | 11 | 18 |
| PackCompilationScreen | 13 | 21 |
| TranslationMemoryScreen | 12 | 22 |
| **Total** | **160** | **263** |

---

# Test Helpers

## test_helpers.dart

Provides utility functions for widget testing:

```dart
// Widget wrapping with ProviderScope
createTestableWidget(Widget child, {List<Override>? overrides})

// Widget wrapping with Scaffold
createTestableWidgetWithScaffold(Widget child, {List<Override>? overrides})

// Widget wrapping with custom theme
createThemedTestableWidget(Widget child, {List<Override>? overrides, ThemeData? theme})

// Pump and settle helper
pumpAndSettleHelper(WidgetTester tester)

// Find by key
findByKey(String key)

// Find by text containing
findByTextContaining(String text)
```

## mock_providers.dart

Provides mock model factories:

```dart
// Single model factories
createMockProject({...})
createMockLanguage({...})
createMockDetectedMod({...})
createMockGameInstallation({...})
createMockGlossary({...})

// List factories
createMockProjectList({int count = 3})
createMockLanguageList()
createMockDetectedModList({int count = 5})
createMockGlossaryList({int count = 3})
```

---

# Running Tests

## Run all tests
```bash
flutter test
```

## Run specific category
```bash
# Widget tests
flutter test test/features/

# Service tests
flutter test test/unit/services/

# Repository tests
flutter test test/unit/repositories/

# Provider tests
flutter test test/providers/
```

## Run specific file
```bash
flutter test test/unit/services/settings_service_test.dart
```

## Run with coverage
```bash
flutter test --coverage
```

## Run in verbose mode
```bash
flutter test --reporter expanded
```

## Run with concurrency
```bash
flutter test --concurrency=4
```

---

# Best Practices

## Test Organization
- Group tests by functionality
- Use descriptive test names: `should [action] when [condition]`
- Follow AAA pattern: Arrange, Act, Assert

## Mocking
- Use `mocktail` for mocking dependencies
- Register fallback values for custom types
- Mock at the boundary (repositories, external services)

## Database Tests
- Use in-memory SQLite: `inMemoryDatabasePath`
- Initialize FFI in `setUpAll`
- Clean up in `tearDown`

## Provider Tests
- Use `ProviderContainer` for isolation
- Dispose container in `tearDown`
- Override dependencies with mocks

## Widget Tests
- Wrap with `createTestableWidget` helper
- Use `SizedBox` to constrain dimensions
- Mock Riverpod providers as needed
