import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../config/app_constants.dart';
import '../../models/common/result.dart';
import 'models/search_result.dart';
import 'models/search_exceptions.dart';

/// Service for managing search history and saved searches
///
/// Handles persistence of search queries, saved searches with filters,
/// and usage statistics.
class SearchHistoryService {
  final Uuid _uuid;

  SearchHistoryService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  Database get _db => DatabaseService.database;

  /// Get search history (last N searches)
  ///
  /// Returns the most recent search queries executed by the user.
  ///
  /// Parameters:
  /// - [limit]: Maximum number of history entries (default: 50, max: 100)
  ///
  /// Returns:
  /// - [Ok]: List of recent search queries with timestamps
  /// - [Err]: [SearchDatabaseException]
  Future<Result<List<Map<String, dynamic>>, SearchServiceException>>
      getSearchHistory({int limit = AppConstants.defaultSearchHistoryLimit}) async {
    try {
      final safeLimit = limit.clamp(
        AppConstants.minPageSize,
        AppConstants.maxSearchHistoryLimit,
      );

      final results = await _db.query(
        'search_history',
        orderBy: 'created_at DESC',
        limit: safeLimit,
      );

      return Ok(results);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to get search history',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error getting history',
          dbError: e));
    }
  }

  /// Add query to search history
  ///
  /// Stores the search query for future reference. Automatically called
  /// by search methods.
  ///
  /// Parameters:
  /// - [query]: Search query to save
  /// - [resultCount]: Number of results found
  ///
  /// Returns:
  /// - [Ok]: true if saved successfully
  /// - [Err]: [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> addToSearchHistory(
    String query,
    int resultCount,
  ) async {
    try {
      // Check history limit
      final countResult = await _db.rawQuery(
          'SELECT COUNT(*) as count FROM search_history');
      final count = countResult.first['count'] as int;

      if (count >= AppConstants.maxSearchHistory) {
        // Delete oldest entry
        await _db.rawDelete('''
          DELETE FROM search_history
          WHERE id = (SELECT id FROM search_history ORDER BY created_at ASC LIMIT 1)
        ''');
      }

      // Insert new entry
      await _db.insert('search_history', {
        'id': _uuid.v4(),
        'query': query,
        'result_count': resultCount,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      return const Ok(true);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to add to search history',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error adding to history',
          dbError: e));
    }
  }

  /// Clear search history
  ///
  /// Removes all search history entries.
  ///
  /// Returns:
  /// - [Ok]: Number of entries deleted
  /// - [Err]: [SearchDatabaseException]
  Future<Result<int, SearchServiceException>> clearSearchHistory() async {
    try {
      final count = await _db.delete('search_history');
      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to clear search history',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error clearing history',
          dbError: e));
    }
  }

  /// Save a search query for later use
  ///
  /// Parameters:
  /// - [name]: Display name for the saved search
  /// - [query]: Search query to save
  /// - [filter]: Optional search filter
  ///
  /// Returns:
  /// - [Ok]: Created SavedSearch object
  /// - [Err]: [DuplicateSavedSearchException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> saveSearch(
    String name,
    String query, {
    SearchFilter? filter,
  }) async {
    try {
      // Check for duplicate name
      final existing = await _db.query(
        'saved_searches',
        where: 'name = ?',
        whereArgs: [name],
      );

      if (existing.isNotEmpty) {
        return Err(DuplicateSavedSearchException(
          'Saved search with name "$name" already exists',
          name: name,
        ));
      }

      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      final savedSearch = SavedSearch(
        id: id,
        name: name,
        query: query,
        filter: filter,
        createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        usageCount: 0,
      );

      await _db.insert('saved_searches', {
        'id': id,
        'name': name,
        'query': query,
        'filter_json': filter != null ? _encodeFilter(filter) : null,
        'created_at': now,
        'last_used_at': null,
        'usage_count': 0,
      });

      return Ok(savedSearch);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to save search', dbError: e));
    } catch (e) {
      return Err(
          SearchDatabaseException('Unexpected error saving search', dbError: e));
    }
  }

  /// Get all saved searches
  ///
  /// Returns:
  /// - [Ok]: List of saved searches ordered by usage count (descending)
  /// - [Err]: [SearchDatabaseException]
  Future<Result<List<SavedSearch>, SearchServiceException>>
      getSavedSearches() async {
    try {
      final results = await _db.query(
        'saved_searches',
        orderBy: 'usage_count DESC, created_at DESC',
      );

      final savedSearches = results.map((row) {
        return SavedSearch(
          id: row['id'] as String,
          name: row['name'] as String,
          query: row['query'] as String,
          filter: _decodeFilter(row['filter_json'] as String?),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int),
          lastUsedAt: row['last_used_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  row['last_used_at'] as int)
              : null,
          usageCount: row['usage_count'] as int,
        );
      }).toList();

      return Ok(savedSearches);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to get saved searches',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error getting saved searches',
          dbError: e));
    }
  }

  /// Get a saved search by ID
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: SavedSearch object
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> getSavedSearch(
      String id) async {
    try {
      final results = await _db.query(
        'saved_searches',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (results.isEmpty) {
        return Err(SavedSearchNotFoundException(
          'Saved search not found',
          searchId: id,
        ));
      }

      final row = results.first;
      final savedSearch = SavedSearch(
        id: row['id'] as String,
        name: row['name'] as String,
        query: row['query'] as String,
        filter: _decodeFilter(row['filter_json'] as String?),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        lastUsedAt: row['last_used_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['last_used_at'] as int)
            : null,
        usageCount: row['usage_count'] as int,
      );

      return Ok(savedSearch);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to get saved search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error getting saved search',
          dbError: e));
    }
  }

  /// Update a saved search
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  /// - [name]: New name (optional)
  /// - [query]: New query (optional)
  /// - [filter]: New filter (optional)
  ///
  /// Returns:
  /// - [Ok]: Updated SavedSearch object
  /// - [Err]: [SavedSearchNotFoundException], [DuplicateSavedSearchException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> updateSavedSearch(
    String id, {
    String? name,
    String? query,
    SearchFilter? filter,
  }) async {
    try {
      // Check if exists
      final existingResult = await getSavedSearch(id);
      if (existingResult is Err) {
        return existingResult;
      }

      final existing = (existingResult as Ok<SavedSearch, SearchServiceException>).value;

      // Check for duplicate name if changing name
      if (name != null && name != existing.name) {
        final duplicate = await _db.query(
          'saved_searches',
          where: 'name = ? AND id != ?',
          whereArgs: [name, id],
        );

        if (duplicate.isNotEmpty) {
          return Err(DuplicateSavedSearchException(
            'Saved search with name "$name" already exists',
            name: name,
          ));
        }
      }

      // Update
      await _db.update(
        'saved_searches',
        {
          if (name != null) 'name': name,
          if (query != null) 'query': query,
          if (filter != null) 'filter_json': _encodeFilter(filter),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Return updated
      return getSavedSearch(id);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to update saved search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error updating saved search',
          dbError: e));
    }
  }

  /// Delete a saved search
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: true if deleted successfully
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> deleteSavedSearch(
      String id) async {
    try {
      final count = await _db.delete(
        'saved_searches',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (count == 0) {
        return Err(SavedSearchNotFoundException(
          'Saved search not found',
          searchId: id,
        ));
      }

      return const Ok(true);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to delete saved search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error deleting saved search',
          dbError: e));
    }
  }

  /// Increment usage count for a saved search
  ///
  /// Called automatically when executing a saved search.
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: true if updated successfully
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> incrementSavedSearchUsage(
      String id) async {
    try {
      final count = await _db.rawUpdate('''
        UPDATE saved_searches
        SET usage_count = usage_count + 1,
            last_used_at = ?
        WHERE id = ?
      ''', [DateTime.now().millisecondsSinceEpoch, id]);

      if (count == 0) {
        return Err(SavedSearchNotFoundException(
          'Saved search not found',
          searchId: id,
        ));
      }

      return const Ok(true);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to increment usage count',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error incrementing usage',
          dbError: e));
    }
  }

  /// Get search statistics
  ///
  /// Returns statistics about search usage and performance.
  ///
  /// Returns:
  /// - [Ok]: Map with statistics (total_searches, avg_results, saved_searches_count)
  /// - [Err]: [SearchDatabaseException]
  Future<Result<Map<String, dynamic>, SearchServiceException>>
      getSearchStatistics() async {
    try {
      final totalSearches = await _db.rawQuery(
          'SELECT COUNT(*) as count FROM search_history');
      final avgResults = await _db.rawQuery(
          'SELECT AVG(result_count) as avg FROM search_history');

      final stats = {
        'total_searches': totalSearches.first['count'] as int,
        'avg_results': (avgResults.first['avg'] as num?)?.toDouble() ?? 0.0,
        'saved_searches_count': (await _db.query('saved_searches')).length,
      };

      return Ok(stats);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Failed to get statistics',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error getting statistics',
          dbError: e));
    }
  }

  /// Encode SearchFilter to JSON string for database storage
  ///
  /// Parameters:
  /// - [filter]: SearchFilter to encode
  ///
  /// Returns: JSON string representation
  String _encodeFilter(SearchFilter filter) {
    return jsonEncode(filter.toJson());
  }

  /// Decode SearchFilter from JSON string
  ///
  /// Parameters:
  /// - [filterJson]: JSON string to decode
  ///
  /// Returns: SearchFilter object or null if invalid
  SearchFilter? _decodeFilter(String? filterJson) {
    if (filterJson == null || filterJson.isEmpty) return null;
    try {
      final json = jsonDecode(filterJson) as Map<String, dynamic>;
      return SearchFilter.fromJson(json);
    } catch (e) {
      // Log error but don't throw - return null for invalid filters
      return null;
    }
  }
}
