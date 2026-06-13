import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/providers/app_version_provider.dart';
import 'package:twmt/providers/update_providers.dart';
import 'package:twmt/services/updates/app_update_service.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/dialogs/all_release_notes_dialog.dart';
import 'package:twmt/widgets/sidebar_update_checker.dart';

import '../helpers/test_helpers.dart';

class _MockAppUpdateService extends Mock implements AppUpdateService {}

/// Stub update-checker notifier returning a fixed [UpdateCheckState].
class _StubUpdateChecker extends UpdateChecker {
  _StubUpdateChecker(this._state);
  final UpdateCheckState _state;

  @override
  UpdateCheckState build() => _state;

  @override
  Future<void> checkForUpdates() async {}

  @override
  void dismissUpdate() {}
}

/// Stub downloader notifier returning a fixed [UpdateDownloadState].
class _StubUpdateDownloader extends UpdateDownloader {
  _StubUpdateDownloader(this._state);
  final UpdateDownloadState _state;

  @override
  UpdateDownloadState build() => _state;

  @override
  Future<void> downloadUpdate(GitHubRelease release) async {}

  @override
  Future<void> installUpdate() async {}
}

GitHubRelease _release({
  String tagName = 'v2.0.0',
  List<GitHubAsset> assets = const [],
}) {
  return GitHubRelease(
    tagName: tagName,
    name: 'Release $tagName',
    body: 'Notes',
    isDraft: false,
    isPrerelease: false,
    publishedAt: DateTime(2024, 1, 1),
    htmlUrl: 'https://example.com/release',
    assets: assets,
  );
}

const _installerAsset = GitHubAsset(
  name: 'TWMT-Setup.exe',
  browserDownloadUrl: 'https://example.com/setup.exe',
  size: 5 * 1024 * 1024,
  contentType: 'application/octet-stream',
  downloadCount: 0,
);

Widget _wrap(List<Override> overrides) {
  // The checker uses IconButton / FilledButton which require a Material
  // ancestor and a real Navigator (for the release-notes dialog), so wrap the
  // target in a Scaffold rather than the bare SizedBox helper.
  return createThemedTestableWidget(
    const Scaffold(body: SidebarUpdateChecker()),
    theme: AppTheme.atelierDarkTheme,
    screenSize: const Size(1200, 1600),
    overrides: overrides,
  );
}

