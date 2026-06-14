import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/prompt_builder_service_impl.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

class _MockGlossaryRepository extends Mock implements GlossaryRepository {}

class _MockCustomRulesService extends Mock implements LlmCustomRulesService {}

PromptBuilderServiceImpl _svc({
  GlossaryRepository? glossaryRepo,
  LlmCustomRulesService? rulesService,
}) =>
    PromptBuilderServiceImpl(
      FakeTokenCalculator(),
      glossaryRepo,
      rulesService,
      null,
    );

TranslationContext _ctx({
  String? gameContext,
  String? projectContext,
  List<GlossaryTermWithVariants>? glossaryEntries,
  List<Map<String, String>>? fewShotExamples,
  String projectId = 'p1',
}) =>
    TranslationContext(
      id: 'c1',
      projectId: projectId,
      projectLanguageId: 'pl1',
      targetLanguage: 'fr',
      gameContext: gameContext,
      projectContext: projectContext,
      glossaryEntries: glossaryEntries,
      fewShotExamples: fewShotExamples,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

TranslationUnit _unit(String key, String source) => TranslationUnit(
      id: 'u-$key',
      projectId: 'p1',
      key: key,
      sourceText: source,
      createdAt: 0,
      updatedAt: 0,
    );

GlossaryTermWithVariants _term(
  String source,
  String target, {
  String? notes,
  String entryId = 'e1',
}) =>
    GlossaryTermWithVariants(
      sourceTerm: source,
      variants: [
        GlossaryVariant(targetTerm: target, notes: notes, entryId: entryId),
      ],
    );

BuiltPrompt _builtPrompt({
  required String system,
  required String user,
  bool includesExamples = false,
  bool includesGameContext = false,
  bool includesProjectContext = false,
}) =>
    BuiltPrompt(
      systemMessage: system,
      userMessage: user,
      unitCount: 1,
      metadata: PromptMetadata(
        includesExamples: includesExamples,
        exampleCount: includesExamples ? 3 : 0,
        includesGlossary: false,
        glossaryTermCount: 0,
        includesGameContext: includesGameContext,
        includesProjectContext: includesProjectContext,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('buildGlossarySectionWithVariants', () {
    test('returns empty when entries are null or empty', () async {
      expect(
        await _svc().buildGlossarySectionWithVariants(
          glossaryEntries: null,
          sourceTexts: const ['Empire'],
        ),
        '',
      );
      expect(
        await _svc().buildGlossarySectionWithVariants(
          glossaryEntries: const [],
          sourceTexts: const ['Empire'],
        ),
        '',
      );
    });

    test('returns empty when no source terms match the text', () async {
      final out = await _svc().buildGlossarySectionWithVariants(
        glossaryEntries: [_term('Bretonnia', 'Bretonnie')],
        sourceTexts: const ['Nothing relevant here'],
      );
      expect(out, '');
    });

    test('formats matched entries into the glossary section', () async {
      final out = await _svc().buildGlossarySectionWithVariants(
        glossaryEntries: [_term('Empire', 'Empire FR')],
        sourceTexts: const ['Long live the Empire'],
      );

      expect(out, contains('GLOSSARY (must use these translations):'));
      expect(out, contains('"Empire" → "Empire FR"'));
    });

    test('increments usage count for matched entries via the repository',
        () async {
      final repo = _MockGlossaryRepository();
      when(() => repo.incrementUsageCount(any()))
          .thenAnswer((_) async {});

      final out = await _svc(glossaryRepo: repo).buildGlossarySectionWithVariants(
        glossaryEntries: [_term('Empire', 'Empire FR', entryId: 'e42')],
        sourceTexts: const ['The Empire marches'],
      );

      expect(out, contains('"Empire" → "Empire FR"'));
      final captured =
          verify(() => repo.incrementUsageCount(captureAny())).captured.single
              as List<String>;
      expect(captured, contains('e42'));
    });

    test('swallows repository failures while incrementing usage', () async {
      final repo = _MockGlossaryRepository();
      when(() => repo.incrementUsageCount(any()))
          .thenThrow(Exception('db down'));

      final out = await _svc(glossaryRepo: repo).buildGlossarySectionWithVariants(
        glossaryEntries: [_term('Empire', 'Empire FR')],
        sourceTexts: const ['Hail the Empire'],
      );

      // Still produces the section despite the stats failure.
      expect(out, contains('"Empire" → "Empire FR"'));
    });
  });

  group('_buildCustomRulesSection (via buildPrompt)', () {
    test('includes the custom rules section when rules text is present',
        () async {
      final rules = _MockCustomRulesService();
      when(() => rules.getCombinedRulesTextForProject('p1'))
          .thenAnswer((_) async => 'Always be formal.');

      final result = await _svc(rulesService: rules).buildPrompt(
        units: [_unit('k1', 'Hello')],
        context: _ctx(),
        includeExamples: false,
      );

      expect(result.isOk, isTrue);
      expect(
        result.unwrap().systemMessage,
        contains('CUSTOM TRANSLATION RULES:'),
      );
      expect(result.unwrap().systemMessage, contains('Always be formal.'));
    });

    test('omits the custom rules section when rules text is empty', () async {
      final rules = _MockCustomRulesService();
      when(() => rules.getCombinedRulesTextForProject(any()))
          .thenAnswer((_) async => '');

      final result = await _svc(rulesService: rules).buildPrompt(
        units: [_unit('k1', 'Hello')],
        context: _ctx(),
        includeExamples: false,
      );

      expect(result.isOk, isTrue);
      expect(
        result.unwrap().systemMessage,
        isNot(contains('CUSTOM TRANSLATION RULES:')),
      );
    });
  });

  group('buildPrompt with examples + variant glossary', () {
    test('includes examples and variant-aware glossary in the prompt',
        () async {
      final result = await _svc().buildPrompt(
        units: [_unit('k1', 'Long live the Empire')],
        context: _ctx(
          gameContext: 'WH3',
          projectContext: 'a mod',
          glossaryEntries: [_term('Empire', 'Empire FR')],
          fewShotExamples: [
            {'source': 's1', 'target': 't1'},
            {'source': 's2', 'target': 't2'},
          ],
        ),
        includeExamples: true,
        maxExamples: 2,
      );

      expect(result.isOk, isTrue);
      final prompt = result.unwrap();
      expect(prompt.userMessage, contains('EXAMPLES (for reference):'));
      expect(prompt.systemMessage, contains('GLOSSARY'));
      expect(prompt.systemMessage, contains('PROJECT CONTEXT:'));
      expect(prompt.metadata.includesExamples, isTrue);
      expect(prompt.metadata.exampleCount, 2);
      expect(prompt.metadata.includesProjectContext, isTrue);
      expect(prompt.metadata.glossaryTermCount, greaterThan(0));
    });
  });

  group('optimizePrompt', () {
    test('removes examples when that brings the prompt under the limit',
        () async {
      // System message contains an EXAMPLES section that, when removed,
      // shrinks the prompt enough to fit.
      final system = 'Header line\n'
          'EXAMPLES (for reference):\n'
          '${'x' * 400}\n'
          '\n'
          'Footer line';
      final prompt = _builtPrompt(
        system: system,
        user: 'short',
        includesExamples: true,
      );

      // After removal the EXAMPLES block disappears; pick a limit that the
      // trimmed prompt fits but the original does not.
      final result = await _svc().optimizePrompt(
        prompt: prompt,
        maxTokens: 10,
        providerCode: 'x',
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap().systemMessage, isNot(contains('x' * 400)));
      expect(result.unwrap().metadata.includesExamples, isFalse);
    });

    test('shortens contexts when removing examples is not enough', () async {
      final system = 'Hi\n'
          'GAME CONTEXT:\n'
          '${'g' * 400}\n'
          '\n'
          'PROJECT CONTEXT:\n'
          '${'p' * 400}\n'
          '\n'
          'GLOSSARY:\n'
          'keep';
      final prompt = _builtPrompt(
        system: system,
        user: 'a',
        includesGameContext: true,
        includesProjectContext: true,
      );

      final result = await _svc().optimizePrompt(
        prompt: prompt,
        maxTokens: 10,
        providerCode: 'x',
      );

      expect(result.isOk, isTrue);
      final optimized = result.unwrap();
      expect(optimized.systemMessage, isNot(contains('g' * 400)));
      expect(optimized.systemMessage, isNot(contains('p' * 400)));
      expect(optimized.systemMessage, contains('keep'));
      expect(optimized.metadata.includesGameContext, isFalse);
      expect(optimized.metadata.includesProjectContext, isFalse);
    });

    test('errors and reports token counts when no strategy fits', () async {
      final prompt = _builtPrompt(
        system: 'GAME CONTEXT:\n${'g' * 800}',
        user: 'y' * 800,
        includesGameContext: true,
      );

      final result = await _svc().optimizePrompt(
        prompt: prompt,
        maxTokens: 5,
        providerCode: 'x',
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('Cannot optimize prompt'));
    });
  });
}
