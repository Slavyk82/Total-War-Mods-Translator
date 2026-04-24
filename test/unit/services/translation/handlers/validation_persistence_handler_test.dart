import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart' hide ValidationException;
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart' as common;
import 'package:twmt/services/translation/models/validation_rule.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/translation/handlers/validation_persistence_handler.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/validation/validation_schema.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';

import '../../../../helpers/fakes/fake_logger.dart';

// Characterisation tests for ValidationPersistenceHandler.validateAndSave.
// Pinned behaviours:
// - Happy path: for each LLM translation, validation runs, the version is
//   upserted via versionRepository, history is recorded with changedBy tagged
//   'provider_<code>', and the source text is staged for the final batch TM
//   update (tmService.addTranslationsBatch runs exactly once at the end).
// - Validation issues (errors or warnings): the persisted version carries
//   status=needsReview and a non-null validationIssues JSON string; saving
//   still proceeds.
// - Persist failure (versionRepository.upsert returns Err): the handler
//   increments failCount, does NOT record history for that unit, and does
//   NOT stage the entry in the TM batch. No orphan history entries.
// - TM batch failure is non-fatal: tmService.addTranslationsBatch returning
//   Err is logged as a warning but does not throw and does not downgrade
//   already-successful persists.
// - History service throwing: caught and logged; the overall save still
//   reports success for that unit.

class _MockValidationService extends Mock implements IValidationService {}

class _MockTmService extends Mock implements ITranslationMemoryService {}

class _MockHistoryService extends Mock implements IHistoryService {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

// Silent logger fake — the handler logs heavily and we do not want noisy
// stubs for every info/debug/warning call.

class _FakeTranslationVersion extends Fake implements TranslationVersion {}

// --- Fixture helpers ---------------------------------------------------

const String _projectId = 'project-1';
const String _projectLanguageId = 'plang-1';
const String _batchId = 'batch-vp';

TranslationUnit _fakeUnit(String key, String source) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return TranslationUnit(
    id: 'unit-$key',
    projectId: _projectId,
    key: key,
    sourceText: source,
    createdAt: now,
    updatedAt: now,
  );
}

TranslationContext _fakeContext() {
  final now = DateTime.now();
  return TranslationContext(
    id: 'ctx-1',
    projectId: _projectId,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    modelId: 'claude-haiku-4.5',
    targetLanguage: 'fr',
    sourceLanguage: 'en',
    createdAt: now,
    updatedAt: now,
  );
}

TranslationProgress _initialProgress({int total = 0}) {
  return TranslationProgress(
    batchId: _batchId,
    status: TranslationProgressStatus.inProgress,
    totalUnits: total,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: TranslationPhase.initializing,
    tokensUsed: 0,
    tmReuseRate: 0.0,
    timestamp: DateTime.now(),
  );
}

