import '../models/search_result.dart';

/// Regex SQL query builder for pattern-based search operations
///
/// Builds SQL queries using REGEXP operator for advanced pattern matching.
/// Note: REGEXP searches are slower than FTS5 queries.
class RegexQueryBuilder {
  /// Maximum number of results per query
  static const int maxLimit = 1000;

  /// Build complete SQL query for regex search across translation units
  ///
  /// Uses REGEXP operator to search in source and/or translated text.
  /// Significantly slower than FTS5 for large datasets.
  ///
  /// Parameters:
  /// - [pattern]: Regular expression pattern (already validated and escaped)
  /// - [searchIn]: Fields to search ('source', 'target', or 'both')
  /// - [filter]: Optional search filters
  /// - [limit]: Maximum results (default: 100, max: 1000)
  ///
  /// Returns: Complete SQL query string
  static String buildRegexQuery(
    String pattern, {
    required String searchIn,
    SearchFilter? filter,
    required int limit,
  }) {
    final filterClause = _buildFilterClause(filter);
    final limitClause = _buildLimitClause(limit);
    final regexCondition = _buildRegexCondition(pattern, searchIn);

    return '''
      SELECT
        tu.id,
        tu.project_id,
        p.name as project_name,
        tu.key,
        tu.source_text,
        tv.translated_text,
        tu.created_at,
        tu.updated_at,
        CASE
          WHEN tu.source_text REGEXP '$pattern' THEN 'source_text'
          ELSE 'translated_text'
        END as matched_field
      FROM translation_units tu
      LEFT JOIN translation_versions tv ON tv.translation_unit_id = tu.id
      LEFT JOIN projects p ON tu.project_id = p.id
      WHERE $regexCondition
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      $limitClause
    ''';
  }

  /// Validate and escape regex pattern for SQL REGEXP operator
  ///
  /// Validates that the pattern is a valid regular expression and
  /// escapes it for safe use in SQL queries.
  ///
  /// Parameters:
  /// - [pattern]: Regular expression pattern
  ///
  /// Returns: Escaped pattern safe for SQL REGEXP operator
  ///
  /// Throws: [ArgumentError] if pattern is invalid
  static String validateAndEscapePattern(String pattern) {
    // Validate regex pattern
    try {
      RegExp(pattern);
    } catch (e) {
      throw ArgumentError('Invalid regex pattern: $e');
    }

    // Escape single quotes for SQL
    return pattern.replaceAll("'", "''");
  }

  /// Build regex condition based on search scope
  ///
  /// Parameters:
  /// - [pattern]: Regex pattern (already escaped)
  /// - [searchIn]: Search scope ('source', 'target', or 'both')
  ///
  /// Returns: SQL condition for REGEXP operator
  static String _buildRegexCondition(String pattern, String searchIn) {
    return switch (searchIn) {
      'source' => "tu.source_text REGEXP '$pattern'",
      'target' => "tv.translated_text REGEXP '$pattern'",
      'both' || _ => "(tu.source_text REGEXP '$pattern' OR tv.translated_text REGEXP '$pattern')",
    };
  }

  /// Build WHERE clause from SearchFilter
  ///
  /// Parameters:
  /// - [filter]: Search filter configuration
  ///
  /// Returns: SQL WHERE conditions (without 'WHERE' keyword) or empty string
  static String _buildFilterClause(SearchFilter? filter) {
    // Early return for null or empty filter
    if (filter == null || filter.isEmpty) {
      return '';
    }

    final conditions = <String>[];

    // Add list-based filters using helper method
    _addListFilter(conditions, filter.projectIds, 'tu.project_id');
    _addListFilter(conditions, filter.languageCodes, 'tv.language_code');
    _addListFilter(conditions, filter.statuses, 'tv.status');
    _addListFilter(conditions, filter.fileNames, 'tu.file_name');

    // Add date range filters
    if (filter.minDate != null) {
      conditions.add('tu.created_at >= ${filter.minDate!.millisecondsSinceEpoch}');
    }
    if (filter.maxDate != null) {
      conditions.add('tu.created_at <= ${filter.maxDate!.millisecondsSinceEpoch}');
    }

    return conditions.join(' AND ');
  }

  /// Helper method to add IN clause for list-based filters
  ///
  /// Parameters:
  /// - [conditions]: List to add condition to
  /// - [values]: List of values for the filter
  /// - [columnName]: SQL column name
  static void _addListFilter(
    List<String> conditions,
    List<String>? values,
    String columnName,
  ) {
    if (values != null && values.isNotEmpty) {
      final placeholders = values.map((v) => "'${_escapeSql(v)}'").join(', ');
      conditions.add('$columnName IN ($placeholders)');
    }
  }

  /// Build LIMIT clause for pagination
  ///
  /// Parameters:
  /// - [limit]: Maximum results (clamped to maxLimit)
  ///
  /// Returns: SQL LIMIT clause
  static String _buildLimitClause(int limit) {
    final safeLimit = limit.clamp(1, maxLimit);
    return 'LIMIT $safeLimit';
  }

  /// Escape SQL string literals
  ///
  /// Parameters:
  /// - [value]: String to escape
  ///
  /// Returns: Escaped string safe for SQL queries
  static String _escapeSql(String value) {
    return value.replaceAll("'", "''");
  }
}
