# TWMT Unit Tests Documentation

This document provides an exhaustive list of all unit tests for the TWMT application screens.

## Test Structure

```
test/
├── helpers/
│   ├── test_helpers.dart          # Test utilities and widget wrappers
│   └── mock_providers.dart        # Mock models and data factories
├── features/
│   ├── home/screens/
│   │   └── home_screen_test.dart
│   ├── projects/screens/
│   │   ├── projects_screen_test.dart
│   │   └── project_detail_screen_test.dart
│   ├── translation_editor/screens/
│   │   ├── translation_editor_screen_test.dart
│   │   ├── translation_progress_screen_test.dart
│   │   ├── validation_review_screen_test.dart
│   │   └── export_progress_screen_test.dart
│   ├── glossary/screens/
│   │   └── glossary_screen_test.dart
│   ├── settings/screens/
│   │   └── settings_screen_test.dart
│   ├── help/screens/
│   │   └── help_screen_test.dart
│   ├── mods/screens/
│   │   └── mods_screen_test.dart
│   ├── game_translation/screens/
│   │   └── game_translation_screen_test.dart
│   ├── pack_compilation/screens/
│   │   └── pack_compilation_screen_test.dart
│   └── translation_memory/screens/
│       └── translation_memory_screen_test.dart
└── widget_test.dart               # Basic smoke test
```

---

## 1. HomeScreen Tests

**File:** `test/features/home/screens/home_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies the root widget is FluentScaffold |
| should render within a SingleChildScrollView | Verifies scrolling capability |
| should render a Column for layout | Verifies Column layout structure |

### Child Widgets
| Test | Description |
|------|-------------|
| should render WelcomeCard widget | Verifies WelcomeCard presence |
| should render StatsCards widget | Verifies StatsCards presence |
| should render RecentProjectsCard widget | Verifies RecentProjectsCard presence |

### Layout and Spacing
| Test | Description |
|------|-------------|
| should have correct padding of 24.0 | Verifies padding configuration |
| should have SizedBox widgets for spacing | Verifies spacing elements |

### StatelessWidget Behavior
| Test | Description |
|------|-------------|
| should be a StatelessWidget | Verifies widget type |
| should have const constructor | Verifies const constructor |

### Accessibility
| Test | Description |
|------|-------------|
| should be scrollable for different screen sizes | Verifies responsive scrolling |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Verifies light theme rendering |
| should render correctly with dark theme | Verifies dark theme rendering |

---

## 2. ProjectsScreen Tests

**File:** `test/features/projects/screens/projects_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should render with correct padding | Verifies padding |
| should render a Column layout | Verifies layout structure |

### Header Section
| Test | Description |
|------|-------------|
| should display folder icon in header | Verifies header icon |
| should display "Projects" title | Verifies header title |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |
| should have const constructor | Verifies const constructor |

### Loading State
| Test | Description |
|------|-------------|
| should show loading indicator when loading | Verifies loading state |
| should display loading message | Verifies loading message |

### Empty State
| Test | Description |
|------|-------------|
| should handle empty state gracefully | Verifies empty state handling |

### Error State
| Test | Description |
|------|-------------|
| should display error icon when error occurs | Verifies error display |

### Navigation
| Test | Description |
|------|-------------|
| should support project navigation callback | Verifies navigation |

### Resync Functionality
| Test | Description |
|------|-------------|
| should handle resync action | Verifies resync capability |

### Filter State
| Test | Description |
|------|-------------|
| should reset filters on init | Verifies filter reset |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header elements | Verifies accessibility |

---

## 3. ProjectDetailScreen Tests

