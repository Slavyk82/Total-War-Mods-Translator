import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart'
    show TWMTDatabaseException;
import 'package:twmt/models/common/validation_rule.dart';
import 'package:twmt/models/domain/translation_provider.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/translation/handlers/batch_estimation_handler.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';

import '../../../../helpers/noop_logger.dart';

// Unit tests for BatchEstimationHandler.
//
// The handler is mostly pure computation: it queries the TM (version repo) for
// already-translated unit IDs, builds a prompt, estimates tokens via the LLM
// service, resolves the provider model name, and assembles a BatchEstimate.
// It also validates batch configuration and aggregates batch statistics from a
// raw SQL query. We mock every injected collaborator (including the optional
// providerRepository, so the constructor never touches ServiceLocator/GetIt)
// and drive each branch with crafted inputs.

class _MockLlmService extends Mock implements ILlmService {}

class _MockPromptBuilder extends Mock implements IPromptBuilderService {}

class _MockBatchRepository extends Mock implements TranslationBatchRepository {}

class _MockBatchUnitRepository extends Mock
    implements TranslationBatchUnitRepository {}

class _MockUnitRepository extends Mock implements TranslationUnitRepository {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockProviderRepository extends Mock
    implements TranslationProviderRepository {}

class _MockDatabase extends Mock implements Database {}

class _FakeLlmRequest extends Fake implements LlmRequest {}

class _FakeBatch extends Fake implements TranslationBatch {}

class _FakeTranslationContext extends Fake implements TranslationContext {}

// --- Fixtures --------------------------------------------------------------

const String _batchId = 'batch-est-1';
const String _projectId = 'project-1';
const String _projectLanguageId = 'plang-1';

TranslationUnit _unit(String id, String source) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return TranslationUnit(
    id: id,
    projectId: _projectId,
    key: 'key-$id',
    sourceText: source,
    createdAt: now,
    updatedAt: now,
  );
}

