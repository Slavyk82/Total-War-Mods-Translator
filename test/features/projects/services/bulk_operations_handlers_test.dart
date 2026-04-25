import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';

// ---------------------------------------------------------------------------
// Minimal fakes — each under 15 lines
// ---------------------------------------------------------------------------

class _FakeProject extends Fake implements Project {
  _FakeProject({required this.id, required this.name});
  @override
  final String id;
  @override
  final String name;
}

class _FakeLanguage extends Fake implements Language {
  _FakeLanguage(this.code);
  @override
  final String code;
}

class _FakeProjectLanguage extends Fake implements ProjectLanguage {
  _FakeProjectLanguage(this.id);
  @override
  final String id;
}

class _FakeLangInfo extends Fake implements ProjectLanguageWithInfo {
  _FakeLangInfo({
    required String projectLanguageId,
    required String languageCode,
    this.translatedUnits = 0,
    this.needsReviewUnits = 0,
  })  : language = _FakeLanguage(languageCode),
        projectLanguage = _FakeProjectLanguage(projectLanguageId);

  @override
  final Language language;
  @override
  final ProjectLanguage projectLanguage;
  @override
  final int translatedUnits;
  @override
  final int needsReviewUnits;
  @override
  final int totalUnits = 10;
}

class _FakeProjectWithDetails extends Fake implements ProjectWithDetails {
  _FakeProjectWithDetails({
    required this.project,
    required this.languages,
  });
  @override
  final Project project;
  @override
  final List<ProjectLanguageWithInfo> languages;
}

// ---------------------------------------------------------------------------
// Helper builders
// ---------------------------------------------------------------------------

/// A project that has NO language configured at all.
ProjectWithDetails _projectNoLanguage() {
  return _FakeProjectWithDetails(
    project: _FakeProject(id: 'p1', name: 'Mod A'),
    languages: const [],
  );
}

/// A project that has a 'de' language but NOT 'fr'.
ProjectWithDetails _projectWrongLanguage() {
  return _FakeProjectWithDetails(
    project: _FakeProject(id: 'p2', name: 'Mod B'),
    languages: [
      _FakeLangInfo(projectLanguageId: 'pl-de', languageCode: 'de'),
    ],
  );
}

/// A project that has 'fr' but with 0 translated and 0 needsReview units.
ProjectWithDetails _projectFrZeroStats() {
  return _FakeProjectWithDetails(
    project: _FakeProject(id: 'p3', name: 'Mod C'),
    languages: [
      _FakeLangInfo(
        projectLanguageId: 'pl-fr',
        languageCode: 'fr',
        translatedUnits: 0,
        needsReviewUnits: 0,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('runBulkTranslate', () {
    test('skips when project has no target language configured', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkTranslate(
            ref: ref,
            project: _projectNoLanguage(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when project has no matching target language', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkTranslate(
            ref: ref,
            project: _projectWrongLanguage(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test(
      'happy path: translates units and runs rescan',
      skip: 'Requires real DB/provider stack — integration test only',
      () async {},
    );
  });

  group('runBulkRescan', () {
    test('skips when project has no target language configured', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkRescan(
            ref: ref,
            project: _projectNoLanguage(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when 0 translated units for the target language', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkRescan(
            ref: ref,
            project: _projectFrZeroStats(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test(
      'happy path: runs headless rescan and returns flagged count',
      skip: 'Requires real DB/provider stack — integration test only',
      () async {},
    );
  });

  group('runBulkForceValidate', () {
    test('skips when project has no target language configured', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkForceValidate(
            ref: ref,
            project: _projectNoLanguage(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when 0 needsReview units for the target language', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkForceValidate(
            ref: ref,
            project: _projectFrZeroStats(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test(
      'happy path: accepts all needsReview versions and returns cleared count',
      skip: 'Requires real DB/provider stack — integration test only',
      () async {},
    );
  });

  group('runBulkGeneratePack', () {
    test('skips when project has no target language configured', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container.read(
        FutureProvider<ProjectOutcome>(
          (ref) => runBulkGeneratePack(
            ref: ref,
            project: _projectNoLanguage(),
            targetLanguageCode: 'fr',
          ),
        ).future,
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test(
      'happy path: calls exportToPack and returns entry/size summary',
      skip: 'Requires real DB/provider stack — integration test only',
      () async {},
    );
  });
}
