import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/release_notes/services/release_notes_service.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/updates/app_update_service.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockAppUpdateService extends Mock implements AppUpdateService {}

GitHubRelease _release(String tagName) => GitHubRelease(
      tagName: tagName,
      name: 'Release $tagName',
      body: 'notes',
      isDraft: false,
      isPrerelease: false,
      publishedAt: DateTime(2026, 1, 1),
      htmlUrl: 'https://example.com/$tagName',
      assets: const [],
    );

void main() {
  late _MockSettingsService settings;
  late _MockAppUpdateService updates;
  late ReleaseNotesService service;

  setUp(() {
    settings = _MockSettingsService();
    updates = _MockAppUpdateService();
    service = ReleaseNotesService(
      settingsService: settings,
      updateService: updates,
    );

    // setString is fire-and-forget in the service; default it to success.
    when(() => settings.setString(any(), any()))
        .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  });

  group('checkShouldShowReleaseNotes', () {
    test('returns null and does not hit GitHub when version is unchanged',
        () async {
      when(() => settings.getString(ReleaseNotesService.lastSeenVersionKey))
          .thenAnswer((_) async => '1.2.3');

      final result = await service.checkShouldShowReleaseNotes('1.2.3');

      expect(result, isNull);
      verifyNever(() => updates.getLatestRelease());
      verifyNever(() => settings.setString(any(), any()));
    });

    test('on first run stores current version and returns null', () async {
      when(() => settings.getString(ReleaseNotesService.lastSeenVersionKey))
          .thenAnswer((_) async => '');

      final result = await service.checkShouldShowReleaseNotes('1.2.3');

      expect(result, isNull);
      verify(() => settings.setString(
          ReleaseNotesService.lastSeenVersionKey, '1.2.3')).called(1);
      verifyNever(() => updates.getLatestRelease());
    });

    test('returns the release when a new version matches the GitHub release',
        () async {
      when(() => settings.getString(ReleaseNotesService.lastSeenVersionKey))
          .thenAnswer((_) async => '1.2.2');
      when(() => updates.getLatestRelease())
          .thenAnswer((_) async => Ok(_release('v1.2.3')));

      final result = await service.checkShouldShowReleaseNotes('1.2.3');

      expect(result, isNotNull);
      expect(result!.version, '1.2.3');
      // A shown release must not be marked seen here (the dialog flow does that).
      verifyNever(() => settings.setString(any(), any()));
    });

    test(
        'returns null and marks current version seen when GitHub release '
        'does not match the installed build', () async {
      when(() => settings.getString(ReleaseNotesService.lastSeenVersionKey))
          .thenAnswer((_) async => '1.2.2');
      when(() => updates.getLatestRelease())
          .thenAnswer((_) async => Ok(_release('v1.3.0')));

      final result = await service.checkShouldShowReleaseNotes('1.2.3');

      expect(result, isNull);
      verify(() => settings.setString(
          ReleaseNotesService.lastSeenVersionKey, '1.2.3')).called(1);
    });

    test('returns null and does not mark seen when the GitHub fetch errors',
        () async {
      when(() => settings.getString(ReleaseNotesService.lastSeenVersionKey))
          .thenAnswer((_) async => '1.2.2');
      when(() => updates.getLatestRelease()).thenAnswer(
          (_) async => const Err(ServiceException('network down')));

      final result = await service.checkShouldShowReleaseNotes('1.2.3');

      expect(result, isNull);
      verifyNever(() => settings.setString(any(), any()));
    });
  });

  group('markVersionAsSeen', () {
    test('persists the version under the last-seen key', () async {
      await service.markVersionAsSeen('9.9.9');

      verify(() => settings.setString(
          ReleaseNotesService.lastSeenVersionKey, '9.9.9')).called(1);
    });
  });
}
