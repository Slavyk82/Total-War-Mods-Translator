# Advanced Search UI - Phase 3.4

## Overview

Complete Advanced Search UI implementation for TWMT with FTS5 full-text search backend.

**Status**: ✅ Production-Ready

## Features

- **Advanced Search Dialog**: Large, resizable dialog (800x600px) with full query builder
- **Query Builder**: FTS5 query syntax with operators (AND, OR, NOT, phrase, prefix)
- **Search Results Panel**: Paginated results with highlighting and navigation
- **Saved Searches**: Save frequently used searches with usage statistics
- **Search History**: Auto-saved last 50 searches
- **Filters**: Status, project, language, file, date range
- **Highlighting**: Bold text with color highlighting for matched terms

## Architecture

```
lib/features/search/
├── models/
│   ├── search_query_model.dart         # Query, scope, operator, options
│   └── search_query_model.g.dart       # Generated JSON serialization
├── providers/
│   ├── search_providers.dart           # Riverpod state management
│   └── search_providers.g.dart         # Generated Riverpod code
└── widgets/
    ├── advanced_search_dialog.dart     # Main search dialog
    ├── search_query_builder.dart       # Query builder widget
    ├── search_results_panel.dart       # Results display with pagination
    └── saved_searches_panel.dart       # Saved searches management
```

## Usage

### 1. Show Advanced Search Dialog

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/search/widgets/advanced_search_dialog.dart';

// In your widget
final result = await showDialog(
  context: context,
  builder: (context) => const AdvancedSearchDialog(),
);

if (result == true) {
  // User clicked Search button
  // Search results are automatically updated in searchResultsProvider
}
```

### 2. Display Search Results

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/search/widgets/search_results_panel.dart';
import 'package:twmt/services/search/models/search_result.dart';

class MySearchResultsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchResultsPanel(
      standalone: true,
      onNavigate: (SearchResult result) {
        // Navigate to translation editor with this entry
        print('Navigate to: ${result.key}');
      },
    );
  }
}
```

### 3. Manage Saved Searches

```dart
import 'package:flutter/material.dart';
import 'package:twmt/features/search/widgets/saved_searches_panel.dart';

// Show saved searches dialog
await showDialog(
  context: context,
  builder: (context) => const SavedSearchesPanel(asDialog: true),
);

// Or embed in screen
const SavedSearchesPanel(asDialog: false);
```

### 4. Programmatic Search

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/search/models/search_query_model.dart';
import 'package:twmt/features/search/providers/search_providers.dart';
import 'package:twmt/services/search/models/search_result.dart';

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        // Set search query
        final notifier = ref.read(searchQueryProvider.notifier);
        notifier.updateText('emperor');
        notifier.updateScope(SearchScope.source);

        // Apply filters
        notifier.updateFilter(SearchFilter(
          statuses: ['translated'],
          projectIds: ['project123'],
        ));

        // Results will be available in searchResultsProvider
      },
      child: Text('Search for "emperor"'),
    );
  }
}
```

## Models

### SearchQueryModel

```dart
final query = SearchQueryModel(
  text: 'emperor',
  scope: SearchScope.source,
  operator: SearchOperator.and,
  filter: SearchFilter(
    statuses: ['translated'],
    projectIds: ['proj123'],
  ),
  options: SearchOptions(
    caseSensitive: false,
    phraseSearch: false,
    prefixSearch: false,
    resultsPerPage: 50,
  ),
);
```

### SearchScope

- `source`: Search in source text only
- `target`: Search in target/translated text only
- `both`: Search in both source and target
- `key`: Search in translation key only
- `all`: Search in all fields

### SearchOperator

- `and`: All terms must be present (AND)
- `or`: Any term can be present (OR)
- `not`: Exclude term (NOT)

### SearchOptions

- `caseSensitive`: Case-sensitive search
- `wholeWord`: Whole word match only
- `useRegex`: Use regular expression (slower)
- `phraseSearch`: Wrap in quotes for exact phrase
- `prefixSearch`: Append * for prefix matching
- `includeObsolete`: Include obsolete entries
- `resultsPerPage`: 25, 50, 100, or 200

## Providers

### searchQueryProvider

Current search query state.

```dart
final query = ref.watch(searchQueryProvider);
ref.read(searchQueryProvider.notifier).updateText('cavalry');
```

### searchResultsProvider(page: int)

Execute search and get paginated results.

```dart
final resultsAsync = ref.watch(searchResultsProvider(page: 1));

