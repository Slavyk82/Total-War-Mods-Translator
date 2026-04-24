import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_actions.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

/// Test subclass that captures `createAndStartBatch` invocations instead
/// of executing the production navigation/orchestration path. This lets the
/// test assert that the new flow really triggers a follow-up retranslation
/// with TM bypass without needing a live LLM, batch repo, or progress
/// screen.
class _CapturingActions extends TranslationEditorActions {
  _CapturingActions({
    required super.ref,
    required super.context,
    required super.projectId,
    required super.languageId,
  });

  final List<({List<String> unitIds, bool forceSkipTM})> capturedBatches = [];

  @override
  Future<void> createAndStartBatch(List<String> unitIds,
      {bool forceSkipTM = false}) async {
    capturedBatches.add((unitIds: List.of(unitIds), forceSkipTM: forceSkipTM));
  }
}

class _ActionsHarness extends ConsumerStatefulWidget {
  const _ActionsHarness({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  final String projectId;
  final String languageId;

  @override
  ConsumerState<_ActionsHarness> createState() => _ActionsHarnessState();
}

class _ActionsHarnessState extends ConsumerState<_ActionsHarness> {
  _CapturingActions buildActions() {
    return _CapturingActions(
      ref: ref,
      context: context,
      projectId: widget.projectId,
      languageId: widget.languageId,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

TranslationRow _row({
  required String unitId,
  required String versionId,
  required String key,
  required String source,
  required String translated,
  TranslationVersionStatus status = TranslationVersionStatus.needsReview,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return TranslationRow(
    unit: TranslationUnit(
      id: unitId,
      projectId: 'project-1',
      key: key,
      sourceText: source,
      createdAt: now,
      updatedAt: now,
    ),
    version: TranslationVersion(
      id: versionId,
      unitId: unitId,
      projectLanguageId: 'plang-1',
      translatedText: translated,
      status: status,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  const projectId = 'project-1';
  const languageId = 'language-fr';
  const projectLanguageId = 'plang-1';

  late _MockProjectLanguageRepository projectLanguageRepo;
  late _MockVersionRepository versionRepo;

  setUp(() {
    projectLanguageRepo = _MockProjectLanguageRepository();
    versionRepo = _MockVersionRepository();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
      (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([
        ProjectLanguage(
          id: projectLanguageId,
          projectId: projectId,
          languageId: languageId,
          createdAt: now,
          updatedAt: now,
        ),
      ]),
    );

    when(() => versionRepo.rejectBatch(any())).thenAnswer(
      (_) async => const Ok<int, TWMTDatabaseException>(0),
    );
  });

  Future<_CapturingActions> pumpAndBuildActions(WidgetTester tester) async {
    final harnessKey = GlobalKey<_ActionsHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          projectLanguageRepositoryProvider.overrideWithValue(
            projectLanguageRepo,
          ),
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: _ActionsHarness(
              key: harnessKey,
              projectId: projectId,
              languageId: languageId,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return harnessKey.currentState!.buildActions();
  }

  group('handleBulkRetranslateNeedsReview', () {
    testWidgets(
        'clears the selected versions then triggers a retranslate batch with '
        'forceSkipTM=true so the bad TM entry is bypassed',
        (tester) async {
      final actions = await pumpAndBuildActions(tester);

      final rows = [
        _row(
          unitId: 'unit-a',
          versionId: 'version-a',
          key: 'k.a',
          source: 'Hello',
          translated: 'wrong A',
        ),
        _row(
          unitId: 'unit-b',
          versionId: 'version-b',
          key: 'k.b',
          source: 'World',
          translated: 'wrong B',
        ),
      ];

      await actions.handleBulkRetranslateNeedsReview(rows);

      // 1. The reject (clear) ran on the selected versions.
      final captured =
          verify(() => versionRepo.rejectBatch(captureAny())).captured;
      expect(captured, hasLength(1));
      expect(
        (captured.single as List).cast<String>().toSet(),
        equals({'version-a', 'version-b'}),
      );

      // 2. A retranslation batch was started for the same units, with TM
      //    bypass forced — the whole point of this flow.
      expect(actions.capturedBatches, hasLength(1));
      final batch = actions.capturedBatches.single;
      expect(batch.unitIds.toSet(), equals({'unit-a', 'unit-b'}));
      expect(batch.forceSkipTM, isTrue);
    });

    testWidgets(
        'does not trigger a retranslation when the rejectBatch call fails — '
        'avoids re-billing the LLM on stale or already-modified rows',
        (tester) async {
      when(() => versionRepo.rejectBatch(any())).thenAnswer(
        (_) async => const Err<int, TWMTDatabaseException>(
            TWMTDatabaseException('disk full')),
      );

      final actions = await pumpAndBuildActions(tester);

      await actions.handleBulkRetranslateNeedsReview([
        _row(
          unitId: 'unit-a',
          versionId: 'version-a',
          key: 'k.a',
          source: 'Hello',
          translated: 'wrong',
        ),
      ]);

      verify(() => versionRepo.rejectBatch(any())).called(1);
      expect(
        actions.capturedBatches,
        isEmpty,
        reason:
            'createAndStartBatch must NOT run when the clear step failed — '
            'otherwise the LLM is billed for rows whose review state never '
            'actually transitioned',
      );
    });

    testWidgets('does nothing when called with an empty row list',
        (tester) async {
      final actions = await pumpAndBuildActions(tester);

      await actions.handleBulkRetranslateNeedsReview([]);

      verifyNever(() => versionRepo.rejectBatch(any()));
      expect(actions.capturedBatches, isEmpty);
    });
  });
}
