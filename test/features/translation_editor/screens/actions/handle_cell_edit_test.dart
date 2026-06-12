import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_base.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_cell_edit.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockHistoryService extends Mock implements IHistoryService {}

class _MockTmService extends Mock implements ITranslationMemoryService {}

/// Only `entryId` is read off the match by the production code, so a Fake
/// sidesteps building a full TmMatch (SimilarityBreakdown + ScoreWeights).
class _FakeTmMatch extends Fake implements TmMatch {
  @override
  String get entryId => 'tm-1';
}

const _projectId = 'project-1';
const _languageId = 'language-fr';
const _projectLanguageId = 'plang-1';
const _unitId = 'unit-a';
const _versionId = 'version-a';

const _projectLanguage = ProjectLanguage(
  id: _projectLanguageId,
  projectId: _projectId,
  languageId: _languageId,
  createdAt: 0,
  updatedAt: 0,
);

const _language = Language(
  id: _languageId,
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
);

const _unit = TranslationUnit(
  id: _unitId,
  projectId: _projectId,
  key: 'greeting',
  sourceText: 'Hello',
  createdAt: 0,
  updatedAt: 0,
);

TranslationVersion _version(String? text) => TranslationVersion(
      id: _versionId,
      unitId: _unitId,
      projectLanguageId: _projectLanguageId,
      translatedText: text,
      status: text == null || text.isEmpty
          ? TranslationVersionStatus.pending
          : TranslationVersionStatus.translated,
      createdAt: 0,
      updatedAt: 0,
    );

final _tmEntry = TranslationMemoryEntry(
  id: 'tm-1',
  sourceText: 'Hello',
  sourceHash: 'h',
  sourceLanguageId: 'en',
  targetLanguageId: 'fr',
  translatedText: 'Bonjour',
  createdAt: 0,
  lastUsedAt: 0,
  updatedAt: 0,
);

/// Minimal actions object composing only the cell-edit mixin under test,
/// mirroring handle_accept_translation_test.dart (avoids pulling app_router
/// into the compile graph via TranslationEditorActions).
class _CellEditActions with EditorActionsBase, EditorActionsCellEdit {
  _CellEditActions({required this.ref, required this.context});

  @override
  final WidgetRef ref;

  @override
  final BuildContext context;

  @override
  String get projectId => _projectId;

  @override
  String get languageId => _languageId;
}

class _ActionsHarness extends ConsumerStatefulWidget {
  const _ActionsHarness({super.key});

  @override
  ConsumerState<_ActionsHarness> createState() => _ActionsHarnessState();
}

