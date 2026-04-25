import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_provider.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/translation/batch_estimation_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';

// Mocks ----------------------------------------------------------------

class _MockLlmService extends Mock implements ILlmService {}

class _MockPromptBuilder extends Mock implements IPromptBuilderService {}

class _MockProviderRepository extends Mock
    implements TranslationProviderRepository {}

// Fallbacks for any() matchers.
class _FakeLlmRequest extends Fake implements LlmRequest {}

class _FakeTranslationUnit extends Fake implements TranslationUnit {}

class _FakeTranslationContext extends Fake implements TranslationContext {}

TranslationContext _buildContext() => TranslationContext(
      id: 'ctx-1',
      projectId: 'project-1',
      projectLanguageId: 'pl-1',
      providerId: 'provider_anthropic',
      modelId: 'claude-test',
      targetLanguage: 'fr',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

TranslationUnit _buildUnit(String id) => TranslationUnit(
      id: id,
      projectId: 'project-1',
      key: 'key_$id',
      sourceText: 'Hello $id',
      createdAt: 1,
      updatedAt: 1,
    );

TranslationProvider _buildProvider() => TranslationProvider(
      id: 'provider_anthropic',
      code: 'anthropic',
      name: 'Anthropic',
      defaultModel: 'claude-test-model',
      createdAt: 1,
    );

BuiltPrompt _buildPrompt() => BuiltPrompt(
      systemMessage: 'system',
      userMessage: 'user',
      unitCount: 1,
      metadata: PromptMetadata(
        includesExamples: false,
        exampleCount: 0,
        includesGlossary: false,
        glossaryTermCount: 0,
        includesGameContext: false,
        includesProjectContext: false,
        createdAt: DateTime(2026),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeLlmRequest());
    registerFallbackValue(_FakeTranslationUnit());
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(<TranslationUnit>[]);
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  test('uses constructor-injected provider repository', () async {
    final llmService = _MockLlmService();
    final promptBuilder = _MockPromptBuilder();
    final fakeRepo = _MockProviderRepository();

    // LLM stubs.
    when(() => llmService.estimateTokens(any()))
        .thenAnswer((_) async => const Ok(100));
    when(() => llmService.getActiveProviderCode())
        .thenAnswer((_) async => 'anthropic');

    // Prompt builder stub.
    when(() => promptBuilder.buildPrompt(
          units: any(named: 'units'),
          context: any(named: 'context'),
          includeExamples: any(named: 'includeExamples'),
          maxExamples: any(named: 'maxExamples'),
        )).thenAnswer((_) async => Ok(_buildPrompt()));

    // Fake repo returns a known provider. If the service calls the
    // injected repo, we should see `modelName == 'claude-test-model'`.
    when(() => fakeRepo.getByCode('anthropic'))
        .thenAnswer((_) async => Ok(_buildProvider()));

    final service = BatchEstimationService(
      llmService: llmService,
      promptBuilder: promptBuilder,
      logger: FakeLogger(),
      isUnitTranslated: (_, _) async => false,
      providerRepository: fakeRepo,
    );

    final result = await service.estimateBatch(
      batchId: 'batch-1',
      units: [_buildUnit('u1')],
      context: _buildContext(),
    );

    expect(result.isOk, isTrue, reason: 'estimateBatch must succeed');
    final estimate = result.unwrap();
    expect(estimate.modelName, equals('claude-test-model'));
    verify(() => fakeRepo.getByCode('anthropic')).called(1);
  });
}
