import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';
import 'package:twmt/features/pack_compilation/providers/compilation_conflict_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';

class MockTranslationUnitRepository extends Mock
    implements TranslationUnitRepository {}

/// Builds a translation-unit map row in the shape the
/// [CompilationConflictService] expects from
/// `getUnitsForKeysAcrossProjects`.
Map<String, dynamic> unitRow({
  required String key,
  required String projectId,
  required String projectName,
  required String unitId,
  required String sourceText,
  String? translatedText,
  String? status,
  int isManuallyEdited = 0,
  int? versionUpdatedAt,
  String? sourceLocFile,
  String? projectMetadata,
}) {
  return <String, dynamic>{
    'key': key,
    'project_id': projectId,
    'project_name': projectName,
    'unit_id': unitId,
    'source_text': sourceText,
    'translated_text': translatedText,
    'status': status,
    'is_manually_edited': isManuallyEdited,
    'version_updated_at': versionUpdatedAt,
    'source_loc_file': sourceLocFile,
    'project_metadata': projectMetadata,
  };
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  late MockTranslationUnitRepository mockRepo;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        translationUnitRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    mockRepo = MockTranslationUnitRepository();
  });

  void stubDuplicateKeys(List<String> keys) {
    when(() => mockRepo.findDuplicateKeysAcrossProjects(
          projectIds: any(named: 'projectIds'),
        )).thenAnswer((_) async => Ok(keys));
  }

  void stubUnits(List<Map<String, dynamic>> units) {
    when(() => mockRepo.getUnitsForKeysAcrossProjects(
          projectIds: any(named: 'projectIds'),
          keys: any(named: 'keys'),
          languageId: any(named: 'languageId'),
        )).thenAnswer((_) async => Ok(units));
  }

  group('compilationConflictServiceProvider', () {
    test('builds a service reading the translation-unit repository', () {
      final container = makeContainer();
      final service = container.read(compilationConflictServiceProvider);
      expect(service, isNotNull);
    });
  });

  group('CompilationConflictAnalysis.analyze', () {
    test('initial state is AsyncData(null)', () {
      final container = makeContainer();
      final state = container.read(compilationConflictAnalysisProvider);
      expect(state, const AsyncData<ConflictAnalysisResult?>(null));
    });

    test('fewer than 2 projects yields an empty (no-conflict) result',
        () async {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1'], languageId: 'fr');

      final state = container.read(compilationConflictAnalysisProvider);
      final analysis = state.asData!.value!;
      expect(analysis.hasConflicts, isFalse);
      expect(analysis.languageId, 'fr');
      expect(analysis.analyzedProjectIds, ['p1']);
      // Single-project path short-circuits before touching the repo.
      verifyNever(() => mockRepo.findDuplicateKeysAcrossProjects(
          projectIds: any(named: 'projectIds')));
    });

    test('no duplicate keys yields an empty result', () async {
      stubDuplicateKeys(const []);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      final analysis =
          container.read(compilationConflictAnalysisProvider).asData!.value!;
      expect(analysis.hasConflicts, isFalse);
      verifyNever(() => mockRepo.getUnitsForKeysAcrossProjects(
            projectIds: any(named: 'projectIds'),
            keys: any(named: 'keys'),
            languageId: any(named: 'languageId'),
          ));
    });

    test('key collision (different source) produces a conflict', () async {
      stubDuplicateKeys(['shared_key']);
      stubUnits([
        unitRow(
          key: 'shared_key',
          projectId: 'p1',
          projectName: 'Project One',
          unitId: 'u1',
          sourceText: 'Hello',
          translatedText: 'Bonjour',
        ),
        unitRow(
          key: 'shared_key',
          projectId: 'p2',
          projectName: 'Project Two',
          unitId: 'u2',
          sourceText: 'Goodbye',
          translatedText: 'Au revoir',
        ),
      ]);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      final analysis =
          container.read(compilationConflictAnalysisProvider).asData!.value!;
      expect(analysis.hasConflicts, isTrue);
      expect(analysis.conflicts, hasLength(1));
      final conflict = analysis.conflicts.single;
      expect(conflict.key, 'shared_key');
      expect(conflict.conflictType,
          CompilationConflictType.keyCollisionDifferentSource);
      expect(conflict.canAutoResolve, isFalse);
      expect(analysis.summary.keyCollisionCount, 1);
    });

    test('same source with differing translations is a translation conflict',
        () async {
      stubDuplicateKeys(['k']);
      stubUnits([
        unitRow(
          key: 'k',
          projectId: 'p1',
          projectName: 'P1',
          unitId: 'u1',
          sourceText: 'Same',
          translatedText: 'TransA',
        ),
        unitRow(
          key: 'k',
          projectId: 'p2',
          projectName: 'P2',
          unitId: 'u2',
          sourceText: 'Same',
          translatedText: 'TransB',
        ),
      ]);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      final analysis =
          container.read(compilationConflictAnalysisProvider).asData!.value!;
      expect(analysis.conflicts.single.conflictType,
          CompilationConflictType.translationConflict);
      expect(analysis.summary.translationConflictCount, 1);
    });

    test('same source with identical/empty translations is not a conflict',
        () async {
      stubDuplicateKeys(['k']);
      stubUnits([
        unitRow(
          key: 'k',
          projectId: 'p1',
          projectName: 'P1',
          unitId: 'u1',
          sourceText: 'Same',
          translatedText: 'Trans',
        ),
        unitRow(
          key: 'k',
          projectId: 'p2',
          projectName: 'P2',
          unitId: 'u2',
          sourceText: 'Same',
          translatedText: '', // empty -> auto-mergeable
        ),
      ]);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      final analysis =
          container.read(compilationConflictAnalysisProvider).asData!.value!;
      expect(analysis.hasConflicts, isFalse);
    });

    test('Err from findDuplicateKeys sets error state', () async {
      when(() => mockRepo.findDuplicateKeysAcrossProjects(
                projectIds: any(named: 'projectIds'),
              ))
          .thenAnswer(
              (_) async => const Err(TWMTDatabaseException('boom')));
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      final state = container.read(compilationConflictAnalysisProvider);
      expect(state.hasError, isTrue);
    });

    test('Err from getUnitsForKeys sets error state', () async {
      stubDuplicateKeys(['k']);
      when(() => mockRepo.getUnitsForKeysAcrossProjects(
            projectIds: any(named: 'projectIds'),
            keys: any(named: 'keys'),
            languageId: any(named: 'languageId'),
          )).thenAnswer(
          (_) async => const Err(TWMTDatabaseException('load failed')));
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      expect(
        container.read(compilationConflictAnalysisProvider).hasError,
        isTrue,
      );
    });

    test('thrown exception is captured as Err -> error state', () async {
      when(() => mockRepo.findDuplicateKeysAcrossProjects(
            projectIds: any(named: 'projectIds'),
          )).thenThrow(Exception('explode'));
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      expect(
        container.read(compilationConflictAnalysisProvider).hasError,
        isTrue,
      );
    });

    test('clear() resets to AsyncData(null)', () async {
      stubDuplicateKeys(const []);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');
      expect(
        container.read(compilationConflictAnalysisProvider).asData!.value,
        isNotNull,
      );

      notifier.clear();
      expect(
        container.read(compilationConflictAnalysisProvider).asData!.value,
        isNull,
      );
    });

    test('updateWithResolutions is a no-op when there is no analysis data',
        () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      notifier.updateWithResolutions(const CompilationConflictResolutions());

      // Still the initial null-data state.
      expect(
        container.read(compilationConflictAnalysisProvider).asData!.value,
        isNull,
      );
    });

    test('updateWithResolutions applies resolutions to current analysis',
        () async {
      stubDuplicateKeys(['shared_key']);
      stubUnits([
        unitRow(
          key: 'shared_key',
          projectId: 'p1',
          projectName: 'P1',
          unitId: 'u1',
          sourceText: 'Hello',
          translatedText: 'Bonjour',
        ),
        unitRow(
          key: 'shared_key',
          projectId: 'p2',
          projectName: 'P2',
          unitId: 'u2',
          sourceText: 'Goodbye',
          translatedText: 'Au revoir',
        ),
      ]);
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictAnalysisProvider.notifier);

      await notifier.analyze(projectIds: ['p1', 'p2'], languageId: 'fr');
      final conflictId =
          container.read(compilationConflictAnalysisProvider).asData!.value!
              .conflicts
              .single
              .id;

      final resolutions = const CompilationConflictResolutions()
          .setResolution(conflictId, CompilationConflictResolution.useFirst,
              'p1');
      notifier.updateWithResolutions(resolutions);

      final updated =
          container.read(compilationConflictAnalysisProvider).asData!.value!;
      expect(updated.conflicts.single.isResolved, isTrue);
      expect(updated.conflicts.single.resolution,
          CompilationConflictResolution.useFirst);
      expect(updated.summary.resolvedCount, 1);
    });
  });

  group('CompilationConflictResolutionsState', () {
    test('initial state is empty', () {
      final container = makeContainer();
      final resolutions =
          container.read(compilationConflictResolutionsStateProvider);
      expect(resolutions.resolutions, isEmpty);
    });

    test('setResolution then getResolution / isResolved', () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictResolutionsStateProvider.notifier);

      notifier.setResolution(
          'c1', CompilationConflictResolution.useSecond, 'p2');

      expect(notifier.getResolution('c1'),
          CompilationConflictResolution.useSecond);
      expect(notifier.isResolved('c1'), isTrue);
      expect(
        container
            .read(compilationConflictResolutionsStateProvider)
            .getResolutionProjectId('c1'),
        'p2',
      );
    });

    test('overwriting a resolution replaces the prior value', () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictResolutionsStateProvider.notifier);

      notifier.setResolution(
          'c1', CompilationConflictResolution.useFirst, 'p1');
      notifier.setResolution('c1', CompilationConflictResolution.skip, null);

      expect(
          notifier.getResolution('c1'), CompilationConflictResolution.skip);
    });

    test('getResolution for unknown id returns null', () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictResolutionsStateProvider.notifier);

      expect(notifier.getResolution('missing'), isNull);
      expect(notifier.isResolved('missing'), isFalse);
    });

    test('setDefaultResolution resolves all conflicts', () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictResolutionsStateProvider.notifier);

      notifier.setDefaultResolution(
          CompilationConflictResolution.useFirst, 'p1');

      // Any id is now considered resolved via the default.
      expect(notifier.isResolved('any-id'), isTrue);
      expect(notifier.getResolution('any-id'),
          CompilationConflictResolution.useFirst);
    });

    test('clear() resets resolutions to empty', () {
      final container = makeContainer();
      final notifier =
          container.read(compilationConflictResolutionsStateProvider.notifier);

      notifier.setResolution(
          'c1', CompilationConflictResolution.useFirst, 'p1');
      notifier.clear();

      expect(notifier.isResolved('c1'), isFalse);
      expect(
        container.read(compilationConflictResolutionsStateProvider).resolutions,
        isEmpty,
      );
    });
  });

  group('derived providers', () {
    Future<ProviderContainer> analyzedContainer({
      required List<Map<String, dynamic>> units,
      List<String> keys = const ['shared_key'],
    }) async {
      stubDuplicateKeys(keys);
      stubUnits(units);
      final container = makeContainer();
      await container
          .read(compilationConflictAnalysisProvider.notifier)
          .analyze(projectIds: ['p1', 'p2'], languageId: 'fr');
      return container;
    }

    List<Map<String, dynamic>> keyCollisionUnits() => [
          unitRow(
            key: 'shared_key',
            projectId: 'p1',
            projectName: 'Project One',
            unitId: 'u1',
            sourceText: 'Hello',
            translatedText: 'Bonjour',
          ),
          unitRow(
            key: 'shared_key',
            projectId: 'p2',
            projectName: 'Project Two',
            unitId: 'u2',
            sourceText: 'Goodbye',
            translatedText: 'Au revoir',
          ),
        ];

    test('with no analysis: permissive / zero defaults', () {
      final container = makeContainer();
      expect(container.read(canProceedWithCompilationProvider), isTrue);
      expect(container.read(unresolvedConflictCountProvider), 0);
      expect(container.read(conflictsNeedingResolutionProvider), isEmpty);
      expect(container.read(isAnalyzingConflictsProvider), isFalse);
      expect(container.read(hasConflictsProvider), isFalse);
      expect(container.read(conflictSummaryProvider), isNull);
      expect(container.read(conflictingProjectsProvider), isEmpty);
      expect(container.read(hasRealConflictsProvider), isFalse);
    });

    test('unresolved manual conflict blocks compilation', () async {
      final container =
          await analyzedContainer(units: keyCollisionUnits());

      expect(container.read(hasConflictsProvider), isTrue);
      expect(container.read(canProceedWithCompilationProvider), isFalse);
      expect(container.read(unresolvedConflictCountProvider), 1);
      expect(container.read(conflictsNeedingResolutionProvider), hasLength(1));
      expect(container.read(conflictSummaryProvider), isNotNull);

      final conflictingProjects =
          container.read(conflictingProjectsProvider);
      expect(conflictingProjects, hasLength(2));
      expect(container.read(hasRealConflictsProvider), isTrue);
      // Sorted by count descending; both have count 1 here.
      expect(
        conflictingProjects.map((p) => p.projectId).toSet(),
        {'p1', 'p2'},
      );
      expect(
        conflictingProjects.firstWhere((p) => p.projectId == 'p1').projectName,
        'Project One',
      );
    });

    test('resolving the conflict allows compilation to proceed', () async {
      final container =
          await analyzedContainer(units: keyCollisionUnits());

      final conflictId = container
          .read(compilationConflictAnalysisProvider)
          .asData!
          .value!
          .conflicts
          .single
          .id;

      container
          .read(compilationConflictResolutionsStateProvider.notifier)
          .setResolution(
              conflictId, CompilationConflictResolution.useFirst, 'p1');

      expect(container.read(canProceedWithCompilationProvider), isTrue);
      expect(container.read(unresolvedConflictCountProvider), 0);
      expect(container.read(conflictsNeedingResolutionProvider), isEmpty);
    });

    test('loading branch: derived providers report conservative values',
        () async {
      stubDuplicateKeys(['shared_key']);
      stubUnits(keyCollisionUnits());
      final container = makeContainer();

      // Kick off analyze but do NOT await: state is AsyncLoading while the
      // repository future is still pending, exercising the loading branches.
      final pending = container
          .read(compilationConflictAnalysisProvider.notifier)
          .analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      expect(container.read(isAnalyzingConflictsProvider), isTrue);
      expect(container.read(canProceedWithCompilationProvider), isFalse);
      expect(container.read(unresolvedConflictCountProvider), 0);
      expect(container.read(conflictsNeedingResolutionProvider), isEmpty);
      expect(container.read(hasConflictsProvider), isFalse);
      expect(container.read(conflictingProjectsProvider), isEmpty);

      await pending;
    });

    test('error branch: derived providers report conservative values',
        () async {
      when(() => mockRepo.findDuplicateKeysAcrossProjects(
            projectIds: any(named: 'projectIds'),
          )).thenAnswer(
          (_) async => const Err(TWMTDatabaseException('boom')));
      final container = makeContainer();
      await container
          .read(compilationConflictAnalysisProvider.notifier)
          .analyze(projectIds: ['p1', 'p2'], languageId: 'fr');

      expect(container.read(compilationConflictAnalysisProvider).hasError,
          isTrue);
      expect(container.read(canProceedWithCompilationProvider), isFalse);
      expect(container.read(unresolvedConflictCountProvider), 0);
      expect(container.read(conflictsNeedingResolutionProvider), isEmpty);
      expect(container.read(hasConflictsProvider), isFalse);
      expect(container.read(conflictingProjectsProvider), isEmpty);
    });
  });
}
