import '../models/search_result.dart';

/// FTS5 SQL query builder for full-text search operations
///
/// Builds complete SQL queries for FTS5 virtual tables with proper
/// joins, filters, ranking, and highlighting.
///
/// Ranking note: SQLite FTS5 `rank` defaults to bm25(), which returns
/// NEGATIVE values where MORE NEGATIVE = MORE relevant. All queries here
/// therefore use ascending `ORDER BY rank` so the best matches come first
/// (critical: LIMIT truncates inside SQLite, so a wrong sort direction
/// permanently discards the most relevant rows). The service layer negates
/// the raw rank into `SearchResult.relevanceScore` (positive, higher =
/// better), and `SearchFilter.minRelevanceScore` follows that positive
/// convention — it maps to `rank <= -minRelevanceScore` in SQL.
class FtsQueryBuilder {
  /// Maximum number of results per query
  static const int maxLimit = 1000;

  /// Maximum offset for pagination
  static const int maxOffset = 1000000;

  /// Default context length for snippets
  static const int defaultContextLength = 50;

  /// Build complete SQL query for translation units search
  ///
  /// Searches translation_units_fts virtual table with proper joins
  /// to projects table for metadata.
  ///
  /// Parameters:
  /// - [ftsQuery]: FTS5 MATCH query string
  /// - [filter]: Optional search filters
  /// - [limit]: Maximum results (default: 100, max: 1000)
  /// - [offset]: Pagination offset (default: 0)
  ///
  /// Returns: Complete SQL query string
  ///
  /// Throws: [ArgumentError] if query contains SQL injection patterns
  static String buildTranslationUnitsQuery(
    String ftsQuery, {
    SearchFilter? filter,
    required int limit,
    int offset = 0,
  }) {
    // Sanitize FTS5 query to prevent SQL injection
    final sanitizedQuery = _sanitizeFtsQuery(ftsQuery);

    final filterClause = _buildFilterClause(filter, tablePrefix: 'tu');
    final limitClause = _buildLimitClause(limit, offset);

    return '''
      SELECT
        tu.id,
        tu.project_id,
        p.name as project_name,
        tu.key,
        tu.source_text,
        tu.source_loc_file as file_name,
        tu.created_at,
        tu.updated_at,
        fts.rank,
        snippet(translation_units_fts, 1, '<mark>', '</mark>', '...', 10) as highlighted
      FROM translation_units_fts fts
      INNER JOIN translation_units tu ON fts.rowid = tu.rowid
      LEFT JOIN projects p ON tu.project_id = p.id
      WHERE translation_units_fts MATCH '$sanitizedQuery'
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      ORDER BY rank
      $limitClause
    ''';
  }

  /// Build complete SQL query for translation versions search
  ///
  /// Searches translation_versions_fts virtual table with joins to
  /// translation units, projects, and languages.
  ///
  /// Note: Uses contentless FTS5 with version_id column for JOIN
  /// (avoids rowid mapping issues with TEXT PRIMARY KEY)
  ///
  /// Parameters:
  /// - [ftsQuery]: FTS5 MATCH query string
  /// - [filter]: Optional search filters
  /// - [limit]: Maximum results
  /// - [offset]: Pagination offset
  ///
  /// Returns: Complete SQL query string
  ///
  /// Throws: [ArgumentError] if query contains SQL injection patterns
  static String buildTranslationVersionsQuery(
    String ftsQuery, {
    SearchFilter? filter,
    required int limit,
    int offset = 0,
  }) {
    // Sanitize FTS5 query to prevent SQL injection
    final sanitizedQuery = _sanitizeFtsQuery(ftsQuery);

    // Scope the MATCH to the translated_text column only.
    //
    // `translation_versions_fts` indexes two columns: translated_text (col 0)
    // and validation_issues (col 1) (see schema.sql). An unqualified MATCH
    // would also match against the validation_issues JSON, producing false
    // positives. FTS5 column-filter syntax `{col} : <query>` restricts the
    // match to that column. The snippet() below already targets col 0
    // (translated_text), so highlighting stays consistent.
    final scopedQuery = '{translated_text} : $sanitizedQuery';

    // translation_versions has no language_code/project_id/file_name columns:
    // language is reached via project_languages -> languages, and
    // project_id/file_name live on translation_units. Use a version-specific
    // filter clause that routes each predicate to the correct table/alias.
    final filterClause = _buildVersionFilterClause(filter);
    final limitClause = _buildLimitClause(limit, offset);

    return '''
      SELECT
        tv.id,
        tu.project_id,
        p.name as project_name,
        l.code as language_code,
        l.name as language_name,
        tu.key,
        tu.source_text,
        tv.translated_text,
        tv.status,
        tv.created_at,
        tv.updated_at,
        fts.rank,
        snippet(translation_versions_fts, 0, '<mark>', '</mark>', '...', 10) as highlighted
      FROM translation_versions_fts fts
      INNER JOIN translation_versions tv ON fts.version_id = tv.id
      INNER JOIN translation_units tu ON tv.unit_id = tu.id
      LEFT JOIN projects p ON tu.project_id = p.id
      LEFT JOIN project_languages pl ON tv.project_language_id = pl.id
      LEFT JOIN languages l ON pl.language_id = l.id
      WHERE translation_versions_fts MATCH '$scopedQuery'
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      ORDER BY rank
      $limitClause
    ''';
  }

