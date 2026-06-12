import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/providers/update_providers.dart';
import 'package:twmt/services/updates/app_update_service.dart';

class MockAppUpdateService extends Mock implements AppUpdateService {}

/// Spy notifier that records delegated checkForUpdates() calls without touching
/// the currentAppVersion/service chain (which doesn't resolve under fakeAsync).
class _SpyUpdateChecker extends UpdateChecker {
  int calls = 0;
  @override
  Future<void> checkForUpdates() async => calls++;
}

/// A non-empty release that exposes a `.exe` installer asset so
/// `windowsInstaller` resolves to a downloadable asset.
GitHubRelease _releaseWithInstaller() => GitHubRelease(
      tagName: 'v1.2.3',
      name: 'Release 1.2.3',
      body: 'notes',
      isDraft: false,
      isPrerelease: false,
      publishedAt: DateTime(2024, 1, 1),
      htmlUrl: 'https://example.com/release',
      assets: const [
        GitHubAsset(
          name: 'TWMT-installer.exe',
          browserDownloadUrl: 'https://example.com/TWMT-installer.exe',
          size: 1000,
          contentType: 'application/octet-stream',
          downloadCount: 0,
        ),
      ],
    );

/// A release whose only asset is not a recognised Windows installer, so
/// `windowsInstaller` returns the empty asset.
GitHubRelease _releaseWithoutInstaller() => GitHubRelease(
      tagName: 'v1.2.3',
      name: 'Release 1.2.3',
      body: 'notes',
      isDraft: false,
      isPrerelease: false,
      publishedAt: DateTime(2024, 1, 1),
      htmlUrl: 'https://example.com/release',
      assets: const [
        GitHubAsset(
          name: 'readme.txt',
          browserDownloadUrl: 'https://example.com/readme.txt',
          size: 1,
          contentType: 'text/plain',
          downloadCount: 0,
        ),
      ],
    );

