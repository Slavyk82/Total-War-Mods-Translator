import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_base.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_validation.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart' as batch;
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

const _projectId = 'project-1';
const _languageId = 'language-fr';
const _versionId = 'version-a';
const _issuesJson =
    '[{"rule":"markup","severity":"warning","message":"tag mismatch"}]';

const _flaggedVersion = TranslationVersion(
  id: _versionId,
  unitId: 'unit-a',
  projectLanguageId: 'plang-1',
  translatedText: 'Bonjour',
  status: TranslationVersionStatus.needsReview,
  validationIssues: _issuesJson,
  createdAt: 0,
  updatedAt: 0,
);

const _issue = batch.ValidationIssue(
  unitKey: 'greeting',
  unitId: 'unit-a',
  versionId: _versionId,
  severity: batch.ValidationSeverity.warning,
  issueType: 'markup',
  description: 'tag mismatch',
  sourceText: 'Hello',
  translatedText: 'Bonjour',
);

/// Minimal actions object composing only the validation mixin under test.
/// Avoids importing TranslationEditorActions, whose transitive app_router
/// import would pull the entire app into the test compile graph.
class _ValidationActions with EditorActionsBase, EditorActionsValidation {
  _ValidationActions({required this.ref, required this.context});

  @override
  final WidgetRef ref;

  @override
  final BuildContext context;

  @override
  String get projectId => _projectId;

  @override
  String get languageId => _languageId;
}

/// Harness widget that builds a [_ValidationActions] from the live
/// `WidgetRef` + `BuildContext` pair, mirroring handle_validate_test.dart.
class _ActionsHarness extends ConsumerStatefulWidget {
  const _ActionsHarness({super.key});

  @override
  ConsumerState<_ActionsHarness> createState() => _ActionsHarnessState();
}

class _ActionsHarnessState extends ConsumerState<_ActionsHarness> {
  _ValidationActions buildActions() =>
      _ValidationActions(ref: ref, context: context);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_flaggedVersion);
  });

  late _MockVersionRepository versionRepo;

  setUp(() {
    versionRepo = _MockVersionRepository();
    when(() => versionRepo.getById(_versionId)).thenAnswer(
      (_) async =>
          const Ok<TranslationVersion, TWMTDatabaseException>(_flaggedVersion),
    );
    when(() => versionRepo.update(any())).thenAnswer(
      (invocation) async => Ok<TranslationVersion, TWMTDatabaseException>(
        invocation.positionalArguments.first as TranslationVersion,
      ),
    );
  });

  Future<GlobalKey<_ActionsHarnessState>> pumpHarness(
    WidgetTester tester,
  ) async {
    final harnessKey = GlobalKey<_ActionsHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: _ActionsHarness(key: harnessKey)),
        ),
      ),
    );
    await tester.pump();
    return harnessKey;
  }

  TranslationVersion capturedUpdate() =>
      verify(() => versionRepo.update(captureAny())).captured.single
          as TranslationVersion;

  testWidgets(
    'handleAcceptTranslation clears validation issues on the persisted version',
    (tester) async {
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!
          .buildActions()
          .handleAcceptTranslation(_issue);
      await tester.pump();

      final persisted = capturedUpdate();
      expect(persisted.status, TranslationVersionStatus.translated);
      expect(
        persisted.validationIssues,
        isNull,
        reason: 'Accepting a translation despite issues must clear the '
            'dismissed issues — copyWith(validationIssues: null) is a no-op, '
            'the clearValidationIssues flag must be used',
      );
      expect(persisted.isReadyForUse, isTrue);
    },
  );

  testWidgets(
    'handleEditTranslation clears validation issues on the persisted version',
    (tester) async {
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!
          .buildActions()
          .handleEditTranslation(_issue, 'Bonjour corrige');
      await tester.pump();

      final persisted = capturedUpdate();
      expect(persisted.status, TranslationVersionStatus.translated);
      expect(persisted.translatedText, 'Bonjour corrige');
      expect(persisted.isManuallyEdited, isTrue);
      expect(
        persisted.validationIssues,
        isNull,
        reason: 'Manually correcting a flagged translation must clear its '
            'stale validation issues',
      );
    },
  );
}
