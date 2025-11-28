import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/project_statistics.dart';

export '../../models/domain/project_statistics.dart' show GlobalStatistics;

/// Mixin providing statistics and counting operations for translation versions.
///
/// Extracts complex aggregation queries from the main repository to maintain
/// single responsibility and keep file sizes manageable.
mixin TranslationVersionStatisticsMixin {
  /// Database instance - must be provided by implementing class
  Database get database;

  /// Table name - must be provided by implementing class
  String get tableName;

  /// Execute a query with error handling - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeQuery<R>(
    Future<R> Function() query,
  );

  /// Count total translation versions for a project language.
  Future<Result<int, TWMTDatabaseException>> countByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ?',
        [projectLanguageId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count translated versions for a project language.
  Future<Result<int, TWMTDatabaseException>> countTranslatedByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND translated_text IS NOT NULL AND translated_text != ?',
        [projectLanguageId, ''],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count validated versions for a project language.
  Future<Result<int, TWMTDatabaseException>> countValidatedByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND (status = ? OR status = ?)',
        [projectLanguageId, 'approved', 'reviewed'],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count versions needing review for a project language.
  Future<Result<int, TWMTDatabaseException>> countNeedsReviewByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND status = ?',
        [projectLanguageId, 'needs_review'],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count translated versions for a project (across all languages).
  Future<Result<int, TWMTDatabaseException>> countTranslatedByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM $tableName tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.translated_text IS NOT NULL
          AND tv.translated_text != ''
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count pending versions for a project (across all languages).
  Future<Result<int, TWMTDatabaseException>> countPendingByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM $tableName tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.status = 'pending'
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count validated versions for a project (across all languages).
  Future<Result<int, TWMTDatabaseException>> countValidatedByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM $tableName tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND (tv.status = 'approved' OR tv.status = 'reviewed')
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count error versions for a project (across all languages).
  Future<Result<int, TWMTDatabaseException>> countErrorByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM $tableName tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.status = 'error'
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Get all translation statistics for a project in a single optimized query.
  ///
  /// Consolidates 4 separate COUNT queries into 1 for 3-4x performance improvement.
  Future<Result<ProjectStatistics, TWMTDatabaseException>> getProjectStatistics(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        WITH unit_best_status AS (
          SELECT
            tu.id as unit_id,
            MAX(CASE
              WHEN tv.status = 'approved' THEN 6
              WHEN tv.status = 'reviewed' THEN 5
              WHEN tv.status = 'translated' THEN 4
              WHEN tv.status = 'needs_review' THEN 3
              WHEN tv.status = 'translating' THEN 2
              WHEN tv.status = 'pending' THEN 1
              ELSE 0
            END) as status_priority,
            MAX(CASE WHEN tv.status = 'approved' THEN 1 ELSE 0 END) as is_approved,
            MAX(CASE WHEN tv.status = 'reviewed' THEN 1 ELSE 0 END) as is_reviewed,
            MAX(CASE WHEN tv.status = 'translated' THEN 1 ELSE 0 END) as is_translated,
            MAX(CASE WHEN tv.status = 'pending' OR tv.status = 'translating' THEN 1 ELSE 0 END) as is_pending,
            MAX(CASE WHEN tv.status = 'needs_review' THEN 1 ELSE 0 END) as is_needs_review
          FROM translation_units tu
          INNER JOIN $tableName tv ON tv.unit_id = tu.id
          WHERE tu.project_id = ?
          GROUP BY tu.id
        )
        SELECT
          COUNT(CASE WHEN status_priority = 4 THEN 1 END) as translated_count,
          COUNT(CASE WHEN status_priority <= 2 THEN 1 END) as pending_count,
          COUNT(CASE WHEN status_priority >= 5 THEN 1 END) as validated_count,
          COUNT(CASE WHEN status_priority = 3 THEN 1 END) as error_count
        FROM unit_best_status
        ''',
        [projectId],
      );

      if (result.isEmpty) {
        return ProjectStatistics.empty();
      }

      final row = result.first;
      return ProjectStatistics(
        translatedCount: (row['translated_count'] as int?) ?? 0,
        pendingCount: (row['pending_count'] as int?) ?? 0,
        validatedCount: (row['validated_count'] as int?) ?? 0,
        errorCount: (row['error_count'] as int?) ?? 0,
      );
    });
  }

  /// Get translation statistics for a specific project language.
  Future<Result<ProjectStatistics, TWMTDatabaseException>> getLanguageStatistics(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT
          COUNT(CASE WHEN tv.status = 'translated' THEN 1 END) as translated_count,
          COUNT(CASE WHEN tv.status IN ('pending', 'translating') THEN 1 END) as pending_count,
          COUNT(CASE WHEN tv.status IN ('approved', 'reviewed') THEN 1 END) as validated_count,
          COUNT(CASE WHEN tv.status = 'needs_review' THEN 1 END) as error_count
        FROM $tableName tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = ?
          AND tu.is_obsolete = 0
        ''',
        [projectLanguageId],
      );

      if (result.isEmpty) {
        return ProjectStatistics.empty();
      }

      final row = result.first;
      return ProjectStatistics(
        translatedCount: (row['translated_count'] as int?) ?? 0,
        pendingCount: (row['pending_count'] as int?) ?? 0,
        validatedCount: (row['validated_count'] as int?) ?? 0,
        errorCount: (row['error_count'] as int?) ?? 0,
      );
    });
  }

  /// Get global statistics across all projects for the dashboard.
  ///
  /// Counts unique translation units and their translation status.
  /// Word count is approximated by counting spaces + 1 in translated texts.
  Future<Result<GlobalStatistics, TWMTDatabaseException>>
      getGlobalStatistics() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT
          COUNT(DISTINCT tu.id) as total_units,
          COUNT(DISTINCT CASE
            WHEN tv.translated_text IS NOT NULL AND tv.translated_text != ''
            THEN tu.id
          END) as translated_units,
          COALESCE(SUM(
            CASE
              WHEN tv.translated_text IS NOT NULL AND tv.translated_text != ''
              THEN LENGTH(tv.translated_text) - LENGTH(REPLACE(tv.translated_text, ' ', '')) + 1
              ELSE 0
            END
          ), 0) as total_words
        FROM translation_units tu
        LEFT JOIN $tableName tv ON tv.unit_id = tu.id
        WHERE tu.is_obsolete = 0
        ''',
      );

      if (result.isEmpty) {
        return GlobalStatistics.empty();
      }

      final row = result.first;
      final totalUnits = (row['total_units'] as int?) ?? 0;
      final translatedUnits = (row['translated_units'] as int?) ?? 0;
      final pendingUnits = totalUnits - translatedUnits;
      final totalWords = (row['total_words'] as int?) ?? 0;

      return GlobalStatistics(
        totalUnits: totalUnits,
        translatedUnits: translatedUnits,
        pendingUnits: pendingUnits,
        totalTranslatedWords: totalWords,
      );
    });
  }
}