**File:** `test/features/projects/screens/project_detail_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should have a header with back button | Verifies back navigation |
| should accept projectId parameter | Verifies parameter acceptance |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |
| should use projectId for provider lookup | Verifies provider usage |

### Loading State
| Test | Description |
|------|-------------|
| should show loading state initially | Verifies initial loading |
| should display loading text | Verifies loading message |

### Error State
| Test | Description |
|------|-------------|
| should handle error state gracefully | Verifies error handling |
| should show Go Back button on error | Verifies error navigation |

### Content Layout
| Test | Description |
|------|-------------|
| should have responsive layout support | Verifies responsive design |

### Languages Section
| Test | Description |
|------|-------------|
| should have Target Languages section | Verifies languages section |
| should have translate icon | Verifies translate icon |

### Add Language Button
| Test | Description |
|------|-------------|
| should have Add Language button | Verifies add button |

### Delete Functionality
| Test | Description |
|------|-------------|
| should support project deletion | Verifies project delete |
| should support language deletion | Verifies language delete |

### Navigation
| Test | Description |
|------|-------------|
| should support back navigation | Verifies back button |
| should support editor navigation | Verifies editor navigation |

### Theme Integration
| Test | Description |
|------|-------------|
| should use surfaceContainerLow background | Verifies background color |
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible back button | Verifies accessibility |

---

## 4. TranslationEditorScreen Tests

**File:** `test/features/translation_editor/screens/translation_editor_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should accept projectId and languageId parameters | Verifies parameters |
| should have header with back button | Verifies header |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Layout Structure
| Test | Description |
|------|-------------|
| should have Column as main layout | Verifies Column layout |
| should have Row for content area | Verifies Row layout |

### Header
| Test | Description |
|------|-------------|
| should display Translation Editor title | Verifies title |

### Toolbar
| Test | Description |
|------|-------------|
| should render EditorToolbar component | Verifies toolbar |

### Sidebar
| Test | Description |
|------|-------------|
| should render EditorSidebar component | Verifies sidebar |

### DataGrid
| Test | Description |
|------|-------------|
| should render EditorDataGrid component | Verifies datagrid |

### Actions
| Test | Description |
|------|-------------|
| should support translation settings action | Verifies settings action |
| should support translate all action | Verifies translate all |
| should support translate selected action | Verifies translate selected |
| should support validate action | Verifies validation |
| should support export action | Verifies export |

### Cell Editing
| Test | Description |
|------|-------------|
| should support cell edit callback | Verifies cell editing |

### Settings Initialization
| Test | Description |
|------|-------------|
| should reset skipTranslationMemory on init | Verifies TM reset |
| should clear mod update impact on init | Verifies mod impact clear |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Navigation
| Test | Description |
|------|-------------|
| should support back navigation | Verifies back button |

---

## 5. TranslationProgressScreen Tests

**File:** `test/features/translation_editor/screens/translation_progress_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should accept orchestrator parameter | Verifies orchestrator |
| should accept onComplete callback | Verifies callback |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display Translation in Progress title | Verifies title |
| should have no leading widget in header | Verifies header layout |

### Navigation Blocking
| Test | Description |
|------|-------------|
| should use PopScope to block navigation | Verifies PopScope |
| should block navigation during active translation | Verifies blocking |

### Progress Display
| Test | Description |
|------|-------------|
| should show preparation view when preparing batch | Verifies preparation view |
| should show progress body when translation is active | Verifies progress body |

### Stream Handling
| Test | Description |
|------|-------------|
| should use StreamBuilder for progress updates | Verifies streaming |

### Stop Functionality
| Test | Description |
|------|-------------|
| should support stop action | Verifies stop capability |

### Error Handling
| Test | Description |
|------|-------------|
| should display error section when error occurs | Verifies error display |

### Timer
| Test | Description |
|------|-------------|
| should track elapsed time | Verifies timer |

### Log Terminal
| Test | Description |
|------|-------------|
| should render LogTerminal component | Verifies terminal |

### Project Name
| Test | Description |
|------|-------------|
| should accept optional projectName parameter | Verifies optional param |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Lifecycle
| Test | Description |
|------|-------------|
| should mark translation as in progress on init | Verifies init state |
| should cleanup timer on dispose | Verifies cleanup |

---

## 6. ValidationReviewScreen Tests

**File:** `test/features/translation_editor/screens/validation_review_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render Scaffold as root widget | Verifies root widget |
| should accept required parameters | Verifies parameters |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Header Section
| Test | Description |
|------|-------------|
| should render ValidationReviewHeader | Verifies header |

### Toolbar Section
| Test | Description |
|------|-------------|
| should render ValidationReviewToolbar | Verifies toolbar |

### DataGrid
| Test | Description |
|------|-------------|
| should render SfDataGrid for issues | Verifies datagrid |

### Empty State
| Test | Description |
|------|-------------|
| should show empty state when no issues | Verifies empty state |

### Selection
| Test | Description |
|------|-------------|
| should support select all action | Verifies select all |
| should support deselect all action | Verifies deselect all |