resultsAsync.when(
  data: (results) {
    // SearchResultsModel with results, totalCount, pagination
  },
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => Text('Error: $error'),
);
```

### savedSearchesProvider

List of saved searches.

```dart
final savedSearchesAsync = ref.watch(savedSearchesProvider);
```

### searchHistoryProvider

Last 50 searches.

```dart
final historyAsync = ref.watch(searchHistoryProvider);
```

### saveSearchActionProvider

Save current search.

```dart
final action = ref.read(saveSearchActionProvider.notifier);
await action.save('My Search', query);
```

### deleteSearchActionProvider

Delete saved search.

```dart
final action = ref.read(deleteSearchActionProvider.notifier);
await action.delete(searchId);
```

### executeSavedSearchActionProvider

Execute saved search.

```dart
final action = ref.read(executeSavedSearchActionProvider.notifier);
await action.execute(savedSearch);
```

## FTS5 Query Syntax

The search backend uses SQLite FTS5 for blazing-fast full-text search.

### Operators

- `term1 AND term2`: Both terms must be present
- `term1 OR term2`: Either term can be present
- `term1 NOT term2`: First term present, second excluded
- `"exact phrase"`: Exact phrase match
- `prefix*`: Prefix search (matches prefixing, prefixes, etc.)
- `term1 NEAR/5 term2`: Terms within 5 tokens of each other

### Examples

```
emperor
emperor AND faction
"total war" OR "warhammer"
cavalry NOT horse
emper*
"ancient empire" NEAR/10 faction
```

## Highlighting

Search results display matched terms with:
- **Bold text**
- Primary color
- Background highlight (10% opacity)

Highlighting uses FTS5's `snippet()` function with `<mark>` tags, parsed to TextSpan.

## Performance

- **FTS5 Search**: 100-1000x faster than LIKE queries
- **Pagination**: 25-200 results per page
- **Caching**: Recent searches cached in memory
- **Debouncing**: 300ms delay on text input (recommended)

## Integration with Translation Editor

The search UI is designed to work standalone or embedded in the Translation Editor (Phase 4).

```dart
// In Translation Editor
SearchResultsPanel(
  standalone: false,
  onNavigate: (result) {
    // Navigate to translation unit in editor
    loadTranslationUnit(result.id);
  },
);
```

## Backend Services

Uses existing production-ready services:

- `ISearchService`: Full-text search operations
- `SearchServiceImpl`: FTS5 implementation
- `FtsQueryBuilder`: Query syntax builder

## Database Tables

All FTS5 tables ready:

- `translation_units_fts`: Source text and keys
- `translation_versions_fts`: Translated text
- `translation_memory_fts`: TM entries
- `search_history`: Last 100 searches
- `saved_searches`: User-saved searches

## Testing

### Manual Testing

1. Open Advanced Search Dialog
2. Enter query: "emperor"
3. Select scope: Source
4. Add filters: Status = Translated
5. Click Search
6. Verify results display with highlighting
7. Click "Go to" on a result
8. Save search as "Emperor Searches"
9. Re-run from Saved Searches panel

### Unit Testing

```dart
testWidgets('Search dialog opens and accepts input', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: AdvancedSearchDialog(),
      ),
    ),
  );

  // Enter search query
  await tester.enterText(find.byType(TextFormField), 'emperor');

  // Click search button
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();

  // Verify dialog closed
  expect(find.byType(AdvancedSearchDialog), findsNothing);
});
```

## Known Limitations

1. **Export**: CSV/Excel export not yet implemented (placeholder)
2. **Total Count**: Pagination shows results count, not total database count (requires COUNT query)
3. **Regex Validation**: Basic validation only, may not catch all invalid patterns

## Future Enhancements

1. **Smart Suggestions**: Auto-complete search terms from glossary
2. **Search Templates**: Pre-defined search templates for common tasks
3. **Batch Operations**: Select multiple results for batch actions
4. **Export Formats**: CSV, Excel, TMX export
5. **Search Analytics**: Most searched terms, popular filters

## Dependencies

- `flutter_riverpod`: ^3.0.3
- `riverpod_annotation`: ^3.0.3
- `json_annotation`: ^4.9.0
- `fluentui_system_icons`: ^1.1.273
- `timeago`: ^3.7.0

## Code Generation

After modifying models or providers, run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## License

Part of TWMT (Total War Mod Translator) application.
