import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import 'models/change_detection_result.dart';
import 'models/file_change.dart';

/// Service interface for detecting changes in mod files.
///
/// Provides methods to detect when mod files have been updated by comparing
/// file hashes, marking affected translations as obsolete, and generating
/// detailed change reports.
abstract class IChangeDetectionService {
  /// Check if a file has changed by comparing its current hash with a previous hash.
  ///
  /// Parameters:
  /// - [filePath]: Path to the file to check
  /// - [previousHash]: Previously stored hash to compare against
  ///
  /// Returns [Ok] with true if file has changed, false otherwise.
  /// Returns [Err] if file cannot be accessed or hash calculation fails.
  Future<Result<bool, ServiceException>> hasFileChanged({
    required String filePath,
    required String previousHash,
  });

  /// Detect changes in a mod file and return detailed change information.
  ///
  /// This method:
  /// 1. Retrieves the current mod version from the database
  /// 2. Calculates the current file hash
  /// 3. Compares with stored hash from mod_versions table
  /// 4. Returns detailed change detection result
  ///
  /// Parameters:
  /// - [modId]: Project ID of the mod to check
  /// - [filePath]: Path to the mod file (.pack file)
  ///
  /// Returns [Ok] with [ChangeDetectionResult] containing change details.
  /// Returns [Err] if file access fails or database operation fails.
  Future<Result<ChangeDetectionResult, ServiceException>> detectChanges({
    required String modId,
    required String filePath,
  });

  /// Mark translations as obsolete when source mod changes.
  ///
  /// This method uses a database transaction to:
  /// 1. Mark all translation_units for the project as obsolete
  /// 2. Or optionally mark only units from a specific version
  ///
  /// Parameters:
  /// - [modId]: Project ID of the mod
  /// - [versionId]: Optional specific version ID to mark obsolete.
  ///   If null, marks all units for the project.
  ///
  /// Returns [Ok] on success.
  /// Returns [Err] if database operation fails.
  Future<Result<void, ServiceException>> markTranslationsObsolete({
    required String modId,
    String? versionId,
  });

  /// Generate a detailed change report between two mod versions.
  ///
  /// This method:
  /// 1. Retrieves version records from mod_versions
  /// 2. Queries mod_version_changes for detailed changes
  /// 3. Returns list of FileChange objects representing all changes
  ///
  /// Parameters:
  /// - [modId]: Project ID of the mod
  /// - [oldVersionId]: ID of the old version
  /// - [newVersionId]: ID of the new version
  ///
  /// Returns [Ok] with list of [FileChange] objects.
  /// Returns [Err] if versions not found or database operation fails.
  Future<Result<List<FileChange>, ServiceException>> generateChangeReport({
    required String modId,
    required String oldVersionId,
    required String newVersionId,
  });
}