### Filtering
| Test | Description |
|------|-------------|
| should support severity filter | Verifies severity filter |
| should support search filter | Verifies search filter |

### Accept/Reject Actions
| Test | Description |
|------|-------------|
| should call onAcceptTranslation callback | Verifies accept callback |
| should call onRejectTranslation callback | Verifies reject callback |

### Bulk Operations
| Test | Description |
|------|-------------|
| should support bulk accept | Verifies bulk accept |
| should support bulk reject | Verifies bulk reject |

### Edit Functionality
| Test | Description |
|------|-------------|
| should support optional onEditTranslation | Verifies edit callback |

### Export Functionality
| Test | Description |
|------|-------------|
| should support optional onExportReport | Verifies export callback |

### Close Functionality
| Test | Description |
|------|-------------|
| should support optional onClose callback | Verifies close callback |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

---

## 7. ExportProgressScreen Tests

**File:** `test/features/translation_editor/screens/export_progress_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should accept required parameters | Verifies parameters |
| should accept optional generatePackImage parameter | Verifies optional param |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display Generating Pack title | Verifies title |
| should have no leading widget in header | Verifies header layout |

### Navigation Blocking
| Test | Description |
|------|-------------|
| should use PopScope to block navigation | Verifies PopScope |
| should block navigation during export | Verifies blocking |

### Progress Display
| Test | Description |
|------|-------------|
| should display progress header | Verifies progress header |
| should display progress section | Verifies progress section |
| should display status info | Verifies status info |

### Elapsed Time
| Test | Description |
|------|-------------|
| should track elapsed time | Verifies timer |

### Log Terminal
| Test | Description |
|------|-------------|
| should render LogTerminal component | Verifies terminal |

### Error Handling
| Test | Description |
|------|-------------|
| should display error section when error occurs | Verifies error display |

### Success State
| Test | Description |
|------|-------------|
| should display success section on completion | Verifies success display |

### Close Button
| Test | Description |
|------|-------------|
| should show close button when complete | Verifies close button |
| should call onComplete callback when closing | Verifies callback |

### Step Labels
| Test | Description |
|------|-------------|
| should display correct step labels | Verifies step labels |

### Language Progress
| Test | Description |
|------|-------------|
| should display language being processed | Verifies current language |
| should display languages list in header | Verifies languages list |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Lifecycle
| Test | Description |
|------|-------------|
| should start export on init | Verifies export start |

---

## 8. GlossaryScreen Tests

**File:** `test/features/glossary/screens/glossary_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should render with Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### List View
| Test | Description |
|------|-------------|
| should show list view when no glossary is selected | Verifies list view |
| should display glossary list header | Verifies header |
| should handle loading state | Verifies loading |
| should handle error state | Verifies error |
| should handle empty state | Verifies empty state |

### Editor View
| Test | Description |
|------|-------------|
| should show editor view when glossary is selected | Verifies editor view |
| should display glossary editor header | Verifies editor header |
| should display statistics panel | Verifies statistics |
| should display editor toolbar | Verifies toolbar |
| should display data grid | Verifies datagrid |
| should display editor footer | Verifies footer |

### Dialogs
| Test | Description |
|------|-------------|
| should support new glossary dialog | Verifies new dialog |
| should support entry editor dialog | Verifies entry editor |
| should support import dialog | Verifies import dialog |
| should support export dialog | Verifies export dialog |
| should support delete confirmation dialog | Verifies delete dialog |

### Search
| Test | Description |
|------|-------------|
| should have search controller | Verifies search |

### Game Installations
| Test | Description |
|------|-------------|
| should load game installations on init | Verifies game loading |

### Lifecycle
| Test | Description |
|------|-------------|
| should dispose search controller | Verifies cleanup |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Layout
| Test | Description |
|------|-------------|
| should have statistics panel with 280 width | Verifies panel width |
| should have vertical divider between panels | Verifies divider |

---

## 9. SettingsScreen Tests

