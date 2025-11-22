import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_info.dart';

/// Service interface for mod update tracking and management.
///
/// Provides methods to check for mod updates from Steam Workshop,
/// track version changes, and manage translation preservation during updates.
abstract class IModUpdateService {
  /// Check all mods for available updates.
  ///
  /// Queries Steam Workshop for all projects with Steam Workshop IDs
  /// and compares their update timestamps with the current mod versions.
  ///
  /// Returns:
  /// - [Ok] with list of [ModUpdateInfo] for all projects
  /// - [Err] with [ServiceException] if the check fails
  ///
  /// Projects without updates will still be included with hasUpdate=false.
  Future<Result<List<ModUpdateInfo>, ServiceException>> checkAllModsForUpdates();

  /// Check a specific mod for updates.
  ///
  /// Queries Steam Workshop for the project's mod and compares the
  /// update timestamp with the current version.
  ///
  /// Parameters:
  /// - [projectId]: The project ID to check for updates
  ///
  /// Returns:
  /// - [Ok] with [ModUpdateInfo] for the project
  /// - [Err] with [ServiceException] if the check fails or project not found
  Future<Result<ModUpdateInfo, ServiceException>> checkModForUpdate({
    required String projectId,
  });

  /// Track a mod update by creating a new version.
  ///
  /// Creates a new mod_versions entry for the detected update and preserves
  /// validated translations from the previous version.
  ///
  /// Parameters:
  /// - [projectId]: The project ID to update
  /// - [newVersionString]: Version string for the new version
  ///
  /// Returns:
  /// - [Ok] with void on success
  /// - [Err] with [ServiceException] if the update tracking fails
  ///
  /// This operation:
  /// 1. Creates a new mod_versions row
  /// 2. Marks the new version as current
  /// 3. Updates project.source_mod_updated timestamp
  Future<Result<void, ServiceException>> trackModUpdate({
    required String projectId,
    required String newVersionString,
  });

  /// Get all pending updates.
  ///
  /// Returns a list of projects that have updates available but haven't
  /// been tracked yet (where Steam update timestamp is newer than the
  /// current version's timestamp).
  ///
  /// Returns:
  /// - [Ok] with list of [ModUpdateInfo] for projects with pending updates
  /// - [Err] with [ServiceException] if the query fails
  Future<Result<List<ModUpdateInfo>, ServiceException>> getPendingUpdates();
}