TranslationContext _context() {
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

BuiltPrompt _builtPrompt() {
  return BuiltPrompt(
    systemMessage: 'You are a translator.',
    userMessage: 'Translate these units.',
    unitCount: 1,
    metadata: PromptMetadata(
      includesExamples: false,
      exampleCount: 0,
      includesGlossary: false,
      glossaryTermCount: 0,
      includesGameContext: false,
      includesProjectContext: false,
      createdAt: DateTime(2026, 1, 1),
    ),
  );
}

TranslationProvider _provider({String? defaultModel}) {
  return TranslationProvider(
    id: 'prov-1',
    code: 'anthropic',
    name: 'Anthropic Claude',
    defaultModel: defaultModel,
    createdAt: 0,
  );
}

TranslationBatchUnit _batchUnit(String unitId) {
  return TranslationBatchUnit(
    id: 'bu-$unitId',
    batchId: _batchId,
    unitId: unitId,
    processingOrder: 0,
  );
}

void main() {
  late _MockLlmService llmService;
  late _MockPromptBuilder promptBuilder;
  late _MockBatchRepository batchRepository;
  late _MockBatchUnitRepository batchUnitRepository;
  late _MockUnitRepository unitRepository;
  late _MockVersionRepository versionRepository;
  late _MockProviderRepository providerRepository;
  late BatchEstimationHandler handler;

  setUpAll(() {
    registerFallbackValue(_FakeLlmRequest());
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(<TranslationUnit>[]);
  });

  setUp(() {
    llmService = _MockLlmService();
    promptBuilder = _MockPromptBuilder();
    batchRepository = _MockBatchRepository();
    batchUnitRepository = _MockBatchUnitRepository();
    unitRepository = _MockUnitRepository();
    versionRepository = _MockVersionRepository();
    providerRepository = _MockProviderRepository();

    handler = BatchEstimationHandler(
      llmService: llmService,
      promptBuilder: promptBuilder,
      batchRepository: batchRepository,
      batchUnitRepository: batchUnitRepository,
      unitRepository: unitRepository,
      versionRepository: versionRepository,
      providerRepository: providerRepository,
      logger: NoopLogger(),
    );
  });

  // Wire up the common happy-path collaborators for estimateBatch.
  void stubEstimateHappyPath({
    Set<String> translatedIds = const {},
    int estimatedTokens = 1000,
    String activeProvider = 'anthropic',
    String? defaultModel = 'claude-haiku-4.5',
  }) {
    when(() => versionRepository.getTranslatedUnitIds(
          unitIds: any(named: 'unitIds'),
          projectLanguageId: any(named: 'projectLanguageId'),
        )).thenAnswer((_) async => Ok(translatedIds));
    when(() => promptBuilder.buildPrompt(
          units: any(named: 'units'),
          context: any(named: 'context'),
          includeExamples: any(named: 'includeExamples'),
          maxExamples: any(named: 'maxExamples'),
        )).thenAnswer((_) async => Ok(_builtPrompt()));
    when(() => llmService.estimateTokens(any()))
        .thenAnswer((_) async => Ok(estimatedTokens));
    when(() => llmService.getActiveProviderCode())
        .thenAnswer((_) async => activeProvider);
    when(() => providerRepository.getByCode(any()))
        .thenAnswer((_) async => Ok(_provider(defaultModel: defaultModel)));
  }

  group('estimateBatch', () {
    test('returns EmptyBatchException when units list is empty', () async {
      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: const [],
        context: _context(),
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<EmptyBatchException>());
      expect(result.unwrapErr().batchId, _batchId);
    });

    test('estimates a single-unit batch with no TM matches', () async {
      stubEstimateHappyPath(estimatedTokens: 1000);

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'Hello world')],
        context: _context(),
      );

      expect(result.isOk, isTrue);
      final estimate = result.unwrap();
      expect(estimate.batchId, _batchId);
      expect(estimate.totalUnits, 1);
      expect(estimate.totalEstimatedTokens, 1000);
      // ~40% input, ~60% output split.
      expect(estimate.estimatedInputTokens, 400);
      expect(estimate.estimatedOutputTokens, 600);
      expect(estimate.unitsFromTm, 0);
      expect(estimate.unitsRequiringLlm, 1);
      expect(estimate.tmReuseRate, 0.0);
      expect(estimate.providerCode, 'anthropic');
      expect(estimate.modelName, 'claude-haiku-4.5');
      // 1 unit / 50 per minute * 60 = ~1.2 -> rounds to 1 second.
      expect(estimate.estimatedDurationSeconds,
          ((1 / AppConstants.estimatedUnitsPerMinute) * 60).round());
    });

    test('computes TM reuse rate and units requiring LLM for multi-unit batch',
        () async {
      // 2 of 4 units already translated.
      stubEstimateHappyPath(
        translatedIds: {'u1', 'u2'},
        estimatedTokens: 2000,
      );

      final units = [
        _unit('u1', 'A'),
        _unit('u2', 'B'),
        _unit('u3', 'C'),
        _unit('u4', 'D'),
      ];

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: units,
        context: _context(),
      );

      expect(result.isOk, isTrue);
      final estimate = result.unwrap();
      expect(estimate.totalUnits, 4);
      expect(estimate.unitsFromTm, 2);
      expect(estimate.unitsRequiringLlm, 2);
      expect(estimate.tmReuseRate, 0.5);
      expect(estimate.totalEstimatedTokens, 2000);
    });

    test('treats TM lookup error as zero matches (all units require LLM)',
        () async {
      when(() => versionRepository.getTranslatedUnitIds(
            unitIds: any(named: 'unitIds'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer(
        (_) async => Err(TWMTDatabaseException('db down')),
      );
      when(() => promptBuilder.buildPrompt(
            units: any(named: 'units'),
            context: any(named: 'context'),
            includeExamples: any(named: 'includeExamples'),
            maxExamples: any(named: 'maxExamples'),
          )).thenAnswer((_) async => Ok(_builtPrompt()));
      when(() => llmService.estimateTokens(any()))
          .thenAnswer((_) async => Ok(500));
      when(() => llmService.getActiveProviderCode())
          .thenAnswer((_) async => 'anthropic');
      when(() => providerRepository.getByCode(any()))
          .thenAnswer((_) async => Ok(_provider(defaultModel: 'm1')));

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A'), _unit('u2', 'B')],
        context: _context(),
      );

      expect(result.isOk, isTrue);
      final estimate = result.unwrap();
      expect(estimate.unitsFromTm, 0);
      expect(estimate.unitsRequiringLlm, 2);
      expect(estimate.tmReuseRate, 0.0);
    });

    test('returns error when prompt building fails', () async {
      when(() => versionRepository.getTranslatedUnitIds(
            unitIds: any(named: 'unitIds'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => Ok(<String>{}));
      when(() => promptBuilder.buildPrompt(
            units: any(named: 'units'),
            context: any(named: 'context'),
            includeExamples: any(named: 'includeExamples'),
            maxExamples: any(named: 'maxExamples'),
          )).thenAnswer(
        (_) async => Err(PromptBuildingException('boom')),
      );

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
      expect(result.unwrapErr().message, contains('Failed to build prompt'));
    });

    test('returns error when token estimation fails', () async {
      when(() => versionRepository.getTranslatedUnitIds(
            unitIds: any(named: 'unitIds'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => Ok(<String>{}));
      when(() => promptBuilder.buildPrompt(
            units: any(named: 'units'),
            context: any(named: 'context'),
            includeExamples: any(named: 'includeExamples'),
            maxExamples: any(named: 'maxExamples'),
          )).thenAnswer((_) async => Ok(_builtPrompt()));
      when(() => llmService.estimateTokens(any())).thenAnswer(
        (_) async => Err(LlmServiceException('token error')),
      );

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
      expect(result.unwrapErr().message, contains('Failed to estimate tokens'));
    });

    test('falls back to "Unknown" model when provider lookup returns Err',
        () async {
      stubEstimateHappyPath(estimatedTokens: 100);
      when(() => providerRepository.getByCode(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('not found')),
      );

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap().modelName, 'Unknown');
    });

    test('falls back to "Unknown" model when provider lookup throws', () async {
      stubEstimateHappyPath(estimatedTokens: 100);
      when(() => providerRepository.getByCode(any()))
          .thenThrow(Exception('boom'));

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap().modelName, 'Unknown');
    });

    test('uses "Unknown" model when provider has null defaultModel', () async {
      stubEstimateHappyPath(estimatedTokens: 100, defaultModel: null);

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap().modelName, 'Unknown');
    });

    test('returns orchestration error when a collaborator throws', () async {
      when(() => versionRepository.getTranslatedUnitIds(
            unitIds: any(named: 'unitIds'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenThrow(Exception('unexpected'));

      final result = await handler.estimateBatch(
        batchId: _batchId,
        units: [_unit('u1', 'A')],
        context: _context(),
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
      expect(result.unwrapErr().message, contains('Failed to estimate batch'));
    });
  });

  group('validateBatch', () {
    test('returns no errors for a valid batch and context', () async {
      when(() => batchRepository.getById(_batchId)).thenAnswer(
        (_) async => Ok(_FakeBatch()),
      );

      final errors = await handler.validateBatch(
        batchId: _batchId,
        context: _context(),
      );

      expect(errors, isEmpty);
    });

    test('flags empty batch ID', () async {
      when(() => batchRepository.getById(any())).thenAnswer(
        (_) async => Ok(_FakeBatch()),
      );

      final errors = await handler.validateBatch(
        batchId: '   ',
        context: _context(),
      );

      expect(errors.any((e) => e.field == 'batchId'), isTrue);
    });

    test('flags empty projectId and targetLanguage', () async {
      when(() => batchRepository.getById(any())).thenAnswer(
        (_) async => Ok(_FakeBatch()),
      );

      final now = DateTime.now();
      final context = TranslationContext(
        id: 'ctx-2',
        projectId: '  ',
        projectLanguageId: _projectLanguageId,
        targetLanguage: '',
        createdAt: now,
        updatedAt: now,
      );

      final errors = await handler.validateBatch(
        batchId: _batchId,
        context: context,
      );

      expect(errors.any((e) => e.field == 'projectId'), isTrue);
      expect(errors.any((e) => e.field == 'targetLanguage'), isTrue);
      expect(
        errors.every((e) => e.rule == ValidationRule.completeness),
        isTrue,
      );
    });

    test('flags missing batch in database', () async {
      when(() => batchRepository.getById(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('missing')),
      );

      final errors = await handler.validateBatch(
        batchId: _batchId,
        context: _context(),
      );

      expect(
        errors.any((e) =>
            e.field == 'batchId' &&
            e.message == 'Batch does not exist in database'),
        isTrue,
      );
    });
  });

  group('getBatchStatistics', () {
    void stubStats(Map<String, Object?> row) {
      final db = _MockDatabase();
      when(() => batchRepository.database).thenReturn(db);
      when(() => db.rawQuery(any(), any())).thenAnswer((_) async => [row]);
    }

    test('aggregates statistics from a single row (no filters)', () async {
      stubStats({
        'total_batches': 3,
        'total_units': 100,
        'total_completed': 80,
        'total_successful': 70,
        'total_failed': 10,
        'avg_time_per_unit': 2.5,
      });

      final stats = await handler.getBatchStatistics();

      expect(stats.totalBatches, 3);
      expect(stats.totalUnitsProcessed, 80);
      expect(stats.totalSuccessful, 70);
      expect(stats.totalFailed, 10);
      // skipped = total_units - total_completed = 100 - 80 = 20.
      expect(stats.totalSkipped, 20);
      expect(stats.averageTimePerUnit, 2.5);
    });

    test('clamps negative skipped count to zero', () async {
      stubStats({
        'total_batches': 1,
        'total_units': 10,
        'total_completed': 15, // completed > units => negative skipped
        'total_successful': 10,
        'total_failed': 0,
        'avg_time_per_unit': 0.0,
      });

      final stats = await handler.getBatchStatistics();

      expect(stats.totalSkipped, 0);
    });

    test('applies batchIds and since filters in the query args', () async {
      final db = _MockDatabase();
      when(() => batchRepository.database).thenReturn(db);
      when(() => db.rawQuery(any(), any())).thenAnswer((_) async => [
            {
              'total_batches': 2,
              'total_units': 50,
              'total_completed': 50,
              'total_successful': 50,
              'total_failed': 0,
              'avg_time_per_unit': 1.0,
            }
          ]);

      final since = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
      final stats = await handler.getBatchStatistics(
        batchIds: ['b1', 'b2'],
        since: since,
      );

      expect(stats.totalBatches, 2);

      final captured =
          verify(() => db.rawQuery(captureAny(), captureAny())).captured;
      final sql = captured[0] as String;
      final args = captured[1] as List<dynamic>;
      expect(sql, contains('tb.id IN (?, ?)'));
      expect(sql, contains('tb.started_at >= ?'));
      // Two batch ids + 1 since arg.
      expect(args, ['b1', 'b2', 2000]);
    });

    test('returns empty statistics when the query throws', () async {
      final db = _MockDatabase();
      when(() => batchRepository.database).thenReturn(db);
      when(() => db.rawQuery(any(), any())).thenThrow(Exception('sql error'));

      final stats = await handler.getBatchStatistics();

      expect(stats.totalBatches, 0);
      expect(stats.totalUnitsProcessed, 0);
      expect(stats.totalSuccessful, 0);
      expect(stats.totalFailed, 0);
      expect(stats.totalSkipped, 0);
      expect(stats.averageTimePerUnit, 0.0);
    });
  });

  group('loadBatchUnits', () {
    test('loads units via batch-unit associations', () async {
      when(() => batchUnitRepository.findByBatchId(_batchId)).thenAnswer(
        (_) async => Ok([_batchUnit('u1'), _batchUnit('u2')]),
      );
      final loaded = [_unit('u1', 'A'), _unit('u2', 'B')];
      when(() => unitRepository.getByIds(any()))
          .thenAnswer((_) async => Ok(loaded));

      final result = await handler.loadBatchUnits(_batchId);

      expect(result.isOk, isTrue);
      expect(result.unwrap(), loaded);
      verify(() => unitRepository.getByIds(['u1', 'u2'])).called(1);
    });

    test('returns error when batch-unit lookup fails', () async {
      when(() => batchUnitRepository.findByBatchId(_batchId)).thenAnswer(
        (_) async => Err(TWMTDatabaseException('no associations')),
      );

      final result = await handler.loadBatchUnits(_batchId);

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('Failed to load batch units'));
    });

    test('returns error when unit loading fails', () async {
      when(() => batchUnitRepository.findByBatchId(_batchId)).thenAnswer(
        (_) async => Ok([_batchUnit('u1')]),
      );
      when(() => unitRepository.getByIds(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('units gone')),
      );

      final result = await handler.loadBatchUnits(_batchId);

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message,
          contains('Failed to load translation units'));
    });

    test('returns orchestration error when a collaborator throws', () async {
      when(() => batchUnitRepository.findByBatchId(_batchId))
          .thenThrow(Exception('boom'));

      final result = await handler.loadBatchUnits(_batchId);

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
      expect(result.unwrapErr().message, contains('Failed to load batch units'));
    });
  });
}
