import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../repositories/mod_version_repository.dart';
import '../../services/database/database_service.dart';
import '../shared/logging_service.dart';
import 'i_change_detection_service.dart';
import 'i_file_service.dart';
import 'models/change_detection_result.dart';
import 'models/file_change.dart';

/// Implementation of change detection service.
///
/// Detects when mod files are updated by comparing file hashes,
/// marks affected translations as obsolete, and generates detailed
/// change reports between mod versions.
class ChangeDetectionServiceImpl implements IChangeDetectionService {
  final IFileService _fileService;
  final ModVersionRepository _modVersionRepository;
  final LoggingService _logger;

  /// Create a new change detection service.
  ///
  /// Dependencies:
  /// - [fileService]: Service for file operations and hash calculation
  /// - [modVersionRepository]: Repository for mod version data
  /// - [logger]: Optional logging service (defaults to singleton instance)
  ChangeDetectionServiceImpl({
    required IFileService fileService,
    required ModVersionRepository modVersionRepository,
    LoggingService? logger,
  })  : _fileService = fileService,
        _modVersionRepository = modVersionRepository,
        _logger = logger ?? LoggingService.instance;

  @override
  Future<Result<bool, ServiceException>> hasFileChanged({
    required String filePath,
    required String previousHash,
  }) async {
    try {
      _logger.debug('Checking if file has changed', {
        'filePath': filePath,
        'previousHash': previousHash,
      });

      // Calculate current hash
      final hashResult = await _fileService.calculateFileHash(
        filePath: filePath,
      );

      if (hashResult.isErr) {
        final error = hashResult.error;
        _logger.error('Failed to calculate file hash', error);
        return Err(ServiceException(
          'Failed to calculate file hash: ${error.message}',
          error: error,
        ));
      }

      final currentHash = hashResult.value;
      final hasChanged = currentHash != previousHash;

      _logger.debug('File change check result', {
        'hasChanged': hasChanged,
        'currentHash': currentHash,
        'previousHash': previousHash,
      });

      return Ok(hasChanged);
    } catch (e, stackTrace) {
      _logger.error('Unexpected error checking file changes', e, stackTrace);
      return Err(ServiceException(
        'Unexpected error checking file changes: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<ChangeDetectionResult, ServiceException>> detectChanges({
    required String modId,
    required String filePath,
  }) async {
    try {
      _logger.info('Detecting changes for mod', {
        'modId': modId,
        'filePath': filePath,
      });

      // Get current version from database
      final currentVersionResult = await _modVersionRepository.getCurrent(modId);

      // Calculate current file hash
      final hashResult = await _fileService.calculateFileHash(
        filePath: filePath,
      );

      if (hashResult.isErr) {
        final error = hashResult.error;
        _logger.error('Failed to calculate file hash', error);
        return Err(ServiceException(
          'Failed to calculate file hash: ${error.message}',
          error: error,
        ));
      }

      final currentHash = hashResult.value;
      final detectedAt = DateTime.now();

      // If no current version exists, this is a new file
      if (currentVersionResult.isErr) {
        _logger.info('No previous version found, treating as new file');
        return Ok(ChangeDetectionResult.newFile(
          hash: currentHash,
          detectedAt: detectedAt,
          affectedFiles: [],
        ));
      }

      final currentVersion = currentVersionResult.value;

      // For now, we'll use the version string as a proxy for hash
      // In a real implementation, we'd store the hash in mod_versions
      // or in a separate table
      final oldHash = currentVersion.versionString;
      final hasChanged = currentHash != oldHash;

      if (hasChanged) {
        _logger.info('File has changed', {
          'oldHash': oldHash,
          'newHash': currentHash,
        });

        return Ok(ChangeDetectionResult.changed(
          oldHash: oldHash,
          newHash: currentHash,
          detectedAt: detectedAt,
          affectedFiles: [],
        ));
      } else {
        _logger.debug('No changes detected');
        return Ok(ChangeDetectionResult.noChange(
          hash: currentHash,
          detectedAt: detectedAt,
        ));
      }
    } catch (e, stackTrace) {
      _logger.error('Unexpected error detecting changes', e, stackTrace);
      return Err(ServiceException(
        'Unexpected error detecting changes: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<void, ServiceException>> markTranslationsObsolete({
    required String modId,
    String? versionId,
  }) async {
    try {
      _logger.info('Marking translations as obsolete', {
        'modId': modId,
        'versionId': versionId,
      });

      final database = DatabaseService.database;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Use transaction for atomicity
      await database.transaction((txn) async {
        if (versionId != null) {
          // Mark units from specific version
          await txn.rawUpdate(
            '''
            UPDATE translation_units
            SET is_obsolete = 1, updated_at = ?
            WHERE project_id = ?
              AND id IN (
                SELECT DISTINCT tu.id
                FROM translation_units tu
                INNER JOIN mod_version_changes mvc ON mvc.unit_key = tu.key
                WHERE mvc.version_id = ?
              )
            ''',
            [now, modId, versionId],
          );
        } else {
          // Mark all units for the project
          await txn.rawUpdate(
            '''
            UPDATE translation_units
            SET is_obsolete = 1, updated_at = ?
            WHERE project_id = ?
            ''',
            [now, modId],
          );
        }
      });

      _logger.info('Successfully marked translations as obsolete');
      return const Ok(null);
    } on TWMTDatabaseException catch (e) {
      _logger.error('Database error marking translations obsolete', e);
      return Err(e);
    } catch (e, stackTrace) {
      _logger.error(
        'Unexpected error marking translations obsolete',
        e,
        stackTrace,
      );
      return Err(ServiceException(
        'Unexpected error marking translations obsolete: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<FileChange>, ServiceException>> generateChangeReport({
    required String modId,
    required String oldVersionId,
    required String newVersionId,
  }) async {
    try {
      _logger.info('Generating change report', {
        'modId': modId,
        'oldVersionId': oldVersionId,
        'newVersionId': newVersionId,
      });

      // Get both versions to verify they exist
      final oldVersionResult = await _modVersionRepository.getById(oldVersionId);
      if (oldVersionResult.isErr) {
        return Err(ServiceException(
          'Old version not found: $oldVersionId',
          error: oldVersionResult.error,
        ));
      }

      final newVersionResult = await _modVersionRepository.getById(newVersionId);
      if (newVersionResult.isErr) {
        return Err(ServiceException(
          'New version not found: $newVersionId',
          error: newVersionResult.error,
        ));
      }

      // Query mod_version_changes for the new version
      final database = DatabaseService.database;
      final changes = await database.query(
        'mod_version_changes',
        where: 'version_id = ?',
        whereArgs: [newVersionId],
        orderBy: 'unit_key ASC',
      );

      // Convert to FileChange objects
      final fileChanges = <FileChange>[];
      for (final change in changes) {
        final changeType = change['change_type'] as String;
        final unitKey = change['unit_key'] as String;
        final oldText = change['old_source_text'] as String?;
        final newText = change['new_source_text'] as String?;
        final detectedAtUnix = change['detected_at'] as int;
        final detectedAt = DateTime.fromMillisecondsSinceEpoch(
          detectedAtUnix * 1000,
        );

        final fileChange = switch (changeType) {
          'added' => FileChange.added(
              filePath: unitKey,
              newHash: newText?.hashCode.toString() ?? '',
              detectedAt: detectedAt,
            ),
          'modified' => FileChange.modified(
              filePath: unitKey,
              oldHash: oldText?.hashCode.toString() ?? '',
              newHash: newText?.hashCode.toString() ?? '',
              detectedAt: detectedAt,
            ),
          'deleted' => FileChange.deleted(
              filePath: unitKey,
              oldHash: oldText?.hashCode.toString() ?? '',
              detectedAt: detectedAt,
            ),
          _ => throw TWMTDatabaseException(
              'Invalid change type: $changeType',
            ),
        };

        fileChanges.add(fileChange);
      }

      _logger.info('Generated change report', {
        'changeCount': fileChanges.length,
      });

      return Ok(fileChanges);
    } on TWMTDatabaseException catch (e) {
      _logger.error('Database error generating change report', e);
      return Err(e);
    } catch (e, stackTrace) {
      _logger.error(
        'Unexpected error generating change report',
        e,
        stackTrace,
      );
      return Err(ServiceException(
        'Unexpected error generating change report: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }
}