**File:** `test/features/settings/screens/settings_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should render with Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a StatefulWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display settings icon | Verifies icon |
| should display Settings title | Verifies title |
| should have correct header padding | Verifies padding |

### Tab Controller
| Test | Description |
|------|-------------|
| should use DefaultTabController with 3 tabs | Verifies controller |
| should have TabBar for navigation | Verifies TabBar |
| should have TabBarView for content | Verifies TabBarView |

### Tabs
| Test | Description |
|------|-------------|
| should display General tab | Verifies General tab |
| should display Folders tab | Verifies Folders tab |
| should display LLM Providers tab | Verifies LLM tab |
| should have correct tab icons | Verifies tab icons |

### Tab Bar Styling
| Test | Description |
|------|-------------|
| should use scrollable TabBar | Verifies scrollable |
| should have transparent divider color | Verifies divider |
| should have empty indicator | Verifies indicator |

### Tab Content
| Test | Description |
|------|-------------|
| should render GeneralSettingsTab | Verifies General content |
| should render FoldersSettingsTab | Verifies Folders content |
| should render LlmProvidersTab | Verifies LLM content |

### Fluent Tab Design
| Test | Description |
|------|-------------|
| should use custom FluentTabBar | Verifies custom TabBar |
| should use custom FluentTab with hover states | Verifies hover states |

### Border Styling
| Test | Description |
|------|-------------|
| should have border below tab bar | Verifies border |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |
| should adapt label colors based on theme brightness | Verifies adaptive colors |

### Tab Interaction
| Test | Description |
|------|-------------|
| should switch tabs on tap | Verifies tab switching |
| should have animated tab transitions | Verifies animations |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible tab labels | Verifies accessibility |
| should support keyboard navigation | Verifies keyboard nav |

---

## 10. HelpScreen Tests

**File:** `test/features/help/screens/help_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should render with Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display question circle icon | Verifies icon |
| should display Help title | Verifies title |
| should have correct header padding of 24 | Verifies padding |

### Content Loading
| Test | Description |
|------|-------------|
| should show loading indicator while loading | Verifies loading |

### Error State
| Test | Description |
|------|-------------|
| should display error icon on error | Verifies error icon |
| should display error message | Verifies error message |

### Empty State
| Test | Description |
|------|-------------|
| should display message when no documentation | Verifies empty message |

### Content Layout
| Test | Description |
|------|-------------|
| should have Row layout for content | Verifies Row layout |
| should have TOC sidebar | Verifies sidebar |
| should have vertical divider | Verifies divider |
| should have section content area | Verifies content area |

### Section Navigation
| Test | Description |
|------|-------------|
| should support section selection | Verifies selection |
| should clamp selectedIndex to valid range | Verifies clamping |
| should use ValueKey for section content | Verifies ValueKey |

### Anchor Navigation
| Test | Description |
|------|-------------|
| should support navigation to section by anchor | Verifies anchor nav |

### Divider
| Test | Description |
|------|-------------|
| should have horizontal divider below header | Verifies divider |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |
| should use theme primary color for icon | Verifies theme color |
| should use theme divider color | Verifies divider color |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header | Verifies accessibility |

---

## 11. ModsScreen Tests

**File:** `test/features/mods/screens/mods_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should have padding of 24.0 | Verifies padding |
| should have Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display cube icon | Verifies icon |
| should display Mods title | Verifies title |

### Toolbar
| Test | Description |
|------|-------------|
| should render ModsToolbar | Verifies toolbar |
| should pass search query to toolbar | Verifies search |
| should support refresh action | Verifies refresh |
| should support filter changes | Verifies filters |
| should support hidden mods toggle | Verifies toggle |
| should support import local pack | Verifies import |

### DataGrid
| Test | Description |
|------|-------------|
| should render DetectedModsDataGrid | Verifies datagrid |
| should pass filtered mods to datagrid | Verifies data passing |

### Error State
| Test | Description |
|------|-------------|
| should display error icon on error | Verifies error icon |
| should display retry button on error | Verifies retry button |

### Loading State
| Test | Description |
|------|-------------|
| should pass loading state to datagrid | Verifies loading |
| should pass refreshing state to toolbar | Verifies refreshing |

### Statistics
| Test | Description |
|------|-------------|
| should display total mods count | Verifies total count |
| should display not imported count | Verifies not imported |
| should display needs update count | Verifies needs update |
| should display hidden count | Verifies hidden |
| should display pending projects count | Verifies pending |

### Row Actions
| Test | Description |
|------|-------------|
| should support row tap for project creation | Verifies row tap |
| should support toggle hidden action | Verifies toggle hidden |
| should support force redownload action | Verifies redownload |

### Navigation
| Test | Description |
|------|-------------|
| should support navigation to projects with filter | Verifies nav to projects |
| should support project detail navigation | Verifies nav to detail |

### Project Creation
| Test | Description |
|------|-------------|
| should support direct project creation | Verifies direct creation |
| should show initialization dialog | Verifies init dialog |

### Local Pack Import
| Test | Description |
|------|-------------|
| should support local pack import | Verifies import |
| should show local pack warning dialog | Verifies warning |
| should show project name dialog for local packs | Verifies name dialog |

### Refresh
| Test | Description |
|------|-------------|
| should support manual refresh | Verifies refresh |
| should invalidate providers on refresh | Verifies invalidation |

### Scan Log
| Test | Description |
|------|-------------|
| should pass scan log stream to datagrid | Verifies scan log |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header | Verifies accessibility |

---

## 12. GameTranslationScreen Tests

**File:** `test/features/game_translation/screens/game_translation_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should have padding of 24.0 | Verifies padding |
| should have Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display globe icon | Verifies icon |
| should display Game Translation title | Verifies title |

