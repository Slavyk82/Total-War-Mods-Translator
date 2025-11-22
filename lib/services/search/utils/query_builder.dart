import '../models/search_result.dart';

/// Utility class for building FTS5 queries with filters and operators
///
/// Handles FTS5 syntax, escaping, operator conversion, and filter application.
class FtsQueryBuilder {
  /// Build a full FTS5 query from base query string
  ///
  /// Converts user query into FTS5 MATCH query with proper escaping.
  ///
  /// Supported operators:
  /// - AND: "cavalry AND unit" → matches both terms
  /// - OR: "cavalry OR infantry" → matches either term
  /// - NOT: "cavalry NOT horse" → matches cavalry but not horse
  /// - Phrase: "\"cavalry unit\"" → exact phrase match
  /// - Prefix: "caval*" → matches cavalry, cavalier, etc.
  /// - NEAR: "cavalry NEAR/5 unit" → terms within 5 tokens
  ///
  /// Parameters:
  /// - [query]: User search query
  /// - [searchColumns]: Columns to search in (default: all)
  ///
  /// Returns: FTS5-compatible MATCH query
  ///
  /// Example:
  /// ```dart
  /// final q = FtsQueryBuilder.buildFtsQuery('cavalry unit');
  /// // Returns: 'cavalry AND unit'
  ///
  /// final q2 = FtsQueryBuilder.buildFtsQuery('"exact phrase"');
  /// // Returns: '"exact phrase"'
  /// ```
  static String buildFtsQuery(String query, {List<String>? searchColumns}) {
    if (query.isEmpty) {
      return '';
    }

    // If query already contains FTS5 operators, validate and return
    if (_containsFtsOperators(query)) {
      return _sanitizeFtsQuery(query);
    }

    // Parse and build FTS5 query from natural language
    return _buildNaturalLanguageQuery(query, searchColumns: searchColumns);
  }

  /// Build WHERE clause for filters
  ///
  /// Generates SQL WHERE conditions based on SearchFilter.
  ///
  /// Parameters:
  /// - [filter]: Search filter configuration
  /// - [tableAlias]: Table alias for column references (default: 't')
  ///
  /// Returns: SQL WHERE clause (without 'WHERE' keyword) or empty string
  static String buildFilterClause(
    SearchFilter? filter, {
    String tableAlias = 't',
  }) {
    if (filter == null || filter.isEmpty) {
      return '';
    }

    final conditions = <String>[];

    // Filter by project IDs
    if (filter.projectIds != null && filter.projectIds!.isNotEmpty) {
      final placeholders =
          filter.projectIds!.map((id) => "'${_escape(id)}'").join(', ');
      conditions.add('$tableAlias.project_id IN ($placeholders)');
    }

    // Filter by language codes
    if (filter.languageCodes != null && filter.languageCodes!.isNotEmpty) {
      final placeholders =
          filter.languageCodes!.map((code) => "'${_escape(code)}'").join(', ');
      conditions.add('$tableAlias.language_code IN ($placeholders)');
    }

    // Filter by statuses
    if (filter.statuses != null && filter.statuses!.isNotEmpty) {
      final placeholders =
          filter.statuses!.map((s) => "'${_escape(s)}'").join(', ');
      conditions.add('$tableAlias.status IN ($placeholders)');
    }

    // Filter by file names
    if (filter.fileNames != null && filter.fileNames!.isNotEmpty) {
      final placeholders =
          filter.fileNames!.map((f) => "'${_escape(f)}'").join(', ');
      conditions.add('$tableAlias.file_name IN ($placeholders)');
    }

    // Filter by date range (min date)
    if (filter.minDate != null) {
      final timestamp = filter.minDate!.millisecondsSinceEpoch;
      conditions.add('$tableAlias.created_at >= $timestamp');
    }

    // Filter by date range (max date)
    if (filter.maxDate != null) {
      final timestamp = filter.maxDate!.millisecondsSinceEpoch;
      conditions.add('$tableAlias.created_at <= $timestamp');
    }

    // Filter by minimum relevance score (for FTS5 results)
    if (filter.minRelevanceScore != null) {
      conditions.add('rank >= ${filter.minRelevanceScore}');
    }

    return conditions.join(' AND ');
  }

