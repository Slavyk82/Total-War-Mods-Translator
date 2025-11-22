import 'package:json_annotation/json_annotation.dart';
import '../../../services/search/models/search_result.dart';

part 'search_query_model.g.dart';

/// Scope for search query (which fields to search)
enum SearchScope {
  /// Search in source text only
  source,

  /// Search in target/translated text only
  target,

  /// Search in both source and target
  both,

  /// Search in translation key only
  key,

  /// Search in all fields
  all;

  String get displayName {
    switch (this) {
      case SearchScope.source:
        return 'Source Text';
      case SearchScope.target:
        return 'Target Text';
      case SearchScope.both:
        return 'Source & Target';
      case SearchScope.key:
        return 'Translation Key';
      case SearchScope.all:
        return 'All Fields';
    }
  }
}

/// Search operator for combining terms
enum SearchOperator {
  /// All terms must be present (AND)
  and,

  /// Any term can be present (OR)
  or,

  /// Exclude term (NOT)
  not;

  String get displayName {
    switch (this) {
      case SearchOperator.and:
        return 'AND (all terms)';
      case SearchOperator.or:
        return 'OR (any term)';
      case SearchOperator.not:
        return 'NOT (exclude)';
    }
  }

  String get ftsOperator {
    switch (this) {
      case SearchOperator.and:
        return 'AND';
      case SearchOperator.or:
        return 'OR';
      case SearchOperator.not:
        return 'NOT';
    }
  }
}

/// Search options (case-sensitive, whole word, regex, etc.)
@JsonSerializable()
class SearchOptions {
  /// Case-sensitive search
  final bool caseSensitive;

  /// Whole word match only
  final bool wholeWord;

  /// Use regular expression
  final bool useRegex;

  /// Use phrase search (exact phrase)
  final bool phraseSearch;

  /// Use prefix search (wildcard at end)
  final bool prefixSearch;

  /// Include obsolete entries
  final bool includeObsolete;

  /// Results per page
  final int resultsPerPage;

  const SearchOptions({
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
    this.phraseSearch = false,
    this.prefixSearch = false,
    this.includeObsolete = false,
    this.resultsPerPage = 50,
  });

  factory SearchOptions.defaults() => const SearchOptions();

  factory SearchOptions.fromJson(Map<String, dynamic> json) =>
      _$SearchOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$SearchOptionsToJson(this);

  SearchOptions copyWith({
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
    bool? phraseSearch,
    bool? prefixSearch,
    bool? includeObsolete,
    int? resultsPerPage,
  }) {
    return SearchOptions(
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      useRegex: useRegex ?? this.useRegex,
      phraseSearch: phraseSearch ?? this.phraseSearch,
      prefixSearch: prefixSearch ?? this.prefixSearch,
      includeObsolete: includeObsolete ?? this.includeObsolete,
      resultsPerPage: resultsPerPage ?? this.resultsPerPage,
    );
  }
}

/// Complete search query model
@JsonSerializable()
class SearchQueryModel {
  /// Search text query
  final String text;

  /// Search scope (source, target, both, etc.)
  final SearchScope scope;

  /// Search operator (AND, OR, NOT)
  final SearchOperator operator;

  /// Search filters
  final SearchFilter? filter;

  /// Search options
  final SearchOptions options;

  const SearchQueryModel({
    required this.text,
    required this.scope,
    required this.operator,
    this.filter,
    required this.options,
  });

  factory SearchQueryModel.empty() => SearchQueryModel(
        text: '',
        scope: SearchScope.all,
        operator: SearchOperator.and,
        filter: null,
        options: SearchOptions.defaults(),
      );

  factory SearchQueryModel.fromJson(Map<String, dynamic> json) =>
      _$SearchQueryModelFromJson(json);

  Map<String, dynamic> toJson() => _$SearchQueryModelToJson(this);

  SearchQueryModel copyWith({
    String? text,
    SearchScope? scope,
    SearchOperator? operator,
    SearchFilter? filter,
    SearchOptions? options,
  }) {
    return SearchQueryModel(
      text: text ?? this.text,
      scope: scope ?? this.scope,
      operator: operator ?? this.operator,
      filter: filter ?? this.filter,
      options: options ?? this.options,
    );
  }

  /// Check if query is valid (has text)
  bool get isValid => text.trim().length >= 2;

  /// Get a summary string of the query
  String get summary {
    final parts = <String>[];
    parts.add('"$text"');
    if (scope != SearchScope.all) {
      parts.add('in ${scope.displayName}');
    }
    if (filter != null && !filter!.isEmpty) {
      final filterParts = <String>[];
      if (filter!.projectIds != null && filter!.projectIds!.isNotEmpty) {
        filterParts.add('${filter!.projectIds!.length} project(s)');
      }
      if (filter!.languageCodes != null && filter!.languageCodes!.isNotEmpty) {
        filterParts.add('${filter!.languageCodes!.length} language(s)');
      }
      if (filter!.statuses != null && filter!.statuses!.isNotEmpty) {
        filterParts.add('status=${filter!.statuses!.join(", ")}');
      }
      if (filterParts.isNotEmpty) {
        parts.add('(${filterParts.join(", ")})');
      }
    }
    return parts.join(' ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQueryModel &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          scope == other.scope &&
          operator == other.operator &&
          filter == other.filter &&
          options == other.options;

  @override
  int get hashCode =>
      text.hashCode ^
      scope.hashCode ^
      operator.hashCode ^
      filter.hashCode ^
      options.hashCode;

  @override
  String toString() {
    return 'SearchQueryModel(text: $text, scope: $scope, operator: $operator)';
  }
}

/// Search results with metadata
@JsonSerializable()
class SearchResultsModel {
  /// List of search results
  final List<SearchResult> results;

  /// Total count of results (before pagination)
  final int totalCount;

  /// Current page number (1-indexed)
  final int currentPage;

  /// Results per page
  final int pageSize;

  /// Original query
  final SearchQueryModel query;

  const SearchResultsModel({
    required this.results,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.query,
  });

  factory SearchResultsModel.empty() => SearchResultsModel(
        results: const [],
        totalCount: 0,
        currentPage: 1,
        pageSize: 50,
        query: SearchQueryModel.empty(),
      );

  factory SearchResultsModel.fromJson(Map<String, dynamic> json) =>
      _$SearchResultsModelFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultsModelToJson(this);

  /// Total number of pages
  int get totalPages => (totalCount / pageSize).ceil();

  /// Has previous page
  bool get hasPreviousPage => currentPage > 1;

  /// Has next page
  bool get hasNextPage => currentPage < totalPages;

  /// Get range text (e.g., "1-50 of 234")
  String get rangeText {
    if (totalCount == 0) return '0 results';
    final start = (currentPage - 1) * pageSize + 1;
    final end = (currentPage * pageSize).clamp(0, totalCount);
    return '$start-$end of $totalCount';
  }

  SearchResultsModel copyWith({
    List<SearchResult>? results,
    int? totalCount,
    int? currentPage,
    int? pageSize,
    SearchQueryModel? query,
  }) {
    return SearchResultsModel(
      results: results ?? this.results,
      totalCount: totalCount ?? this.totalCount,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      query: query ?? this.query,
    );
  }
}