### Loading State
| Test | Description |
|------|-------------|
| should show loading indicator | Verifies loading |
| should display loading message | Verifies message |

### Error State
| Test | Description |
|------|-------------|
| should display error icon | Verifies error icon |
| should display error message | Verifies error message |

### Empty State
| Test | Description |
|------|-------------|
| should display empty state message | Verifies empty message |
| should display create button in empty state | Verifies create button |
| should display warning when no packs available | Verifies warning |

### Projects Grid
| Test | Description |
|------|-------------|
| should render ProjectGrid when projects exist | Verifies grid |
| should pass projects to grid | Verifies data passing |

### Create Dialog
| Test | Description |
|------|-------------|
| should show CreateGameTranslationDialog | Verifies dialog |
| should not be dismissible | Verifies modal behavior |

### Navigation
| Test | Description |
|------|-------------|
| should support project navigation | Verifies navigation |
| should navigate to project detail | Verifies detail nav |

### Local Packs Check
| Test | Description |
|------|-------------|
| should check for local packs availability | Verifies packs check |
| should disable create when no packs | Verifies disable state |

### Filtering
| Test | Description |
|------|-------------|
| should filter for game translation projects | Verifies filtering |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |
| should use theme colors | Verifies colors |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header | Verifies accessibility |
| should have accessible warning icon | Verifies warning icon |

---

## 13. PackCompilationScreen Tests