/// Applies the standard 1200x1600 surface (dPR 1.0) used across the suite so
/// the sidebar footer column lays out without overflow, and resets it on
/// teardown.
void _setSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_release());
  });

  List<Override> baseOverrides({
    required UpdateCheckState check,
    UpdateDownloadState download = const UpdateDownloadState(),
    AppUpdateService? service,
    String version = '1.5.0',
  }) {
    return [
      appVersionProvider.overrideWith((ref) async => version),
      updateCheckerProvider.overrideWith(() => _StubUpdateChecker(check)),
      updateDownloaderProvider
          .overrideWith(() => _StubUpdateDownloader(download)),
      if (service != null)
        appUpdateServiceProvider.overrideWithValue(service),
    ];
  }

  testWidgets('renders version label from appVersionProvider', (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
      version: '9.9.9',
    )));
    await tester.pump();

    expect(find.textContaining('9.9.9'), findsOneWidget);
    // "What's new?" link is shown when not loading.
    expect(find.text("What's new?"), findsOneWidget);
  });

  testWidgets("hovering What's new? underlines the link", (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
    )));
    await tester.pump();

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text("What's new?")));
    await tester.pump();
    // Move away to exercise the onExit branch as well.
    await gesture.moveTo(Offset.zero);
    await tester.pump();

    expect(find.text("What's new?"), findsOneWidget);
  });

  testWidgets('initial state shows "Check for updates" button', (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
    )));
    await tester.pump();

    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('checking state shows spinner and disabled button',
      (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(isChecking: true),
    )));
    await tester.pump();

    expect(find.text('Checking...'), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNull);
  });

  testWidgets('up-to-date state shows "Up-to-date" label', (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: UpdateCheckState(lastChecked: DateTime(2024, 1, 1)),
    )));
    await tester.pump();

    expect(find.text('Up-to-date'), findsOneWidget);
  });

  testWidgets('tapping check button invokes checkForUpdates', (tester) async {
    var called = 0;
    final overrides = [
      appVersionProvider.overrideWith((ref) async => '1.0.0'),
      updateCheckerProvider.overrideWith(
        () => _RecordingUpdateChecker(onCheck: () => called++),
      ),
      updateDownloaderProvider
          .overrideWith(() => _StubUpdateDownloader(const UpdateDownloadState())),
    ];

    _setSurface(tester);
    await tester.pumpWidget(_wrap(overrides));
    await tester.pump();

    await tester.tap(find.text('Check for updates'));
    await tester.pump();

    expect(called, 1);
  });

  testWidgets('update-available state shows version and download button',
      (tester) async {
    final release = _release(tagName: 'v2.3.4', assets: [_installerAsset]);
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: UpdateCheckState(availableUpdate: release),
    )));
    await tester.pump();

    expect(find.text('v2.3.4 available'), findsOneWidget);
    // Download button shows formatted size (5.0 MB).
    expect(find.textContaining('Download'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsOneWidget);
    expect(find.text('View on GitHub'), findsOneWidget);
  });

  testWidgets('tapping download invokes downloadUpdate', (tester) async {
    GitHubRelease? downloaded;
    final release = _release(tagName: 'v2.3.4', assets: [_installerAsset]);
    final overrides = [
      appVersionProvider.overrideWith((ref) async => '1.0.0'),
      updateCheckerProvider.overrideWith(
        () => _StubUpdateChecker(UpdateCheckState(availableUpdate: release)),
      ),
      updateDownloaderProvider.overrideWith(
        () => _RecordingDownloader(onDownload: (r) => downloaded = r),
      ),
    ];

    _setSurface(tester);
    await tester.pumpWidget(_wrap(overrides));
    await tester.pump();

    await tester.tap(find.textContaining('Download'));
    await tester.pump();

    expect(downloaded, same(release));
  });

  testWidgets('tapping dismiss invokes dismissUpdate', (tester) async {
    var dismissed = 0;
    final release = _release(tagName: 'v2.0.0', assets: [_installerAsset]);
    final overrides = [
      appVersionProvider.overrideWith((ref) async => '1.0.0'),
      updateCheckerProvider.overrideWith(
        () => _RecordingUpdateChecker(
          initialState: UpdateCheckState(availableUpdate: release),
          onDismiss: () => dismissed++,
        ),
      ),
      updateDownloaderProvider
          .overrideWith(() => _StubUpdateDownloader(const UpdateDownloadState())),
    ];

    _setSurface(tester);
    await tester.pumpWidget(_wrap(overrides));
    await tester.pump();

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(dismissed, 1);
  });

  testWidgets('downloading state shows progress bar and percentage',
      (tester) async {
    final release = _release(tagName: 'v2.0.0', assets: [_installerAsset]);
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: UpdateCheckState(availableUpdate: release),
      download: const UpdateDownloadState(isDownloading: true, progress: 0.42),
    )));
    await tester.pump();

    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Downloading...'), findsOneWidget);
  });

  testWidgets('downloaded state shows install button and invokes installUpdate',
      (tester) async {
    var installed = 0;
    final release = _release(tagName: 'v2.0.0', assets: [_installerAsset]);
    final overrides = [
      appVersionProvider.overrideWith((ref) async => '1.0.0'),
      updateCheckerProvider.overrideWith(
        () => _StubUpdateChecker(UpdateCheckState(availableUpdate: release)),
      ),
      updateDownloaderProvider.overrideWith(
        () => _RecordingDownloader(
          initialState:
              const UpdateDownloadState(downloadedPath: 'C:/tmp/setup.exe'),
          onInstall: () => installed++,
        ),
      ),
    ];

    _setSurface(tester);
    await tester.pumpWidget(_wrap(overrides));
    await tester.pump();

    expect(find.text('Install & Restart'), findsOneWidget);
    await tester.tap(find.text('Install & Restart'));
    await tester.pump();

    expect(installed, 1);
  });

  testWidgets('download error renders error message', (tester) async {
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
      download: const UpdateDownloadState(error: 'Network exploded'),
    )));
    await tester.pump();

    expect(find.text('Network exploded'), findsOneWidget);
  });

  testWidgets('update available without installer hides download button',
      (tester) async {
    // No assets -> windowsInstaller returns an empty asset -> download button
    // branch is skipped, only "View on GitHub" remains.
    final release = _release(tagName: 'v2.0.0', assets: const []);
    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: UpdateCheckState(availableUpdate: release),
    )));
    await tester.pump();

    expect(find.text('View on GitHub'), findsOneWidget);
    expect(find.textContaining('Download'), findsNothing);
  });

  testWidgets("What's new? opens release notes dialog on success",
      (tester) async {
    final service = _MockAppUpdateService();
    when(() => service.getAllReleases()).thenAnswer(
      (_) async => Ok([_release(tagName: 'v1.3.0'), _release(tagName: 'v1.0.0')]),
    );

    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
      service: service,
    )));
    await tester.pump();

    await tester.tap(find.text("What's new?"));
    await tester.pump(); // start async load
    await tester.pump(); // resolve future + show dialog

    expect(find.byType(AllReleaseNotesDialog), findsOneWidget);
    verify(() => service.getAllReleases()).called(1);
  });

  testWidgets("What's new? shows error toast on failure", (tester) async {
    final service = _MockAppUpdateService();
    when(() => service.getAllReleases()).thenAnswer(
      (_) async => Err(const ServiceException('boom')),
    );

    _setSurface(tester);
    await tester.pumpWidget(_wrap(baseOverrides(
      check: const UpdateCheckState(),
      service: service,
    )));
    await tester.pump();

    await tester.tap(find.text("What's new?"));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Failed to load release notes'), findsOneWidget);

    // Drain the toast's auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
  });
}

/// Recording checker that captures check/dismiss invocations.
class _RecordingUpdateChecker extends UpdateChecker {
  _RecordingUpdateChecker({
    this.initialState = const UpdateCheckState(),
    this.onCheck,
    this.onDismiss,
  });

  final UpdateCheckState initialState;
  final void Function()? onCheck;
  final void Function()? onDismiss;

  @override
  UpdateCheckState build() => initialState;

  @override
  Future<void> checkForUpdates() async {
    onCheck?.call();
  }

  @override
  void dismissUpdate() {
    onDismiss?.call();
  }
}

/// Recording downloader that captures download/install invocations.
class _RecordingDownloader extends UpdateDownloader {
  _RecordingDownloader({
    this.initialState = const UpdateDownloadState(),
    this.onDownload,
    this.onInstall,
  });

  final UpdateDownloadState initialState;
  final void Function(GitHubRelease release)? onDownload;
  final void Function()? onInstall;

  @override
  UpdateDownloadState build() => initialState;

  @override
  Future<void> downloadUpdate(GitHubRelease release) async {
    onDownload?.call(release);
  }

  @override
  Future<void> installUpdate() async {
    onInstall?.call();
  }
}
