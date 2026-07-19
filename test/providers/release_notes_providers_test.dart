import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:twmt/features/release_notes/services/release_notes_service.dart';
import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/providers/release_notes_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

class MockReleaseNotesService extends Mock implements ReleaseNotesService {}

GitHubRelease _release({String tag = 'v1.2.3'}) => GitHubRelease(
      tagName: tag,
      name: 'Release $tag',
      body: 'notes',
      isDraft: false,
      isPrerelease: false,
      publishedAt: DateTime(2024, 1, 1),
      htmlUrl: 'https://example.com/$tag',
      assets: const [],
    );

void main() {
  // PackageInfo.fromPlatform() is called directly inside checkReleaseNotes();
  // seed the static mock singleton so it resolves to a fixed version.
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'twmt',
      packageName: 'com.github.slavyk82.twmt',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('ReleaseNotesState', () {
    test('defaults are neutral', () {
      const state = ReleaseNotesState();
      expect(state.isChecking, isFalse);
      expect(state.releaseToShow, isNull);
      expect(state.hasBeenDismissed, isFalse);
      expect(state.shouldShowDialog, isFalse);
    });

    test('shouldShowDialog is true only when idle, has a release, not dismissed',
        () {
      final state = ReleaseNotesState(releaseToShow: _release());
      expect(state.shouldShowDialog, isTrue);

      expect(state.copyWith(isChecking: true).shouldShowDialog, isFalse);
      expect(state.copyWith(hasBeenDismissed: true).shouldShowDialog, isFalse);
    });

    test('copyWith clearRelease nulls the release', () {
      final state = ReleaseNotesState(releaseToShow: _release());
      final cleared = state.copyWith(clearRelease: true);
      expect(cleared.releaseToShow, isNull);
    });

    test('copyWith preserves unspecified fields', () {
      final state = ReleaseNotesState(
        isChecking: true,
        releaseToShow: _release(),
      );
      final next = state.copyWith(isChecking: false);
      expect(next.isChecking, isFalse);
      expect(next.releaseToShow, isNotNull);
      expect(next.hasBeenDismissed, isFalse);
    });
  });

  group('ReleaseNotesChecker', () {
    late MockReleaseNotesService mockService;
    late ProviderContainer container;

    setUp(() {
      mockService = MockReleaseNotesService();
      container = ProviderContainer(overrides: [
        releaseNotesServiceProvider.overrideWithValue(mockService),
      ]);
    });

    tearDown(() => container.dispose());

    test('build returns a neutral state', () {
      final state = container.read(releaseNotesCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.releaseToShow, isNull);
      expect(state.hasBeenDismissed, isFalse);
    });

    test('checkReleaseNotes surfaces a release the service returns', () async {
      final release = _release();
      when(() => mockService.checkShouldShowReleaseNotes(any()))
          .thenAnswer((_) async => release);

      await container
          .read(releaseNotesCheckerProvider.notifier)
          .checkReleaseNotes();

      final state = container.read(releaseNotesCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.releaseToShow, same(release));
      expect(state.shouldShowDialog, isTrue);
      verify(() => mockService.checkShouldShowReleaseNotes('1.2.3')).called(1);
    });

    test('checkReleaseNotes clears the release when the service returns null',
        () async {
      when(() => mockService.checkShouldShowReleaseNotes(any()))
          .thenAnswer((_) async => null);

      await container
          .read(releaseNotesCheckerProvider.notifier)
          .checkReleaseNotes();

      final state = container.read(releaseNotesCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.releaseToShow, isNull);
      expect(state.shouldShowDialog, isFalse);
    });

    test('checkReleaseNotes fails silently when the service throws', () async {
      when(() => mockService.checkShouldShowReleaseNotes(any()))
          .thenThrow(Exception('github unreachable'));

      await container
          .read(releaseNotesCheckerProvider.notifier)
          .checkReleaseNotes();

      final state = container.read(releaseNotesCheckerProvider);
      expect(state.isChecking, isFalse);
      expect(state.releaseToShow, isNull);
    });

    test('dismissReleaseNotes marks the version seen and clears the release',
        () async {
      final release = _release();
      when(() => mockService.checkShouldShowReleaseNotes(any()))
          .thenAnswer((_) async => release);
      when(() => mockService.markVersionAsSeen(any()))
          .thenAnswer((_) async {});

      final notifier = container.read(releaseNotesCheckerProvider.notifier);
      await notifier.checkReleaseNotes();
      expect(container.read(releaseNotesCheckerProvider).releaseToShow,
          isNotNull);

      await notifier.dismissReleaseNotes();

      final state = container.read(releaseNotesCheckerProvider);
      expect(state.hasBeenDismissed, isTrue);
      expect(state.releaseToShow, isNull);
      expect(state.shouldShowDialog, isFalse);
      verify(() => mockService.markVersionAsSeen('1.2.3')).called(1);
    });

    test('dismissReleaseNotes without a pending release does not call the service',
        () async {
      await container
          .read(releaseNotesCheckerProvider.notifier)
          .dismissReleaseNotes();

      final state = container.read(releaseNotesCheckerProvider);
      expect(state.hasBeenDismissed, isTrue);
      verifyNever(() => mockService.markVersionAsSeen(any()));
    });
  });
}