class _ActionsHarnessState extends ConsumerState<_ActionsHarness> {
  _CellEditActions buildActions() =>
      _CellEditActions(ref: ref, context: context);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_version('fallback'));
  });

  late _MockVersionRepo versionRepo;
  late _MockUnitRepo unitRepo;
  late _MockProjectLanguageRepo projectLanguageRepo;
  late _MockLanguageRepo languageRepo;
  late _MockHistoryService historyService;
  late _MockTmService tmService;

  setUp(() {
    versionRepo = _MockVersionRepo();
    unitRepo = _MockUnitRepo();
    projectLanguageRepo = _MockProjectLanguageRepo();
    languageRepo = _MockLanguageRepo();
    historyService = _MockHistoryService();
    tmService = _MockTmService();

    when(() => projectLanguageRepo.getByProject(_projectId)).thenAnswer(
      (_) async => const Ok<List<ProjectLanguage>, TWMTDatabaseException>(
        [_projectLanguage],
      ),
    );
    when(() => projectLanguageRepo.getById(_projectLanguageId)).thenAnswer(
      (_) async =>
          const Ok<ProjectLanguage, TWMTDatabaseException>(_projectLanguage),
    );
    when(() => languageRepo.getById(_languageId)).thenAnswer(
      (_) async => const Ok<Language, TWMTDatabaseException>(_language),
    );
    when(() => unitRepo.getById(_unitId)).thenAnswer(
      (_) async => const Ok<TranslationUnit, TWMTDatabaseException>(_unit),
    );
    when(() => versionRepo.update(any())).thenAnswer(
      (invocation) async => Ok<TranslationVersion, TWMTDatabaseException>(
        invocation.positionalArguments.first as TranslationVersion,
      ),
    );
    when(() => historyService.recordChange(
          versionId: any(named: 'versionId'),
          translatedText: any(named: 'translatedText'),
          status: any(named: 'status'),
          changedBy: any(named: 'changedBy'),
          changeReason: any(named: 'changeReason'),
        )).thenAnswer(
      (_) async => const Ok<void, TWMTDatabaseException>(null),
    );
    when(() => tmService.addTranslation(
          sourceText: any(named: 'sourceText'),
          targetText: any(named: 'targetText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => Ok<TranslationMemoryEntry, TmAddException>(_tmEntry));
    when(() => tmService.incrementUsageCount(entryId: any(named: 'entryId')))
        .thenAnswer((_) async => Ok<TranslationMemoryEntry, TmServiceException>(_tmEntry));
  });

  void stubExistingVersion(String? translatedText) {
    when(() => versionRepo.getByUnitAndProjectLanguage(
          unitId: _unitId,
          projectLanguageId: _projectLanguageId,
        )).thenAnswer(
      (_) async => Ok<TranslationVersion, TWMTDatabaseException>(
        _version(translatedText),
      ),
    );
  }

  Future<GlobalKey<_ActionsHarnessState>> pumpHarness(
      WidgetTester tester) async {
    final harnessKey = GlobalKey<_ActionsHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          translationVersionRepositoryProvider.overrideWithValue(versionRepo),
          translationUnitRepositoryProvider.overrideWithValue(unitRepo),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          historyServiceProvider.overrideWithValue(historyService),
          translationMemoryServiceProvider.overrideWithValue(tmService),
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

  group('handleCellEdit', () {
    testWidgets('persists manual edit, records history and updates TM',
        (tester) async {
      stubExistingVersion('Old');
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleCellEdit(
            _unitId,
            'Bonjour',
          );
      await tester.pump();

      final persisted = capturedUpdate();
      expect(persisted.translatedText, 'Bonjour');
      expect(persisted.isManuallyEdited, isTrue);
      expect(persisted.status, TranslationVersionStatus.translated);

      verify(() => historyService.recordChange(
            versionId: _versionId,
            translatedText: 'Bonjour',
            status: 'translated',
            changedBy: 'user',
            changeReason: any(named: 'changeReason'),
          )).called(1);
      verify(() => tmService.addTranslation(
            sourceText: 'Hello',
            targetText: 'Bonjour',
            targetLanguageCode: 'fr',
          )).called(1);
    });

    testWidgets('normalizes escaped newlines before persisting',
        (tester) async {
      stubExistingVersion('Old');
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleCellEdit(
            _unitId,
            r'Line1\nLine2',
          );
      await tester.pump();

      expect(capturedUpdate().translatedText, 'Line1\nLine2');
    });

    testWidgets('is a no-op when the text is unchanged', (tester) async {
      stubExistingVersion('Bonjour');
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleCellEdit(
            _unitId,
            'Bonjour',
          );
      await tester.pump();

      verifyNever(() => versionRepo.update(any()));
      verifyNever(() => tmService.addTranslation(
            sourceText: any(named: 'sourceText'),
            targetText: any(named: 'targetText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          ));
    });

    testWidgets('clearing text sets pending status and skips TM update',
        (tester) async {
      stubExistingVersion('Bonjour');
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleCellEdit(_unitId, '');
      await tester.pump();

      expect(capturedUpdate().status, TranslationVersionStatus.pending);
      verifyNever(() => tmService.addTranslation(
            sourceText: any(named: 'sourceText'),
            targetText: any(named: 'targetText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          ));
    });
  });

  group('handleApplySuggestion', () {
    testWidgets('exact match marks tmExact, not manual, and bumps usage count',
        (tester) async {
      stubExistingVersion('Old');
      when(() => tmService.findExactMatch(
            sourceText: 'Hello',
            targetLanguageCode: 'fr',
          )).thenAnswer(
        (_) async => Ok<TmMatch?, TmLookupException>(_FakeTmMatch()),
      );
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleApplySuggestion(
            _unitId,
            'Bonjour',
            true,
          );
      await tester.pump();

      final persisted = capturedUpdate();
      expect(persisted.translatedText, 'Bonjour');
      expect(persisted.isManuallyEdited, isFalse);
      expect(persisted.translationSource, TranslationSource.tmExact);
      expect(persisted.status, TranslationVersionStatus.translated);

      verify(() => tmService.incrementUsageCount(entryId: 'tm-1')).called(1);
      verify(() => historyService.recordChange(
            versionId: _versionId,
            translatedText: 'Bonjour',
            status: 'translated',
            changedBy: 'tm_exact',
            changeReason: any(named: 'changeReason'),
          )).called(1);
    });

    testWidgets('fuzzy match marks tmFuzzy', (tester) async {
      stubExistingVersion('Old');
      when(() => tmService.findExactMatch(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer(
        (_) async => const Ok<TmMatch?, TmLookupException>(null),
      );
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleApplySuggestion(
            _unitId,
            'Bonjour',
            false,
          );
      await tester.pump();

      expect(capturedUpdate().translationSource, TranslationSource.tmFuzzy);
    });

    testWidgets('is a no-op when the suggestion equals the current text',
        (tester) async {
      stubExistingVersion('Bonjour');
      final harnessKey = await pumpHarness(tester);

      await harnessKey.currentState!.buildActions().handleApplySuggestion(
            _unitId,
            'Bonjour',
            true,
          );
      await tester.pump();

      verifyNever(() => versionRepo.update(any()));
    });
  });
}