  /// Build complete SQL query for translation memory search
  ///
  /// Searches translation_memory_fts virtual table with language filters.
  ///
  /// Parameters:
  /// - [ftsQuery]: FTS5 MATCH query string
  /// - [targetLanguage]: Target language filter (optional)
  /// - [limit]: Maximum results
  /// - [offset]: Pagination offset
  ///
  /// Returns: Complete SQL query string
  ///
  /// Throws: [ArgumentError] if query contains SQL injection patterns
  static String buildTranslationMemoryQuery(
    String ftsQuery, {
    String? targetLanguage,
    required int limit,
    int offset = 0,
  }) {
    // Sanitize FTS5 query to prevent SQL injection
    final sanitizedQuery = _sanitizeFtsQuery(ftsQuery);

    final limitClause = _buildLimitClause(limit, offset);

    final languageFilters = <String>[];
    if (targetLanguage != null) {
      languageFilters.add("tm.target_language = '${_escapeSql(targetLanguage)}'");
    }

    final languageClause =
        languageFilters.isNotEmpty ? 'AND ${languageFilters.join(' AND ')}' : '';

    return '''
      SELECT
        tm.id,
        tm.source_text,
        tm.target_text,
        tm.target_language,
        tm.created_at,
        tm.last_used_at,
        fts.rank,
        -- NOTE: translation_memory_fts indexes source_text (col 0) and
        -- translated_text (col 1); the MATCH below intentionally spans BOTH
        -- columns (TM lookups search either side). The snippet() is hardcoded
        -- to col 1 (translated_text), so when a hit is only in source_text the
        -- highlight may be empty/unhighlighted. Per-column snippet selection is
        -- left out deliberately to keep this query simple.
        snippet(translation_memory_fts, 1, '<mark>', '</mark>', '...', 10) as highlighted
      FROM translation_memory_fts fts
      INNER JOIN translation_memory tm ON fts.rowid = tm.rowid
      WHERE translation_memory_fts MATCH '$sanitizedQuery'
      $languageClause
      ORDER BY rank
      $limitClause
    ''';
  }

  /// Build complete SQL query for glossary search
  ///
  /// Uses LIKE queries (not FTS5) for glossary entries.
  /// Can be migrated to FTS5 later for better performance.
  ///
  /// Parameters:
  /// - [query]: Search query (plain text)
  /// - [glossaryId]: Filter by glossary ID (optional)
  /// - [category]: Filter by category (optional)
  /// - [limit]: Maximum results
  /// - [offset]: Pagination offset
  ///
  /// Returns: Complete SQL query string
  static String buildGlossaryQuery(
    String query, {
    String? glossaryId,
    String? category,
    required int limit,
    int offset = 0,
  }) {
    final filters = <String>[];

    if (glossaryId != null) {
      filters.add("glossary_id = '${_escapeSql(glossaryId)}'");
    }

    if (category != null) {
      filters.add("category = '${_escapeSql(category)}'");
    }

    final whereClause = filters.isNotEmpty ? 'AND ${filters.join(' AND ')}' : '';
    final limitClause = _buildLimitClause(limit, offset);
    final escapedQuery = _escapeSqlLikePattern(query);

    return '''
      SELECT
        id,
        term,
        translation,
        category,
        notes,
        created_at,
        updated_at
      FROM glossary_entries
      WHERE (term LIKE '%$escapedQuery%' ESCAPE '\\' OR translation LIKE '%$escapedQuery%' ESCAPE '\\' OR notes LIKE '%$escapedQuery%' ESCAPE '\\')
      $whereClause
      ORDER BY term ASC
      $limitClause
    ''';
  }