void main() {
  setUpAll(() {
    // Required for any `any()` matcher on a non-primitive GitHubAsset argument
    // (downloadInstaller's first positional parameter).
    registerFallbackValue(const GitHubAsset.empty());
  });

  // ---------------------------------------------------------------------------
  // Plain model tests (no container required).
  // ---------------------------------------------------------------------------
  group('UpdateCheckState model', () {
    test('default constructor has neutral defaults', () {
      const state = UpdateCheckState();
      expect(state.isChecking, isFalse);
      expect(state.availableUpdate, isNull);
      expect(state.error, isNull);
      expect(state.lastChecked, isNull);
      expect(state.hasUpdate, isFalse);
    });

    test('hasUpdate is true when an availableUpdate is present', () {
      final state = UpdateCheckState(availableUpdate: _releaseWithInstaller());
      expect(state.hasUpdate, isTrue);
    });

    test('copyWith overrides only provided fields', () {
      const base = UpdateCheckState();
      final when = DateTime(2024, 2, 2);
      final next = base.copyWith(
        isChecking: true,
        error: 'boom',
        lastChecked: when,
      );
      expect(next.isChecking, isTrue);
      expect(next.error, 'boom');
      expect(next.lastChecked, when);
      expect(next.availableUpdate, isNull);
    });

    test('copyWith clearUpdate nulls the availableUpdate', () {
      final base = UpdateCheckState(availableUpdate: _releaseWithInstaller());
      final cleared = base.copyWith(clearUpdate: true);
      expect(cleared.availableUpdate, isNull);
      expect(cleared.hasUpdate, isFalse);
    });

    test('copyWith clearError nulls the error', () {
      const base = UpdateCheckState(error: 'boom');
      final cleared = base.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });
  });

  group('UpdateDownloadState model', () {
    test('default constructor has neutral defaults', () {
      const state = UpdateDownloadState();
      expect(state.isDownloading, isFalse);
      expect(state.progress, 0.0);
      expect(state.downloadedPath, isNull);
      expect(state.error, isNull);
    });

    test('copyWith overrides only provided fields', () {
      const base = UpdateDownloadState();
      final next = base.copyWith(
        isDownloading: true,
        progress: 0.5,
        downloadedPath: 'C:/tmp/x.exe',
      );
      expect(next.isDownloading, isTrue);
      expect(next.progress, 0.5);
      expect(next.downloadedPath, 'C:/tmp/x.exe');
      expect(next.error, isNull);
    });

    test('copyWith clearPath and clearError null the respective fields', () {
      const base = UpdateDownloadState(
        downloadedPath: 'C:/tmp/x.exe',
        error: 'boom',
      );
      final cleared = base.copyWith(clearPath: true, clearError: true);
      expect(cleared.downloadedPath, isNull);
      expect(cleared.error, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Bridge provider / service wiring.
  // ---------------------------------------------------------------------------
  group('appUpdateServiceProvider', () {
    test('can be overridden with a mock', () {
      final mock = MockAppUpdateService();
      final container = ProviderContainer(overrides: [
        appUpdateServiceProvider.overrideWithValue(mock),
      ]);
      addTearDown(container.dispose);

      expect(container.read(appUpdateServiceProvider), same(mock));
    });
  });

  group('currentAppVersionProvider', () {
    test('can be overridden directly with a fixed version', () async {
      final container = ProviderContainer(overrides: [
        currentAppVersionProvider.overrideWith((ref) async => '9.9.9'),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(currentAppVersionProvider.future), '9.9.9');
    });
  });

  // ---------------------------------------------------------------------------
  // UpdateChecker notifier.
  // ---------------------------------------------------------------------------
  group('UpdateChecker notifier', () {
    late MockAppUpdateService mockService;
    late ProviderContainer container;

    setUp(() {
      mockService = MockAppUpdateService();
      container = ProviderContainer(overrides: [
        appUpdateServiceProvider.overrideWithValue(mockService),
        currentAppVersionProvider.overrideWith((ref) async => '1.0.0'),
      ]);
    });

    tearDown(() => container.dispose());

    test('build() returns a neutral UpdateCheckState', () {
      final state = container.read(updateCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.availableUpdate, isNull);
      expect(state.error, isNull);
      expect(state.lastChecked, isNull);
    });

    test('checkForUpdates sets availableUpdate when service returns a release',
        () async {
      final release = _releaseWithInstaller();
      when(() => mockService.checkForUpdate(any())).thenAnswer(
        (_) async => Ok<GitHubRelease?, ServiceException>(release),
      );

      await container.read(updateCheckerProvider.notifier).checkForUpdates();

      final state = container.read(updateCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.availableUpdate, same(release));
      expect(state.hasUpdate, isTrue);
      expect(state.error, isNull);
      expect(state.lastChecked, isNotNull);
      verify(() => mockService.checkForUpdate('1.0.0')).called(1);
    });

    test('checkForUpdates clears availableUpdate when service returns null (up to date)',
        () async {
      when(() => mockService.checkForUpdate(any())).thenAnswer(
        (_) async => const Ok<GitHubRelease?, ServiceException>(null),
      );

      await container.read(updateCheckerProvider.notifier).checkForUpdates();

      final state = container.read(updateCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.availableUpdate, isNull);
      expect(state.hasUpdate, isFalse);
      expect(state.error, isNull);
      expect(state.lastChecked, isNotNull);
    });

    test('checkForUpdates records the error message when service returns Err',
        () async {
      when(() => mockService.checkForUpdate(any())).thenAnswer(
        (_) async => Err<GitHubRelease?, ServiceException>(
          const ServiceException('network down'),
        ),
      );

      await container.read(updateCheckerProvider.notifier).checkForUpdates();

      final state = container.read(updateCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.error, 'network down');
      expect(state.availableUpdate, isNull);
      expect(state.lastChecked, isNotNull);
    });

    test('checkForUpdates catches thrown exceptions into the error field',
        () async {
      when(() => mockService.checkForUpdate(any()))
          .thenThrow(Exception('boom'));

      await container.read(updateCheckerProvider.notifier).checkForUpdates();

      final state = container.read(updateCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.error, contains('Failed to check for updates'));
      expect(state.lastChecked, isNotNull);
    });

    test('dismissUpdate clears a previously available update', () async {
      final release = _releaseWithInstaller();
      when(() => mockService.checkForUpdate(any())).thenAnswer(
        (_) async => Ok<GitHubRelease?, ServiceException>(release),
      );

      final notifier = container.read(updateCheckerProvider.notifier);
      await notifier.checkForUpdates();
      expect(container.read(updateCheckerProvider).hasUpdate, isTrue);

      notifier.dismissUpdate();
      expect(container.read(updateCheckerProvider).hasUpdate, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // UpdateDownloader notifier.
  // ---------------------------------------------------------------------------
  group('UpdateDownloader notifier', () {
    late MockAppUpdateService mockService;
    late ProviderContainer container;

    setUp(() {
      mockService = MockAppUpdateService();
      container = ProviderContainer(overrides: [
        appUpdateServiceProvider.overrideWithValue(mockService),
      ]);
    });

    tearDown(() => container.dispose());

    test('build() returns a neutral UpdateDownloadState', () {
      final state = container.read(updateDownloaderProvider);
      expect(state.isDownloading, isFalse);
      expect(state.progress, 0.0);
      expect(state.downloadedPath, isNull);
      expect(state.error, isNull);
    });

    test('downloadUpdate errors out when the release has no Windows installer',
        () async {
      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithoutInstaller());

      final state = container.read(updateDownloaderProvider);
      expect(state.error, 'No Windows installer available');
      // Service must never be hit on the no-asset short-circuit.
      verifyNever(() => mockService.downloadInstaller(any(),
          onProgress: any(named: 'onProgress')));
    });

    test('downloadUpdate reports progress and the final path on success',
        () async {
      when(() => mockService.downloadInstaller(any(),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
        // Drive the progress callback so the progress branch is exercised.
        final onProgress = invocation.namedArguments[#onProgress]
            as void Function(double)?;
        onProgress?.call(0.25);
        onProgress?.call(0.75);
        return const Ok<String, ServiceException>('C:/tmp/TWMT/installer.exe');
      });

      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithInstaller());

      final state = container.read(updateDownloaderProvider);
      expect(state.isDownloading, isFalse);
      expect(state.progress, 1.0);
      expect(state.downloadedPath, 'C:/tmp/TWMT/installer.exe');
      expect(state.error, isNull);
    });

    test('downloadUpdate records the error message when the service returns Err',
        () async {
      when(() => mockService.downloadInstaller(any(),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => Err<String, ServiceException>(
                const ServiceException('disk full'),
              ));

      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithInstaller());

      final state = container.read(updateDownloaderProvider);
      expect(state.isDownloading, isFalse);
      expect(state.error, 'disk full');
      expect(state.downloadedPath, isNull);
    });

    test('downloadUpdate catches thrown exceptions into the error field',
        () async {
      when(() => mockService.downloadInstaller(any(),
              onProgress: any(named: 'onProgress')))
          .thenThrow(Exception('kaboom'));

      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithInstaller());

      final state = container.read(updateDownloaderProvider);
      expect(state.isDownloading, isFalse);
      expect(state.error, contains('Download failed'));
    });

    test('installUpdate errors out when nothing has been downloaded', () async {
      // No downloadedPath in state -> guard branch, service untouched.
      await container.read(updateDownloaderProvider.notifier).installUpdate();

      final state = container.read(updateDownloaderProvider);
      expect(state.error, 'No installer downloaded');
      verifyNever(() => mockService.launchInstaller(any()));
    });

    test('installUpdate records the error message when launch returns Err',
        () async {
      // Seed a downloaded path via a successful download first.
      when(() => mockService.downloadInstaller(any(),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async =>
              const Ok<String, ServiceException>('C:/tmp/TWMT/installer.exe'));
      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithInstaller());

      when(() => mockService.launchInstaller(any())).thenAnswer(
        (_) async =>
            Err<void, ServiceException>(const ServiceException('cannot exec')),
      );

      await container.read(updateDownloaderProvider.notifier).installUpdate();

      final state = container.read(updateDownloaderProvider);
      expect(state.error, 'cannot exec');
      verify(() => mockService.launchInstaller('C:/tmp/TWMT/installer.exe'))
          .called(1);
    });

    test('installUpdate catches thrown exceptions into the error field',
        () async {
      when(() => mockService.downloadInstaller(any(),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async =>
              const Ok<String, ServiceException>('C:/tmp/TWMT/installer.exe'));
      await container
          .read(updateDownloaderProvider.notifier)
          .downloadUpdate(_releaseWithInstaller());

      when(() => mockService.launchInstaller(any()))
          .thenThrow(Exception('exec blew up'));

      await container.read(updateDownloaderProvider.notifier).installUpdate();

      final state = container.read(updateDownloaderProvider);
      expect(state.error, contains('Failed to launch installer'));
    });

    test('reset returns the state to its neutral default', () async {
      when(() => mockService.downloadInstaller(any(),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async =>
              const Ok<String, ServiceException>('C:/tmp/TWMT/installer.exe'));
      final notifier = container.read(updateDownloaderProvider.notifier);
      await notifier.downloadUpdate(_releaseWithInstaller());
      expect(container.read(updateDownloaderProvider).downloadedPath, isNotNull);

      notifier.reset();
      final state = container.read(updateDownloaderProvider);
      expect(state.downloadedPath, isNull);
      expect(state.progress, 0.0);
      expect(state.isDownloading, isFalse);
      expect(state.error, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // autoUpdateCheck provider — delegates to UpdateChecker.checkForUpdates().
  // ---------------------------------------------------------------------------
  group('autoUpdateCheckProvider', () {
    test('delegates to UpdateChecker.checkForUpdates after the startup delay',
        () async {
      // The provider sleeps 5s before delegating. A spy notifier isolates the
      // delegation. We await the real delay (fakeAsync + Riverpod async builds
      // are flaky under parallel CPU load), with a generous timeout.
      final spy = _SpyUpdateChecker();
      final container = ProviderContainer(overrides: [
        updateCheckerProvider.overrideWith(() => spy),
      ]);
      addTearDown(container.dispose);

      await container.read(autoUpdateCheckProvider.future);

      expect(spy.calls, 1);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ---------------------------------------------------------------------------
  // cleanupOldInstallers provider — delegates to the service.
  // ---------------------------------------------------------------------------
  group('cleanupOldInstallersProvider', () {
    test('calls the service cleanup routine', () async {
      final mockService = MockAppUpdateService();
      // Production calls cleanupOldInstallers() with no arguments.
      when(() => mockService.cleanupOldInstallers())
          .thenAnswer((_) async {});

      final container = ProviderContainer(overrides: [
        appUpdateServiceProvider.overrideWithValue(mockService),
      ]);
      addTearDown(container.dispose);

      await container.read(cleanupOldInstallersProvider.future);

      verify(() => mockService.cleanupOldInstallers()).called(1);
    });

    test('swallows service errors silently (no throw, completes)', () async {
      final mockService = MockAppUpdateService();
      when(() => mockService.cleanupOldInstallers())
          .thenThrow(Exception('cleanup failed'));

      final container = ProviderContainer(overrides: [
        appUpdateServiceProvider.overrideWithValue(mockService),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container.read(cleanupOldInstallersProvider.future),
        completes,
      );
    });
  });
}
