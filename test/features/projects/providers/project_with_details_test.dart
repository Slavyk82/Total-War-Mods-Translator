// Pure-logic tests for [ProjectWithDetails] computed getters — the predicates
// that back the Projects screen quick filters.
//
// Regression guard: when a project is fully translated in every configured
// language and has no `needs_review` units left, [hasUpdates] must return
// false even if the persistent `has_mod_update_impact` flag was never cleared.
// Without this guard, bulk translate / bulk review workflows that don't route
// through the translation editor's initState (the only place the flag gets
// cleared today) leave projects stuck in the "Needs Update" filter.
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';

Project _project({
  String id = 'p1',
  bool hasModUpdateImpact = false,
}) {
  return Project(
    id: id,
    name: 'Project $id',
    gameInstallationId: 'install-1',
    createdAt: 0,
    updatedAt: 0,
    hasModUpdateImpact: hasModUpdateImpact,
  );
}

ProjectLanguageWithInfo _lang({
  String languageId = 'lang-fr',
  int totalUnits = 10,
  int translatedUnits = 10,
  int needsReviewUnits = 0,
}) {
  return ProjectLanguageWithInfo(
    projectLanguage: ProjectLanguage(
      id: 'pl-$languageId',
      projectId: 'p1',
      languageId: languageId,
      progressPercent: 0.0,
      createdAt: 0,
      updatedAt: 0,
    ),
    language: const Language(
      id: 'lang-fr',
      code: 'fr',
      name: 'French',
      nativeName: 'Français',
    ),
    totalUnits: totalUnits,
    translatedUnits: translatedUnits,
    needsReviewUnits: needsReviewUnits,
  );
}

void main() {
  group('ProjectWithDetails.hasUpdates', () {
    test('returns false when the flag is clear and no pending analysis', () {
      final details = ProjectWithDetails(
        project: _project(hasModUpdateImpact: false),
        languages: [_lang()],
      );
      expect(details.hasUpdates, isFalse);
    });

    test('returns true when analysis reports pending mod changes', () {
      final details = ProjectWithDetails(
        project: _project(hasModUpdateImpact: false),
        languages: [_lang()],
        updateAnalysis: const ModUpdateAnalysis(
          newUnitsCount: 3,
          removedUnitsCount: 0,
          modifiedUnitsCount: 0,
          totalPackUnits: 10,
          totalProjectUnits: 7,
        ),
      );
      expect(details.hasUpdates, isTrue);
    });

    test('returns true when flag is set and work remains (incomplete)', () {
      final details = ProjectWithDetails(
        project: _project(hasModUpdateImpact: true),
        languages: [_lang(translatedUnits: 5)], // 5/10 → not complete
      );
      expect(details.hasUpdates, isTrue);
    });

    test('returns true when flag is set and reviews are still pending', () {
      final details = ProjectWithDetails(
        project: _project(hasModUpdateImpact: true),
        languages: [_lang(needsReviewUnits: 2)],
      );
      expect(details.hasUpdates, isTrue);
    });

    test(
      'returns false when flag is set but project is fully translated '
      'with no reviews pending (bulk-translate / bulk-validate scenario)',
      () {
        final details = ProjectWithDetails(
          project: _project(hasModUpdateImpact: true),
          languages: [_lang(translatedUnits: 10, needsReviewUnits: 0)],
        );
        expect(
          details.hasUpdates,
          isFalse,
          reason:
              'When all configured languages are 100% translated and no '
              '`needs_review` units remain, the project must be excluded from '
              'the "Needs Update" filter regardless of the persistent flag.',
        );
      },
    );

    test(
      'returns true when flag is set, languages are complete, but the analysis '
      'still shows pending mod changes (new version detected)',
      () {
        final details = ProjectWithDetails(
          project: _project(hasModUpdateImpact: true),
          languages: [_lang(translatedUnits: 10, needsReviewUnits: 0)],
          updateAnalysis: const ModUpdateAnalysis(
            newUnitsCount: 2,
            removedUnitsCount: 0,
            modifiedUnitsCount: 0,
            totalPackUnits: 12,
            totalProjectUnits: 10,
          ),
        );
        expect(details.hasUpdates, isTrue);
      },
    );

    test('returns false when no languages are configured and no flag is set',
        () {
      final details = ProjectWithDetails(
        project: _project(hasModUpdateImpact: false),
        languages: const [],
      );
      expect(details.hasUpdates, isFalse);
    });
  });
}