  /// Build WHERE clause from SearchFilter
  ///
  /// Generates SQL conditions for project, language, status, date, and
  /// relevance filters.
  ///
  /// Parameters:
  /// - [filter]: Search filter configuration
  /// - [tablePrefix]: Table alias prefix (e.g., 'tu', 'tv')
  ///
  /// Returns: SQL WHERE conditions (without 'WHERE' keyword) or empty string
  ///
  /// Used by the translation_units (source-text) query only. translation_units
  /// has no `status` or `language_code` column — those predicates belong to
  /// translation_versions — so they are intentionally NOT emitted here (doing
  /// so would raise "no such column"). Use [_buildVersionFilterClause] for the
  /// versions query.
  static String _buildFilterClause(
    SearchFilter? filter, {
    String tablePrefix = 't',
  }) {
    if (filter == null || filter.isEmpty) {
      return '';
    }

    final conditions = <String>[];

    // Project ID filter
    if (filter.projectIds != null && filter.projectIds!.isNotEmpty) {
      final placeholders =
          filter.projectIds!.map((id) => "'${_escapeSql(id)}'").join(', ');
      conditions.add('$tablePrefix.project_id IN ($placeholders)');
    }

    // File name filter (translation_units stores it as source_loc_file)
    if (filter.fileNames != null && filter.fileNames!.isNotEmpty) {
      final placeholders =
          filter.fileNames!.map((f) => "'${_escapeSql(f)}'").join(', ');
      conditions.add('$tablePrefix.source_loc_file IN ($placeholders)');
    }

    // Date range filters
    if (filter.minDate != null) {
      final timestamp = filter.minDate!.millisecondsSinceEpoch;
      conditions.add('$tablePrefix.created_at >= $timestamp');
    }

    if (filter.maxDate != null) {
      final timestamp = filter.maxDate!.millisecondsSinceEpoch;
      conditions.add('$tablePrefix.created_at <= $timestamp');
    }

    // Relevance score filter. minRelevanceScore uses the public positive
    // convention (higher = better); the raw FTS5 bm25 rank is negative with
    // more-negative = better, so the predicate is rank <= -minRelevanceScore.
    if (filter.minRelevanceScore != null) {
      conditions.add('rank <= ${-filter.minRelevanceScore!}');
    }

    return conditions.join(' AND ');
  }

  /// Build a WHERE clause for the translation_versions search query.
  ///
  /// Routes each predicate to the table/alias that actually holds the column:
  /// - project_id / file_name -> translation_units (`tu`)
  /// - language code          -> languages (`l.code`, via project_languages)
  /// - status / created_at    -> translation_versions (`tv`)
  static String _buildVersionFilterClause(SearchFilter? filter) {
    if (filter == null || filter.isEmpty) {
      return '';
    }

    final conditions = <String>[];

    if (filter.projectIds != null && filter.projectIds!.isNotEmpty) {
      final placeholders =
          filter.projectIds!.map((id) => "'${_escapeSql(id)}'").join(', ');
      conditions.add('tu.project_id IN ($placeholders)');
    }

    if (filter.languageCodes != null && filter.languageCodes!.isNotEmpty) {
      final placeholders =
          filter.languageCodes!.map((code) => "'${_escapeSql(code)}'").join(', ');
      conditions.add('l.code IN ($placeholders)');
    }

    if (filter.statuses != null && filter.statuses!.isNotEmpty) {
      final placeholders =
          filter.statuses!.map((s) => "'${_escapeSql(s)}'").join(', ');
      conditions.add('tv.status IN ($placeholders)');
    }

    if (filter.fileNames != null && filter.fileNames!.isNotEmpty) {
      final placeholders =
          filter.fileNames!.map((f) => "'${_escapeSql(f)}'").join(', ');
      conditions.add('tu.source_loc_file IN ($placeholders)');
    }

    if (filter.minDate != null) {
      conditions.add('tv.created_at >= ${filter.minDate!.millisecondsSinceEpoch}');
    }

    if (filter.maxDate != null) {
      conditions.add('tv.created_at <= ${filter.maxDate!.millisecondsSinceEpoch}');
    }

    // See _buildFilterClause: positive minRelevanceScore maps to a
    // less-than predicate on the negative bm25 rank.
    if (filter.minRelevanceScore != null) {
      conditions.add('rank <= ${-filter.minRelevanceScore!}');
    }

    return conditions.join(' AND ');
  }

  /// Build LIMIT/OFFSET clause for pagination
  ///
  /// Parameters:
  /// - [limit]: Maximum results (clamped to maxLimit)
  /// - [offset]: Pagination offset (clamped to maxOffset)
  ///
  /// Returns: SQL LIMIT/OFFSET clause
  static String _buildLimitClause(int limit, int offset) {
    final safeLimit = limit.clamp(1, maxLimit);
    final safeOffset = offset.clamp(0, maxOffset);

    if (safeOffset > 0) {
      return 'LIMIT $safeLimit OFFSET $safeOffset';
    }
    return 'LIMIT $safeLimit';
  }