// --- Test setup --------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTranslationVersion());
    registerFallbackValue(<({String sourceText, String targetText})>[]);
    registerFallbackValue(StackTrace.empty);
  });

  late _MockValidationService validation;
  late _MockTmService tmService;
  late _MockHistoryService historyService;
  late _MockVersionRepository versionRepository;
  late FakeLogger logger;
  late ValidationPersistenceHandler handler;

  // Captures every TranslationVersion the handler tries to persist. Lets each
  // test assert status, validationIssues, translationSource, etc.
  late List<TranslationVersion> persistedVersions;

  setUp(() {
    validation = _MockValidationService();
    tmService = _MockTmService();
    historyService = _MockHistoryService();
    versionRepository = _MockVersionRepository();
    logger = FakeLogger();
    persistedVersions = [];

    // Default validation: everything is valid, no errors, no warnings.
    when(() => validation.validateTranslation(
          sourceText: any(named: 'sourceText'),
          translatedText: any(named: 'translatedText'),
          key: any(named: 'key'),
          glossaryTerms: any(named: 'glossaryTerms'),
        )).thenAnswer((_) async =>
        Ok<common.ValidationResult, ValidationException>(
            common.ValidationResult.success()));

    // Default upsert: capture and return Ok.
    when(() => versionRepository.upsert(any())).thenAnswer((inv) async {
      final v = inv.positionalArguments[0] as TranslationVersion;
      persistedVersions.add(v);
      return Ok<TranslationVersion, TWMTDatabaseException>(v);
    });

    // Default history: Ok.
    when(() => historyService.recordChange(
          versionId: any(named: 'versionId'),
          translatedText: any(named: 'translatedText'),
          status: any(named: 'status'),
          changedBy: any(named: 'changedBy'),
          changeReason: any(named: 'changeReason'),
        )).thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

    // Default TM batch: Ok with count.
    when(() => tmService.addTranslationsBatch(
          translations: any(named: 'translations'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => const Ok<int, TmAddException>(0));

    handler = ValidationPersistenceHandler(
      validation: validation,
      tmService: tmService,
      historyService: historyService,
      versionRepository: versionRepository,
      logger: logger,
    );
  });

  Future<void> noopCheckPauseOrCancel(String batchId) async {}
  void noopProgressUpdate(String batchId, TranslationProgress progress) {}

  group('ValidationPersistenceHandler.validateAndSave', () {
    test(
        'happy path: validates each LLM translation, upserts the version, '
        'records history, and issues exactly one batched TM update at the end',
        () async {
      final units = [
        _fakeUnit('a', 'Hello'),
        _fakeUnit('b', 'World'),
      ];
      final translations = {
        'unit-a': 'Bonjour',
        'unit-b': 'Monde',
      };

      await handler.validateAndSave(
        translations: translations,
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // Validation ran once per translation.
      verify(() => validation.validateTranslation(
            sourceText: any(named: 'sourceText'),
            translatedText: any(named: 'translatedText'),
            key: any(named: 'key'),
            glossaryTerms: any(named: 'glossaryTerms'),
          )).called(2);

      // Both versions persisted as LLM-source, status=translated (clean).
      expect(persistedVersions, hasLength(2));
      expect(
        persistedVersions.map((v) => v.unitId).toSet(),
        equals({'unit-a', 'unit-b'}),
      );
      expect(
        persistedVersions.map((v) => v.translationSource).toSet(),
        equals({TranslationSource.llm}),
      );
      expect(
        persistedVersions.map((v) => v.status).toSet(),
        equals({TranslationVersionStatus.translated}),
      );
      // No validation issues for the happy path.
      expect(
        persistedVersions.every((v) => v.validationIssues == null),
        isTrue,
      );

      // History recorded once per persisted version with the provider tag.
      verify(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: any(named: 'translatedText'),
            status: any(named: 'status'),
            changedBy: 'provider_anthropic',
            changeReason: any(named: 'changeReason'),
          )).called(2);

      // TM update is batched ONCE at the end, not per-unit.
      final captured = verify(() => tmService.addTranslationsBatch(
            translations: captureAny(named: 'translations'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: 'fr',
          )).captured;
      expect(captured, hasLength(1));
      final batchEntries =
          captured.single as List<({String sourceText, String targetText})>;
      expect(batchEntries, hasLength(2));
      expect(
        batchEntries.map((e) => e.sourceText).toSet(),
        equals({'Hello', 'World'}),
      );
      expect(
        batchEntries.map((e) => e.targetText).toSet(),
        equals({'Bonjour', 'Monde'}),
      );
    });

    test(
        'validation warnings/errors: persisted version has status=needsReview '
        'and a non-null validationIssues payload; save still proceeds',
        () async {
      final units = [_fakeUnit('a', 'Hello {0}')];
      final translations = {'unit-a': 'Bonjour'};

      // Validator returns Ok but with errors + warnings populated.
      when(() => validation.validateTranslation(
            sourceText: any(named: 'sourceText'),
            translatedText: any(named: 'translatedText'),
            key: any(named: 'key'),
            glossaryTerms: any(named: 'glossaryTerms'),
          )).thenAnswer((_) async =>
          Ok<common.ValidationResult, ValidationException>(
              common.ValidationResult.failure(
            issues: const [
              ValidationIssueEntry(
                rule: ValidationRule.variables,
                severity: ValidationSeverity.error,
                message: 'Missing variable {0}',
              ),
              ValidationIssueEntry(
                rule: ValidationRule.truncation,
                severity: ValidationSeverity.warning,
                message: 'Significantly shorter than source',
              ),
            ],
          )));

      await handler.validateAndSave(
        translations: translations,
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      expect(persistedVersions, hasLength(1));
      final version = persistedVersions.single;
      expect(version.status, TranslationVersionStatus.needsReview);
      // validationIssues is persisted as a JSON-encoded structured array
      // of {rule, severity, message} objects (schema v1). Decode it and
      // assert each entry carries the canonical fields.
      expect(version.validationIssues, isNotNull);
      expect(
        version.validationSchemaVersion,
        kCurrentValidationSchemaVersion,
      );
      final raw = version.validationIssues!;
      final parsed = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(parsed.length, 2);
      final messages = parsed.map((e) => e['message']).toList();
      expect(
        messages,
        containsAll(<String>[
          'Missing variable {0}',
          'Significantly shorter than source',
        ]),
      );
      for (final entry in parsed) {
        expect(entry, containsPair('rule', isA<String>()));
        expect(entry, containsPair('severity', isA<String>()));
      }
      // Even with issues the translation is written and history recorded.
      verify(() => historyService.recordChange(
            versionId: version.id,
            translatedText: 'Bonjour',
            status: 'needsReview',
            changedBy: 'provider_anthropic',
            changeReason: any(named: 'changeReason'),
          )).called(1);
    });

    test(
        'persist failure: when versionRepository.upsert returns Err, failCount '
        'is incremented, history is NOT recorded for that unit, and the entry '
        'is NOT added to the TM batch (no orphan accounting)', () async {
      final units = [
        _fakeUnit('a', 'Hello'),
        _fakeUnit('b', 'World'),
      ];
      final translations = {
        'unit-a': 'Bonjour',
        'unit-b': 'Monde',
      };

      // 'unit-a' fails to upsert; 'unit-b' succeeds. Upsert is matched on the
      // captured entity's unitId so each unit gets its own response.
      when(() => versionRepository.upsert(any())).thenAnswer((inv) async {
        final v = inv.positionalArguments[0] as TranslationVersion;
        persistedVersions.add(v);
        if (v.unitId == 'unit-a') {
          return Err<TranslationVersion, TWMTDatabaseException>(
              const TWMTDatabaseException('disk full'));
        }
        return Ok<TranslationVersion, TWMTDatabaseException>(v);
      });

      final progress = await handler.validateAndSave(
        translations: translations,
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // Both upserts attempted (proves we didn't short-circuit the loop).
      verify(() => versionRepository.upsert(any())).called(2);

      // History recorded ONLY for the successful unit — no orphan history
      // entries for the failed upsert.
      verifyNever(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: 'Bonjour',
            status: any(named: 'status'),
            changedBy: any(named: 'changedBy'),
            changeReason: any(named: 'changeReason'),
          ));
      verify(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: 'Monde',
            status: any(named: 'status'),
            changedBy: 'provider_anthropic',
            changeReason: any(named: 'changeReason'),
          )).called(1);

      // TM batch contains only the successful translation.
      final captured = verify(() => tmService.addTranslationsBatch(
            translations: captureAny(named: 'translations'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).captured;
      expect(captured, hasLength(1));
      final batchEntries =
          captured.single as List<({String sourceText, String targetText})>;
      expect(batchEntries, hasLength(1));
      expect(batchEntries.single.sourceText, 'World');
      expect(batchEntries.single.targetText, 'Monde');

      // Progress reflects one success and one failure (relative to initial
      // counts of zero).
      expect(progress.successfulUnits, 1);
      expect(progress.failedUnits, 1);
    });

    test(
        'TM batch failure is non-fatal: addTranslationsBatch returning Err is '
        'logged but does not throw, and the successful persists/history '
        'remain intact', () async {
      final units = [_fakeUnit('a', 'Hello')];
      final translations = {'unit-a': 'Bonjour'};

      when(() => tmService.addTranslationsBatch(
            translations: any(named: 'translations'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Err<int, TmAddException>(
          TmAddException('tm database locked')));

      // Must not throw even though the TM batch failed.
      final progress = await handler.validateAndSave(
        translations: translations,
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // Persist + history both ran — the TM failure came AFTER and did not
      // roll back anything.
      expect(persistedVersions, hasLength(1));
      verify(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: 'Bonjour',
            status: any(named: 'status'),
            changedBy: 'provider_anthropic',
            changeReason: any(named: 'changeReason'),
          )).called(1);
      // And the returned progress still shows the unit as successful.
      expect(progress.successfulUnits, 1);
      expect(progress.failedUnits, 0);
      // Final phase after the TM step is 'finalizing'.
      expect(progress.currentPhase, TranslationPhase.finalizing);
    });

    test(
        'history service throwing is caught and logged; the unit is still '
        'counted as successful (history is non-critical)', () async {
      final units = [_fakeUnit('a', 'Hello')];
      final translations = {'unit-a': 'Bonjour'};

      when(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: any(named: 'translatedText'),
            status: any(named: 'status'),
            changedBy: any(named: 'changedBy'),
            changeReason: any(named: 'changeReason'),
          )).thenThrow(Exception('history service offline'));

      final progress = await handler.validateAndSave(
        translations: translations,
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // Persist happened.
      expect(persistedVersions, hasLength(1));
      // Unit is counted as successful despite the history failure.
      expect(progress.successfulUnits, 1);
      expect(progress.failedUnits, 0);
      // TM batch still runs for the successful persist.
      verify(() => tmService.addTranslationsBatch(
            translations: any(named: 'translations'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).called(1);
    });
  });
}
