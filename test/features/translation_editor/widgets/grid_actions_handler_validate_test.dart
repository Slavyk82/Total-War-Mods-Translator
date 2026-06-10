import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/features/translation_editor/widgets/grid_actions_handler.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';
import '../../../helpers/test_bootstrap.dart';

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

const _issuesJson =
    '[{"rule":"markup","severity":"warning","message":"tag mismatch"}]';

TranslationRow _flaggedRow(String id) => TranslationRow(
      unit: TranslationUnit(
        id: id,
        projectId: 'p1',
        key: 'k_$id',
        sourceText: 's_$id',
        createdAt: 0,
        updatedAt: 0,
      ),
      version: TranslationVersion(
        id: 'v_$id',
        unitId: id,
        projectLanguageId: 'pl1',
        translatedText: 't_$id',
        status: TranslationVersionStatus.needsReview,
        validationIssues: _issuesJson,
        createdAt: 0,
        updatedAt: 0,
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(
      const TranslationVersion(
        id: 'fallback',
        unitId: 'fallback',
        projectLanguageId: 'fallback',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'handleValidate ("Mark as translated") clears validation issues '
      'on the persisted version', (tester) async {
    final versionRepo = _MockVersionRepository();
    when(() => versionRepo.update(any())).thenAnswer(
      (invocation) async => Ok<TranslationVersion, TWMTDatabaseException>(
        invocation.positionalArguments.first as TranslationVersion,
      ),
    );

    final dataSource = EditorDataSource(
      onCellEdit: (_, _) async {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
    dataSource.updateDataSource([_flaggedRow('u1')]);

    late BuildContext capturedContext;
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      createThemedTestableWidget(
        Consumer(
          builder: (context, ref, _) {
            capturedContext = context;
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
        ],
      ),
    );

    final handler = GridActionsHandler(
      context: capturedContext,
      ref: capturedRef,
      dataSource: dataSource,
      selectedRowIds: const <String>{'u1'},
      projectId: 'p1',
      languageId: 'fr',
      onCellEdit: (_, _) async {},
    );

    await handler.handleValidate();
    await tester.pump();

    final persisted = verify(() => versionRepo.update(captureAny()))
        .captured
        .single as TranslationVersion;

    expect(persisted.status, TranslationVersionStatus.translated);
    expect(
      persisted.validationIssues,
      isNull,
      reason: 'Manually approving a row must clear its stale validation '
          'issues — copyWith(validationIssues: null) is a no-op, the '
          'clearValidationIssues flag must be used',
    );
    expect(persisted.isReadyForUse, isTrue);

    // Let the success toast's auto-dismiss timer/animation run so no timers
    // leak past teardown.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