**File:** `test/features/pack_compilation/screens/pack_compilation_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should have padding of 24.0 | Verifies padding |
| should have Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |
| should manage _showEditor state | Verifies state |

### Header
| Test | Description |
|------|-------------|
| should display box multiple icon | Verifies icon |
| should display Pack Compilations title | Verifies title |
| should display New Compilation button | Verifies button |

### List View
| Test | Description |
|------|-------------|
| should display list view by default | Verifies default view |
| should render CompilationList widget | Verifies list widget |

### Editor View
| Test | Description |
|------|-------------|
| should show editor when creating new | Verifies editor show |
| should show back button in editor view | Verifies back button |
| should render CompilationEditor widget | Verifies editor widget |

### Navigation Blocking
| Test | Description |
|------|-------------|
| should block navigation during compilation | Verifies blocking |
| should disable back button during compilation | Verifies disable |
| should show tooltip when navigation blocked | Verifies tooltip |

### Create Button
| Test | Description |
|------|-------------|
| should render _CreateButton widget | Verifies button widget |
| should have tooltip | Verifies tooltip |
| should have add icon | Verifies icon |
| should have hover animation | Verifies animation |

### Editor Header
| Test | Description |
|------|-------------|
| should display New Compilation title for new | Verifies new title |
| should display compilation name when editing | Verifies edit title |

### Cancel and Save
| Test | Description |
|------|-------------|
| should support cancel action | Verifies cancel |
| should hide editor on save | Verifies hide |
| should invalidate provider on save | Verifies invalidation |

### Edit Compilation
| Test | Description |
|------|-------------|
| should load compilation for editing | Verifies load |
| should reset editor state on hide | Verifies reset |

### Background Color
| Test | Description |
|------|-------------|
| should use surfaceContainerLow for editor view | Verifies background |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header | Verifies accessibility |
| should have accessible back button | Verifies back button |

---

## 14. TranslationMemoryScreen Tests

**File:** `test/features/translation_memory/screens/translation_memory_screen_test.dart`

### Widget Structure
| Test | Description |
|------|-------------|
| should render FluentScaffold as root widget | Verifies root widget |
| should have Column layout | Verifies layout |
| should have const constructor | Verifies constructor |

### State Management
| Test | Description |
|------|-------------|
| should be a ConsumerStatefulWidget | Verifies widget type |

### Header
| Test | Description |
|------|-------------|
| should display database icon | Verifies icon |
| should display Translation Memory title | Verifies title |
| should have header padding of 24.0 | Verifies padding |

### Action Buttons
| Test | Description |
|------|-------------|
| should display Import button | Verifies Import |
| should display Export button | Verifies Export |
| should display Cleanup button | Verifies Cleanup |
| should have import icon | Verifies import icon |
| should have export icon | Verifies export icon |
| should have broom icon for cleanup | Verifies broom icon |
| should have tooltips on buttons | Verifies tooltips |

### Main Layout
| Test | Description |
|------|-------------|
| should have Row layout for content | Verifies Row |
| should have divider between header and content | Verifies divider |

### Statistics Panel
| Test | Description |
|------|-------------|
| should render TmStatisticsPanel | Verifies panel |
| should have fixed width of 280 | Verifies width |

### Toolbar
| Test | Description |
|------|-------------|
| should render TmSearchBar | Verifies search bar |
| should display Refresh button | Verifies Refresh |
| should have refresh icon | Verifies icon |
| should have toolbar padding of 16.0 | Verifies padding |

### DataGrid
| Test | Description |
|------|-------------|
| should render TmBrowserDataGrid | Verifies datagrid |

### Pagination
| Test | Description |
|------|-------------|
| should render TmPaginationBar | Verifies pagination |

### Dialogs
| Test | Description |
|------|-------------|
| should show import dialog on Import tap | Verifies import dialog |
| should show export dialog on Export tap | Verifies export dialog |
| should show cleanup dialog on Cleanup tap | Verifies cleanup dialog |

### Refresh Action
| Test | Description |
|------|-------------|
| should invalidate providers on refresh | Verifies invalidation |

### Vertical Divider
| Test | Description |
|------|-------------|
| should have vertical divider between panels | Verifies divider |

### Theme Integration
| Test | Description |
|------|-------------|
| should render correctly with light theme | Light theme test |
| should render correctly with dark theme | Dark theme test |
| should use theme primary color for icon | Verifies color |

### Accessibility
| Test | Description |
|------|-------------|
| should have accessible header | Verifies header |
| should have accessible action buttons | Verifies buttons |

---

## Test Summary Statistics

| Screen | Test Groups | Total Tests |
|--------|-------------|-------------|
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
| **TOTAL** | **160** | **263** |

---

## Running Tests

### Run all tests
```bash
flutter test
```

### Run tests for a specific screen
```bash
flutter test test/features/home/screens/home_screen_test.dart
```

### Run tests with coverage
```bash
flutter test --coverage
```

### Run tests in verbose mode
```bash
flutter test --reporter expanded
```

---

## Test Helpers

### test_helpers.dart

Provides utility functions for creating testable widgets:

- `createTestableWidget(Widget child, {List<Override>? overrides})` - Wraps widget with ProviderScope and MaterialApp
- `createTestableWidgetWithScaffold(Widget child, {List<Override>? overrides})` - Wraps widget with Scaffold
- `createThemedTestableWidget(Widget child, {List<Override>? overrides, ThemeData? theme})` - Wraps widget with custom theme
- `pumpAndSettle(WidgetTester tester)` - Pumps and settles animations
- `findByKey(String key)` - Finds widget by key
- `findByTextContaining(String text)` - Finds widget containing text

### mock_providers.dart

Provides mock model factories:

- `createMockProject(...)` - Creates a mock Project
- `createMockLanguage(...)` - Creates a mock Language
- `createMockDetectedMod(...)` - Creates a mock DetectedMod
- `createMockGameInstallation(...)` - Creates a mock GameInstallation
- `createMockGlossary(...)` - Creates a mock Glossary
- `createMockProjectList({int count})` - Creates list of mock Projects
- `createMockLanguageList()` - Creates list of mock Languages
- `createMockDetectedModList({int count})` - Creates list of mock DetectedMods
- `createMockGlossaryList({int count})` - Creates list of mock Glossaries
