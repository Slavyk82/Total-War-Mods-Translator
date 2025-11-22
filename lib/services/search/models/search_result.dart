import 'package:json_annotation/json_annotation.dart';

part 'search_result.g.dart';

/// Type of search result
enum SearchResultType {
  /// Translation unit (source text)
  translationUnit,

  /// Translation version (translated text)
  translationVersion,

  /// Translation memory entry
  translationMemory,

  /// Glossary entry
  glossaryEntry,
}

/// Represents a search result from FTS5 full-text search
///
/// Contains the matched entity, relevance score, highlights, and context
@JsonSerializable()
class SearchResult {
  /// Unique identifier of the matched entity
  final String id;

  /// Type of search result
  final SearchResultType type;

  /// Project ID (if applicable)
  final String? projectId;

  /// Project name (if applicable)
  final String? projectName;

  /// Language code (if applicable - for translation versions)
  final String? languageCode;

  /// Language name (if applicable)
  final String? languageName;

  /// Translation unit key (if applicable)
  final String? key;

  /// Source text content
  final String? sourceText;

  /// Translated text content (if applicable)
  final String? translatedText;

  /// Field where the match was found (e.g., "key", "source_text", "translated_text")
  final String matchedField;

  /// Highlighted match with <mark> tags
  final String highlightedText;

  /// Relevance rank score from FTS5 (higher = more relevant)
  final double relevanceScore;

  /// Additional context around the match
  final String? context;

  /// File name (if applicable)
  final String? fileName;

  /// Category (for glossary entries)
  final String? category;

  /// Translation status (if applicable)
  final String? status;

  /// Creation timestamp
  final DateTime? createdAt;

  /// Last update timestamp
  final DateTime? updatedAt;

