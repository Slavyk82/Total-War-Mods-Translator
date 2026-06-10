import '../models/search_result.dart';

/// Regex SQL query builder for pattern-based search operations
///
/// IMPORTANT — REGEXP is NOT available in this app's SQLite engine.
/// SQLite (and the `sqflite_common_ffi` backend used here) ships NO built-in
/// `REGEXP` function, and the codebase never registers one (there is no
/// `createFunction`/REGEXP hook on the connection-open path — verified by
/// grep). Emitting `col REGEXP '...'` therefore made every regex search throw
/// "no such function: REGEXP" at execution time, surfacing as an opaque
/// `SearchDatabaseException` to the user.
///
/// Decision (least-surprising, in-scope fix):
///   * For the common case where the pattern is just a literal substring
///     (no regex metacharacters), we emit an equivalent `LIKE` query so the
///     feature works for everyday searches.
///   * For a *true* regex (containing metacharacters that LIKE cannot express),
///     we throw a clear [UnsupportedError] so the failure is explicit and
///     actionable instead of a silent "no such function" crash.
///
/// Registering a custom `REGEXP` function would be the only way to support full
/// regex, but that belongs on the connection-open path (out of scope for this
/// builder). The natural place would be wherever the sqflite/ffi database is
/// opened; this builder is consumed by
/// `SearchServiceImpl.searchWithRegex` (search_service_impl.dart) which already
/// maps [ArgumentError] -> InvalidRegexException, so [UnsupportedError] from
/// here propagates as a generic search error with a descriptive message.
class RegexQueryBuilder {
  /// Maximum number of results per query
  static const int maxLimit = 1000;

  /// Regex metacharacters that cannot be represented by a SQL `LIKE` pattern.
  ///
  /// If a (pre-escape) pattern contains any of these, it is a "true" regex and
  /// we cannot fall back to LIKE without changing its meaning.
  static final RegExp _regexMetaChars = RegExp(r'[.*+?^$()\[\]{}|\\]');

  /// Build complete SQL query for regex search across translation units.
  ///
  /// Because SQLite has no `REGEXP` function here (see class doc), this only
  /// supports patterns that are plain literal substrings, which are translated
  /// into an equivalent case-insensitive `LIKE '%...%'` query.
  ///
  /// Parameters:
  /// - [pattern]: Pattern as returned by [validateAndEscapePattern] (single
  ///   quotes already doubled for SQL). Must be a literal substring.
  /// - [searchIn]: Fields to search ('source', 'target', or 'both')
  /// - [filter]: Optional search filters
  /// - [limit]: Maximum results (default: 100, max: 1000)
  ///
  /// Returns: Complete SQL query string
  ///
  /// Throws: [UnsupportedError] if [pattern] contains regex metacharacters,
  ///   because true regex requires a registered SQLite REGEXP function that
  ///   this app does not provide.
  static String buildRegexQuery(
    String pattern, {
    required String searchIn,
    SearchFilter? filter,
    required int limit,
  }) {
    // Reject true-regex patterns explicitly instead of emitting SQL that would
    // fail at runtime with "no such function: REGEXP".
    if (_regexMetaChars.hasMatch(pattern)) {
      throw UnsupportedError(
        'Regex search is not supported: SQLite has no REGEXP function '
        'registered in this app. Only literal substring patterns work. '
        'Pattern contained regex metacharacters: "$pattern".',
      );
    }

    final filterClause = _buildFilterClause(filter);
    final limitClause = _buildLimitClause(limit);
    final likeCondition = _buildLikeCondition(pattern, searchIn);

    // The pattern is a literal substring (no metacharacters). We additionally
    // escape LIKE wildcards so a literal `%` / `_` (which are NOT regex
    // metacharacters) are matched literally, pairing with `ESCAPE '\'`.
    final likePattern = _escapeSqlLikePattern(pattern);

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
          WHEN tu.source_text LIKE '%$likePattern%' ESCAPE '\\' THEN 'source_text'
          ELSE 'translated_text'
        END as matched_field
      FROM translation_units tu
      LEFT JOIN translation_versions tv ON tv.unit_id = tu.id
      LEFT JOIN projects p ON tu.project_id = p.id
      WHERE $likeCondition
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      GROUP BY tu.id
      ORDER BY tu.id
      $limitClause
    ''';
  }

  /// Validate and SQL-escape a search pattern.
  ///
  /// Validates that the pattern is a syntactically valid regular expression
  /// (so callers get an early [ArgumentError] for bad input) and escapes SQL
  /// single quotes for safe interpolation. Note that even a valid regex will
  /// be rejected later by [buildRegexQuery] if it actually uses regex
  /// metacharacters, since SQLite has no REGEXP function here.
  ///
  /// Parameters:
  /// - [pattern]: Regular expression pattern
  ///
  /// Returns: Escaped pattern safe for SQL string interpolation
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

  /// Build the search condition based on scope, using LIKE (not REGEXP).
  ///
  /// SQLite has no REGEXP function in this app (see class doc), so we match
  /// literal substrings with a case-insensitive `LIKE '%...%'`. LIKE wildcards
  /// in the literal are escaped via [_escapeSqlLikePattern] and neutralised
  /// with `ESCAPE '\'`.
  ///
  /// Parameters:
  /// - [pattern]: Literal substring (single quotes already SQL-escaped)
  /// - [searchIn]: Search scope ('source', 'target', or 'both')
  ///
  /// Returns: SQL condition using LIKE
  static String _buildLikeCondition(String pattern, String searchIn) {
    final likePattern = _escapeSqlLikePattern(pattern);
    final source = "tu.source_text LIKE '%$likePattern%' ESCAPE '\\'";
    final target = "tv.translated_text LIKE '%$likePattern%' ESCAPE '\\'";
    return switch (searchIn) {
      'source' => source,
      'target' => target,
      'both' || _ => '($source OR $target)',
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

  /// Escape LIKE wildcards in a pattern that has ALREADY had its SQL single
  /// quotes doubled (by [validateAndEscapePattern]).
  ///
  /// This escapes the backslash first, then the LIKE wildcards `%` and `_`,
  /// pairing with `ESCAPE '\'` in the SQL. It intentionally does NOT touch
  /// single quotes (those are already doubled) to avoid double-escaping.
  static String _escapeSqlLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