  /// Build ORDER BY clause for ranking results
  ///
  /// Parameters:
  /// - [orderBy]: Sort field (default: 'rank' for FTS5 relevance)
  /// - [ascending]: Sort direction (default: false for relevance)
  ///
  /// Returns: SQL ORDER BY clause (without 'ORDER BY' keyword)
  static String buildOrderClause({
    String orderBy = 'rank',
    bool ascending = false,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    return '$orderBy $direction';
  }

  /// Build LIMIT/OFFSET clause for pagination
  ///
  /// Parameters:
  /// - [limit]: Maximum number of results (max: 1000)
  /// - [offset]: Offset for pagination (default: 0)
  ///
  /// Returns: SQL LIMIT/OFFSET clause
  static String buildLimitClause({required int limit, int offset = 0}) {
    final safeLimit = limit.clamp(1, 1000);
    final safeOffset = offset.clamp(0, 1000000);

    if (safeOffset > 0) {
      return 'LIMIT $safeLimit OFFSET $safeOffset';
    }
    return 'LIMIT $safeLimit';
  }

  /// Generate highlight snippet with <mark> tags
  ///
  /// Uses FTS5 snippet() function to generate highlighted text.
  ///
  /// Parameters:
  /// - [tableName]: FTS5 virtual table name
  /// - [column]: Column to highlight
  /// - [startMark]: Start marker (default: '<mark>')
  /// - [endMark]: End marker (default: '</mark>')
  /// - [ellipsis]: Ellipsis for truncated text (default: '...')
  /// - [tokens]: Number of tokens to include (default: 10)
  ///
  /// Returns: SQL snippet() function call
  static String buildSnippet({
    required String tableName,
    required int column,
    String startMark = '<mark>',
    String endMark = '</mark>',
    String ellipsis = '...',
    int tokens = 10,
  }) {
    // FTS5 snippet(table, column, startMark, endMark, ellipsis, tokens)
    return "snippet($tableName, $column, '$startMark', '$endMark', '$ellipsis', $tokens)";
  }

  /// Escape special characters for FTS5
  ///
  /// Escapes: " (double quote)
  ///
  /// Parameters:
  /// - [text]: Text to escape
  ///
  /// Returns: Escaped text safe for FTS5 queries
  static String escapeFtsText(String text) {
    return text.replaceAll('"', '""');
  }

  /// Validate FTS5 query syntax
  ///
  /// Checks for common syntax errors in FTS5 queries.
  ///
  /// Parameters:
  /// - [query]: Query to validate
  ///
  /// Returns: true if valid, throws exception if invalid
  static bool validateFtsQuery(String query) {
    if (query.trim().isEmpty) {
      throw ArgumentError('Query cannot be empty');
    }

    // Check for unbalanced quotes
    final quoteCount = '"'.allMatches(query).length;
    if (quoteCount % 2 != 0) {
      throw ArgumentError('Unbalanced quotes in query');
    }

    // Check for unbalanced parentheses
    int openParens = 0;
    for (final char in query.split('')) {
      if (char == '(') openParens++;
      if (char == ')') openParens--;
      if (openParens < 0) {
        throw ArgumentError('Unbalanced parentheses in query');
      }
    }
    if (openParens != 0) {
      throw ArgumentError('Unbalanced parentheses in query');
    }

    // Check for invalid operator usage
    final invalidPatterns = [
      RegExp(r'\bAND\s+AND\b', caseSensitive: false),
      RegExp(r'\bOR\s+OR\b', caseSensitive: false),
      RegExp(r'\bNOT\s+NOT\b', caseSensitive: false),
      RegExp(r'^\s*AND\b', caseSensitive: false),
      RegExp(r'^\s*OR\b', caseSensitive: false),
      RegExp(r'\bAND\s*$', caseSensitive: false),
      RegExp(r'\bOR\s*$', caseSensitive: false),
    ];

    for (final pattern in invalidPatterns) {
      if (pattern.hasMatch(query)) {
        throw ArgumentError('Invalid operator usage in query');
      }
    }

    return true;
  }

  /// Check if query contains FTS5 operators
  static bool _containsFtsOperators(String query) {
    final operators = [
      RegExp(r'\bAND\b', caseSensitive: false),
      RegExp(r'\bOR\b', caseSensitive: false),
      RegExp(r'\bNOT\b', caseSensitive: false),
      RegExp(r'\bNEAR\b', caseSensitive: false),
      RegExp(r'"[^"]+"'), // Phrase search
      RegExp(r'\w+\*'), // Prefix search
    ];

    return operators.any((op) => op.hasMatch(query));
  }

  /// Sanitize FTS5 query (remove dangerous characters)
  static String _sanitizeFtsQuery(String query) {
    // Remove potential SQL injection characters
    // Keep FTS5 operators: AND, OR, NOT, NEAR, *, ", (, )
    return query
        .replaceAll(RegExp(r'[;]'), '') // Remove semicolons
        .replaceAll(RegExp(r'--'), '') // Remove SQL comments
        .replaceAll(RegExp(r'/\*'), '') // Remove block comments
        .trim();
  }

  /// Build FTS5 query from natural language query
  static String _buildNaturalLanguageQuery(
    String query, {
    List<String>? searchColumns,
  }) {
    final words = query.trim().split(RegExp(r'\s+'));

    // If single word, return as-is
    if (words.length == 1) {
      return escapeFtsText(words[0]);
    }

    // Default: treat multiple words as AND query
    // User can override with explicit OR/NOT operators
    final escapedWords = words.map((w) => escapeFtsText(w)).toList();
    return escapedWords.join(' AND ');
  }

  /// Escape SQL string literals
  static String _escape(String value) {
    return value.replaceAll("'", "''");
  }

  /// Build regex pattern for REGEXP operator
  ///
  /// Validates and escapes regex pattern for SQLite REGEXP.
  ///
  /// Parameters:
  /// - [pattern]: Regular expression pattern
  ///
  /// Returns: Escaped pattern safe for REGEXP operator
  static String buildRegexPattern(String pattern) {
    // Basic validation - check if pattern is valid
    try {
      RegExp(pattern);
    } catch (e) {
      throw ArgumentError('Invalid regex pattern: $e');
    }

    // Escape single quotes for SQL
    return pattern.replaceAll("'", "''");
  }

  /// Convert user-friendly operators to FTS5 syntax
  ///
  /// Converts:
  /// - "+" to AND
  /// - "|" to OR
  /// - "-" to NOT
  ///
  /// Parameters:
  /// - [query]: Query with user-friendly operators
  ///
  /// Returns: Query with FTS5 operators
  static String convertOperators(String query) {
    return query
        .replaceAllMapped(
          RegExp(r'\s*\+\s*'),
          (m) => ' AND ',
        )
        .replaceAllMapped(
          RegExp(r'\s*\|\s*'),
          (m) => ' OR ',
        )
        .replaceAllMapped(
          RegExp(r'\s*-\s*(\w+)'),
          (m) => ' NOT ${m.group(1)}',
        )
        .trim();
  }
}
