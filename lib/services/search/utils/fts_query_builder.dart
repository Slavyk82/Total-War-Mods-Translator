import '../models/search_result.dart';

/// FTS5 SQL query builder for full-text search operations
///
/// Builds complete SQL queries for FTS5 virtual tables with proper
/// joins, filters, ranking, and highlighting.
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
        tu.file_name,
        tu.created_at,
        tu.updated_at,
        fts.rank,
        snippet(translation_units_fts, 1, '<mark>', '</mark>', '...', 10) as highlighted
      FROM translation_units_fts fts
      INNER JOIN translation_units tu ON fts.rowid = tu.rowid
      LEFT JOIN projects p ON tu.project_id = p.id
      WHERE translation_units_fts MATCH '$sanitizedQuery'
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      ORDER BY rank DESC
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

    final filterClause = _buildFilterClause(filter, tablePrefix: 'tv');
    final limitClause = _buildLimitClause(limit, offset);

    return '''
      SELECT
        tv.id,
        tu.project_id,
        p.name as project_name,
        tv.language_code,
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
      LEFT JOIN languages l ON tv.language_code = l.code
      WHERE translation_versions_fts MATCH '$sanitizedQuery'
      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}
      ORDER BY rank DESC
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
        snippet(translation_memory_fts, 1, '<mark>', '</mark>', '...', 10) as highlighted
      FROM translation_memory_fts fts
      INNER JOIN translation_memory tm ON fts.rowid = tm.rowid
      WHERE translation_memory_fts MATCH '$sanitizedQuery'
      $languageClause
      ORDER BY rank DESC
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
    final escapedQuery = _escapeSql(query);

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
      WHERE (term LIKE '%$escapedQuery%' OR translation LIKE '%$escapedQuery%' OR notes LIKE '%$escapedQuery%')
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

    // Language code filter
    if (filter.languageCodes != null && filter.languageCodes!.isNotEmpty) {
      final placeholders =
          filter.languageCodes!.map((code) => "'${_escapeSql(code)}'").join(', ');
      conditions.add('$tablePrefix.language_code IN ($placeholders)');
    }

    // Status filter
    if (filter.statuses != null && filter.statuses!.isNotEmpty) {
      final placeholders =
          filter.statuses!.map((s) => "'${_escapeSql(s)}'").join(', ');
      conditions.add('$tablePrefix.status IN ($placeholders)');
    }

    // File name filter
    if (filter.fileNames != null && filter.fileNames!.isNotEmpty) {
      final placeholders =
          filter.fileNames!.map((f) => "'${_escapeSql(f)}'").join(', ');
      conditions.add('$tablePrefix.file_name IN ($placeholders)');
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

    // Relevance score filter
    if (filter.minRelevanceScore != null) {
      conditions.add('rank >= ${filter.minRelevanceScore}');
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

  /// Escape SQL string literals
  ///
  /// Prevents SQL injection by escaping single quotes.
  ///
  /// Parameters:
  /// - [value]: String to escape
  ///
  /// Returns: Escaped string safe for SQL queries
  static String _escapeSql(String value) {
    return value.replaceAll("'", "''");
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

    // 2. Escape FTS5 special characters and SQL quotes
    // FTS5 special chars: " * - ( ) [ ] { }
    var sanitized = query
        .replaceAll('"', '""')  // Escape double quotes
        .replaceAll("'", "''")  // Escape single quotes
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
    final dangerousPatterns = [
      // SQL DML/DDL keywords
      RegExp(r'\b(DROP|DELETE|UPDATE|INSERT|ALTER|CREATE|EXEC|EXECUTE)\b',
          caseSensitive: false),

      // SQL comments
      RegExp(r'--'),        // Single-line SQL comments
      RegExp(r'/\*'),       // Multi-line comment start
      RegExp(r'\*/'),       // Multi-line comment end

      // Statement terminators
      RegExp(r';'),

      // OR/AND tautologies
      RegExp(r'\bOR\s+["' "'" r']?1["' "'" r']?\s*=\s*["' "'" r']?1["' "'" r']?',
          caseSensitive: false),
      RegExp(r'\bAND\s+["' "'" r']?1["' "'" r']?\s*=\s*["' "'" r']?1["' "'" r']?',
          caseSensitive: false),

      // UNION-based injection
      RegExp(r'\bUNION\b', caseSensitive: false),

      // Null byte injection
      RegExp(r'\x00'),

      // SQL functions that shouldn't be in search queries
      RegExp(r'\b(LOAD_FILE|INTO\s+OUTFILE|INTO\s+DUMPFILE)\b',
          caseSensitive: false),
    ];

    return dangerousPatterns.any((pattern) => pattern.hasMatch(query));
  }
}
