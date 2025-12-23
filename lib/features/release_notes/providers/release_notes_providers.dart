import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/domain/github_release.dart';
import '../../../services/service_locator.dart';
import '../services/release_notes_service.dart';

part 'release_notes_providers.g.dart';

/// Provider for the release notes service.
@Riverpod(keepAlive: true)
ReleaseNotesService releaseNotesService(Ref ref) {
  return ServiceLocator.get<ReleaseNotesService>();
}

/// State for the release notes check.
class ReleaseNotesState {
  final bool isChecking;
  final GitHubRelease? releaseToShow;
  final bool hasBeenDismissed;

  const ReleaseNotesState({
    this.isChecking = false,
    this.releaseToShow,
    this.hasBeenDismissed = false,
  });

  ReleaseNotesState copyWith({
    bool? isChecking,
    GitHubRelease? releaseToShow,
    bool? hasBeenDismissed,
    bool clearRelease = false,
  }) {
    return ReleaseNotesState(
      isChecking: isChecking ?? this.isChecking,
      releaseToShow: clearRelease ? null : (releaseToShow ?? this.releaseToShow),
      hasBeenDismissed: hasBeenDismissed ?? this.hasBeenDismissed,
    );
  }

  /// Whether the release notes dialog should be shown.
  bool get shouldShowDialog =>
      !isChecking && releaseToShow != null && !hasBeenDismissed;
}

/// Notifier for checking and managing release notes display.
@Riverpod(keepAlive: true)
class ReleaseNotesChecker extends _$ReleaseNotesChecker {
  @override
  ReleaseNotesState build() {
    return const ReleaseNotesState();
  }

  /// Check if release notes should be shown for the current app version.
  Future<void> checkReleaseNotes() async {
    state = state.copyWith(isChecking: true);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!ref.mounted) return;

      final currentVersion = packageInfo.version;

      final service = ref.read(releaseNotesServiceProvider);
      final release = await service.checkShouldShowReleaseNotes(currentVersion);
      if (!ref.mounted) return;

      state = state.copyWith(
        isChecking: false,
        releaseToShow: release,
        clearRelease: release == null,
      );
    } catch (e) {
      // Fail silently - don't interrupt app startup for release notes
      if (ref.mounted) {
        state = state.copyWith(isChecking: false);
      }
    }
  }

  /// Dismiss the release notes dialog and mark the version as seen.
  Future<void> dismissReleaseNotes() async {
    final release = state.releaseToShow;
    if (release != null) {
      final service = ref.read(releaseNotesServiceProvider);
      await service.markVersionAsSeen(release.version);
      if (!ref.mounted) return;
    }
    state = state.copyWith(hasBeenDismissed: true, clearRelease: true);
  }
}