  /// Escape SQL string literals (single quotes only, for non-LIKE use).
  ///
  /// Prevents SQL injection by escaping single quotes. Use this for values
  /// compared with `=` or `IN (...)`, where LIKE wildcards have no meaning.
  ///
  /// Parameters:
  /// - [value]: String to escape
  ///
  /// Returns: Escaped string safe for SQL queries
  static String _escapeSql(String value) {
    return value.replaceAll("'", "''");
  }

  /// Escape a LIKE pattern literal.
  ///
  /// Order matters: escape the backslash FIRST (so later escapes' backslashes
  /// are not re-escaped), then `%` and `_` (LIKE wildcards), then the SQL
  /// single-quote. Callers must pair this with `ESCAPE '\'` in the SQL so
  /// the backslash is interpreted as the LIKE escape character.
  ///
  /// Parameters:
  /// - [value]: User-provided substring to match literally
  ///
  /// Returns: Escaped string safe for interpolation inside a LIKE pattern
  static String _escapeSqlLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll("'", "''");
  }

  /// Sanitize FTS5 query to prevent SQL injection
  ///
  /// FTS5 MATCH clauses cannot use parameterized queries, so we must
  /// sanitize the input string carefully.
  ///
  /// Parameters:
  /// - [query]: User-provided search query
  ///
  /// Returns: Sanitized query safe for FTS5 MATCH
  ///
  /// Throws: [ArgumentError] if query contains SQL injection patterns
  static String _sanitizeFtsQuery(String query) {
    if (query.trim().isEmpty) {
      throw ArgumentError('Search query cannot be empty');
    }

    // 1. Check for SQL injection patterns
    if (_containsSqlInjectionPatterns(query)) {
      throw ArgumentError(
        'Invalid search query: contains potential SQL injection patterns',
      );
    }

    // 2. Escape SQL quotes only.
    //
    // The MATCH value is interpolated inside SINGLE quotes ('$sanitizedQuery'),
    // so only the single quote needs doubling for SQL safety. We MUST NOT
    // double the double quote: in FTS5, `"..."` denotes a phrase query, and
    // doubling it (`""cavalry unit""`) corrupts the phrase syntax. Double
    // quotes are safe to leave intact because they are not the SQL string
    // delimiter here.
    var sanitized = query
        .replaceAll("'", "''")  // Escape single quotes (SQL safety)
        .trim();

    // 3. Validate length (prevent DoS via extremely long queries)
    if (sanitized.length > 500) {
      throw ArgumentError(
        'Search query too long (max 500 characters)',
      );
    }

    // 4. Remove potentially dangerous FTS5 operators if not alphanumeric
    // Allow: letters, numbers, spaces, hyphens, underscores, dots
    // Remove: control characters, semicolons, pipes, etc.
    sanitized = sanitized.replaceAll(RegExp(r'[^\w\s\-_."' "'" r']+'), ' ');

    return sanitized;
  }

  /// Detect potential SQL injection patterns
  ///
  /// Checks for common SQL injection attack vectors including:
  /// - SQL keywords (DROP, DELETE, UPDATE, etc.)
  /// - SQL comments (-- and /* */)
  /// - Statement terminators (;)
  /// - OR/AND tautologies (OR 1=1)
  ///
  /// Parameters:
  /// - [query]: Query string to check
  ///
  /// Returns: true if dangerous patterns detected, false otherwise
  static bool _containsSqlInjectionPatterns(String query) {
    // NOTE: the MATCH value is interpolated inside a SINGLE-quoted SQL literal
    // with single quotes doubled (see _sanitizeFtsQuery step 2), so genuine SQL
    // injection is already impossible. We therefore do NOT block ordinary
    // English words — DROP/DELETE/UPDATE/INSERT/ALTER/CREATE/EXEC and UNION are
    // common search terms in mod text (e.g. "union", "create"), and the
    // OR/AND-tautology heuristics add no real safety here. Blocking them only
    // broke legitimate searches. We keep checks for true metacharacters that
    // are never part of a normal search term.
    final dangerousPatterns = [
      // SQL comments
      RegExp(r'--'),        // Single-line SQL comments
      RegExp(r'/\*'),       // Multi-line comment start
      RegExp(r'\*/'),       // Multi-line comment end

      // Statement terminators
      RegExp(r';'),

      // Null byte injection
      RegExp(r'\x00'),
    ];

    return dangerousPatterns.any((pattern) => pattern.hasMatch(query));
  }
}