  const SearchResult({
    required this.id,
    required this.type,
    this.projectId,
    this.projectName,
    this.languageCode,
    this.languageName,
    this.key,
    this.sourceText,
    this.translatedText,
    required this.matchedField,
    required this.highlightedText,
    required this.relevanceScore,
    this.context,
    this.fileName,
    this.category,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  /// JSON serialization
  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$SearchResultToJson(this);

  /// Create copy with updated fields
  SearchResult copyWith({
    String? id,
    SearchResultType? type,
    String? projectId,
    String? projectName,
    String? languageCode,
    String? languageName,
    String? key,
    String? sourceText,
    String? translatedText,
    String? matchedField,
    String? highlightedText,
    double? relevanceScore,
    String? context,
    String? fileName,
    String? category,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SearchResult(
      id: id ?? this.id,
      type: type ?? this.type,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      languageCode: languageCode ?? this.languageCode,
      languageName: languageName ?? this.languageName,
      key: key ?? this.key,
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      matchedField: matchedField ?? this.matchedField,
      highlightedText: highlightedText ?? this.highlightedText,
      relevanceScore: relevanceScore ?? this.relevanceScore,
      context: context ?? this.context,
      fileName: fileName ?? this.fileName,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          projectId == other.projectId &&
          projectName == other.projectName &&
          languageCode == other.languageCode &&
          languageName == other.languageName &&
          key == other.key &&
          sourceText == other.sourceText &&
          translatedText == other.translatedText &&
          matchedField == other.matchedField &&
          highlightedText == other.highlightedText &&
          relevanceScore == other.relevanceScore &&
          context == other.context &&
          fileName == other.fileName &&
          category == other.category &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      type.hashCode ^
      projectId.hashCode ^
      projectName.hashCode ^
      languageCode.hashCode ^
      languageName.hashCode ^
      key.hashCode ^
      sourceText.hashCode ^
      translatedText.hashCode ^
      matchedField.hashCode ^
      highlightedText.hashCode ^
      relevanceScore.hashCode ^
      context.hashCode ^
      fileName.hashCode ^
      category.hashCode ^
      status.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'SearchResult(id: $id, type: $type, matchedField: $matchedField, '
        'relevanceScore: $relevanceScore, key: $key, projectName: $projectName, '
        'languageName: $languageName)';
  }
}

/// Search filter configuration
@JsonSerializable()
class SearchFilter {
  /// Filter by project IDs
  final List<String>? projectIds;

  /// Filter by language codes
  final List<String>? languageCodes;

  /// Filter by translation status
  final List<String>? statuses;

  /// Filter by file names
  final List<String>? fileNames;

  /// Filter by result types
  final List<SearchResultType>? types;

  /// Filter by date range (created_at >= minDate)
  final DateTime? minDate;

  /// Filter by date range (created_at <= maxDate)
  final DateTime? maxDate;

  /// Filter by minimum relevance score
  final double? minRelevanceScore;

  const SearchFilter({
    this.projectIds,
    this.languageCodes,
    this.statuses,
    this.fileNames,
    this.types,
    this.minDate,
    this.maxDate,
    this.minRelevanceScore,
  });

  /// JSON serialization
  factory SearchFilter.fromJson(Map<String, dynamic> json) =>
      _$SearchFilterFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$SearchFilterToJson(this);

  /// Check if filter is empty (no filters applied)
  bool get isEmpty =>
      projectIds == null &&
      languageCodes == null &&
      statuses == null &&
      fileNames == null &&
      types == null &&
      minDate == null &&
      maxDate == null &&
      minRelevanceScore == null;

  /// Create copy with updated fields
  SearchFilter copyWith({
    List<String>? projectIds,
    List<String>? languageCodes,
    List<String>? statuses,
    List<String>? fileNames,
    List<SearchResultType>? types,
    DateTime? minDate,
    DateTime? maxDate,
    double? minRelevanceScore,
  }) {
    return SearchFilter(
      projectIds: projectIds ?? this.projectIds,
      languageCodes: languageCodes ?? this.languageCodes,
      statuses: statuses ?? this.statuses,
      fileNames: fileNames ?? this.fileNames,
      types: types ?? this.types,
      minDate: minDate ?? this.minDate,
      maxDate: maxDate ?? this.maxDate,
      minRelevanceScore: minRelevanceScore ?? this.minRelevanceScore,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchFilter &&
          runtimeType == other.runtimeType &&
          projectIds == other.projectIds &&
          languageCodes == other.languageCodes &&
          statuses == other.statuses &&
          fileNames == other.fileNames &&
          types == other.types &&
          minDate == other.minDate &&
          maxDate == other.maxDate &&
          minRelevanceScore == other.minRelevanceScore;

  @override
  int get hashCode =>
      projectIds.hashCode ^
      languageCodes.hashCode ^
      statuses.hashCode ^
      fileNames.hashCode ^
      types.hashCode ^
      minDate.hashCode ^
      maxDate.hashCode ^
      minRelevanceScore.hashCode;

  @override
  String toString() {
    return 'SearchFilter(projectIds: $projectIds, languageCodes: $languageCodes, '
        'statuses: $statuses, types: $types, minRelevanceScore: $minRelevanceScore)';
  }
}

/// Saved search query
@JsonSerializable()
class SavedSearch {
  /// Unique identifier
  final String id;

  /// Search name
  final String name;

  /// Search query
  final String query;

  /// Search filter
  final SearchFilter? filter;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last used timestamp
  final DateTime? lastUsedAt;

  /// Usage count
  final int usageCount;

  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
    this.filter,
    required this.createdAt,
    this.lastUsedAt,
    this.usageCount = 0,
  });

  /// JSON serialization
  factory SavedSearch.fromJson(Map<String, dynamic> json) =>
      _$SavedSearchFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$SavedSearchToJson(this);

  /// Create copy with updated fields
  SavedSearch copyWith({
    String? id,
    String? name,
    String? query,
    SearchFilter? filter,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    int? usageCount,
  }) {
    return SavedSearch(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSearch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          query == other.query &&
          filter == other.filter &&
          createdAt == other.createdAt &&
          lastUsedAt == other.lastUsedAt &&
          usageCount == other.usageCount;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      query.hashCode ^
      filter.hashCode ^
      createdAt.hashCode ^
      lastUsedAt.hashCode ^
      usageCount.hashCode;

  @override
  String toString() {
    return 'SavedSearch(id: $id, name: $name, query: $query, usageCount: $usageCount)';
  }
}
