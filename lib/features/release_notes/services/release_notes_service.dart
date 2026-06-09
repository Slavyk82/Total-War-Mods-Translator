import 'package:flutter/foundation.dart';

import '../../../models/domain/github_release.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/updates/app_update_service.dart';

/// Service for managing release notes display after app updates.
///
/// Checks if release notes should be shown by comparing the current app version
/// with the last seen version stored in settings.
class ReleaseNotesService {
  final SettingsService _settingsService;
  final AppUpdateService _updateService;

  /// Key used to store the last seen app version in settings.
  static const String lastSeenVersionKey = 'last_seen_app_version';

  ReleaseNotesService({
    required SettingsService settingsService,
    required AppUpdateService updateService,
  })  : _settingsService = settingsService,
        _updateService = updateService;

  /// Check if release notes should be shown for the current version.
  ///
  /// Returns the [GitHubRelease] if notes should be shown, null otherwise.
  ///
  /// Logic:
  /// 1. If first run ever (empty lastSeenVersion), store current version and return null
  /// 2. If same version as last seen, return null
  /// 3. If new version, fetch release from GitHub and return it if matching
  Future<GitHubRelease?> checkShouldShowReleaseNotes(String currentVersion) async {
    debugPrint('[ReleaseNotes] Checking for version: $currentVersion');

    // Get last seen version from settings
    final lastSeenVersion = await _settingsService.getString(lastSeenVersionKey);
    debugPrint('[ReleaseNotes] Last seen version: "$lastSeenVersion"');

    // If same version, no need to show
    if (lastSeenVersion == currentVersion) {
      debugPrint('[ReleaseNotes] Same version, skipping');
      return null;
    }

    // If first run ever (empty string), just store the version and don't show
    if (lastSeenVersion.isEmpty) {
      debugPrint('[ReleaseNotes] First run, storing version');
      await markVersionAsSeen(currentVersion);
      return null;
    }

    debugPrint('[ReleaseNotes] New version detected, fetching release from GitHub...');

    // Fetch current release info from GitHub
    final result = await _updateService.getLatestRelease();

    if (result.isErr) {
      debugPrint('[ReleaseNotes] GitHub API error: ${result.unwrapErr().message}');
      return null;
    }

    final release = result.unwrap();
    debugPrint('[ReleaseNotes] GitHub release version: ${release.version}');
    // Only show if the release version matches the current app version.
    // This ensures we show the correct release notes.
    if (release.version == currentVersion) {
      debugPrint('[ReleaseNotes] Versions match! Showing dialog');
      return release;
    }

    // Version mismatch (installed build is behind the latest GitHub release —
    // e.g. the user deferred an update). Mark the current build as seen so we
    // do not re-hit the GitHub API on every subsequent startup for the same
    // installed version. A genuinely new release will change [release.version]
    // and is handled by the update flow, while a future build matching its own
    // release notes will differ from the stored version and re-trigger this.
    debugPrint('[ReleaseNotes] Version mismatch: ${release.version} != $currentVersion');
    await markVersionAsSeen(currentVersion);
    return null;
  }

  /// Mark the given version as seen.
  ///
  /// After calling this, [checkShouldShowReleaseNotes] will return null
  /// for this version.
  Future<void> markVersionAsSeen(String version) async {
    await _settingsService.setString(lastSeenVersionKey, version);
  }
}
