import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/prompt_builder_service_impl.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

class _MockLanguageRepository extends Mock implements LanguageRepository {}

PromptBuilderServiceImpl _svc({LanguageRepository? langRepo}) =>
    PromptBuilderServiceImpl(FakeTokenCalculator(), null, null, langRepo);

TranslationContext _ctx({
  String targetLanguage = 'fr',
  String? gameContext,
  String? projectContext,
  Map<String, String>? glossaryTerms,
  List<Map<String, String>>? fewShotExamples,
}) =>
    TranslationContext(
      id: 'c1',
      projectId: 'p1',
      projectLanguageId: 'pl1',
      targetLanguage: targetLanguage,
      gameContext: gameContext,
      projectContext: projectContext,
      glossaryTerms: glossaryTerms,
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

void main() {
  group('buildSystemPrompt', () {
    test('falls back to the uppercase code without a language repository',
        () async {
      final out = await _svc().buildSystemPrompt(context: _ctx());

      expect(out, contains('professional translator'));
      expect(out, contains('translate game text to FR'));
    });

    test('uses the resolved language name when the repository has it',
        () async {
      final repo = _MockLanguageRepository();
      when(() => repo.getByCode('fr')).thenAnswer((_) async => Ok(
            const Language(id: 'l', code: 'fr', name: 'French', nativeName: 'Français'),
          ));

      final out = await _svc(langRepo: repo)
          .buildSystemPrompt(context: _ctx(targetLanguage: 'fr'));

      expect(out, contains('translate game text to French (fr)'));
    });
  });

  group('buildGameContext / buildProjectContext', () {
    test('game context is empty when null or blank', () async {
      expect(await _svc().buildGameContext(gameContext: null), '');
      expect(await _svc().buildGameContext(gameContext: '   '), '');
    });

    test('game context is labelled when present', () async {
      final out = await _svc().buildGameContext(gameContext: 'WH3 lore');
      expect(out, contains('GAME CONTEXT:\nWH3 lore'));
    });

    test('project context combines project + custom instruction sections',
        () async {
      final out = await _svc().buildProjectContext(
        projectContext: 'a mod',
        customInstructions: 'be terse',
      );
      expect(out, contains('PROJECT CONTEXT:\na mod'));
      expect(out, contains('CUSTOM INSTRUCTIONS:\nbe terse'));
    });

    test('project context is empty when both inputs are blank', () async {
      expect(
        await _svc().buildProjectContext(projectContext: '', customInstructions: null),
        '',
      );
    });
  });

  group('buildFewShotExamples', () {
    test('returns empty when there are no examples', () async {
      expect(await _svc().buildFewShotExamples(context: _ctx()), '');
    });

    test('formats and caps examples at maxExamples', () async {
      final ctx = _ctx(fewShotExamples: [
        {'source': 's1', 'target': 't1'},
        {'source': 's2', 'target': 't2'},
        {'source': 's3', 'target': 't3'},
      ]);

      final out = await _svc().buildFewShotExamples(context: ctx, maxExamples: 2);

      expect(out, contains('1. Source: "s1"'));
      expect(out, contains('2. Source: "s2"'));
      expect(out, isNot(contains('s3')));
    });
  });

  group('buildGlossarySection (legacy map)', () {
    test('returns empty when there are no terms', () async {
      expect(await _svc().buildGlossarySection(glossaryTerms: null), '');
      expect(await _svc().buildGlossarySection(glossaryTerms: {}), '');
    });

    test('formats plain term mappings', () async {
      final out = await _svc()
          .buildGlossarySection(glossaryTerms: {'Empire': 'Empire FR'});
      expect(out, contains('- "Empire" → "Empire FR"'));
    });

    test('splits the [Note: ...] suffix into a Context line', () async {
      final out = await _svc().buildGlossarySection(
        glossaryTerms: {'Lord': 'Seigneur [Note: noble title]'},
      );
      expect(out, contains('- "Lord" → "Seigneur"'));
      expect(out, contains('Context: noble title'));
    });
  });

  group('buildUserMessage', () {
    test('throws when units are empty', () async {
      expect(
        () => _svc().buildUserMessage(units: []),
        throwsA(isA<InvalidContextException>()),
      );
    });

    test('numbers each unit with its key and source', () async {
      final out = await _svc().buildUserMessage(
        units: [_unit('k1', 'Hello'), _unit('k2', 'World')],
      );
      expect(out, contains('Translate the following 2 text entries'));
      expect(out, contains('1. Key: "k1"'));
      expect(out, contains('Source: "Hello"'));
      expect(out, contains('2. Key: "k2"'));
    });
  });

  group('buildFormatInstructions', () {
    test('describes the JSON translations envelope', () async {
      final out = await _svc().buildFormatInstructions();
      expect(out, contains('OUTPUT FORMAT'));
      expect(out, contains('"translations"'));
    });
  });

  group('buildPrompt', () {
    test('errors on an empty units list', () async {
      final result = await _svc().buildPrompt(units: [], context: _ctx());

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<PromptBuildingException>());
    });

    test('assembles system + user messages and metadata', () async {
      final result = await _svc().buildPrompt(
        units: [_unit('k1', 'Hello')],
        context: _ctx(gameContext: 'WH3', glossaryTerms: {'Hello': 'Bonjour'}),
        includeExamples: false,
      );

      expect(result.isOk, isTrue);
      final prompt = result.unwrap();
      expect(prompt.unitCount, 1);
      expect(prompt.systemMessage, contains('professional translator'));
      expect(prompt.systemMessage, contains('OUTPUT FORMAT'));
      expect(prompt.systemMessage, contains('GAME CONTEXT:'));
      expect(prompt.userMessage, contains('Source: "Hello"'));
      expect(prompt.metadata.includesGameContext, isTrue);
      expect(prompt.metadata.includesGlossary, isTrue);
      expect(prompt.metadata.glossaryTermCount, 1);
    });
  });

  group('validatePrompt', () {
    BuiltPrompt prompt({String system = 'sys', String user = 'usr', int units = 1}) =>
        BuiltPrompt(
          systemMessage: system,
          userMessage: user,
          unitCount: units,
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

    test('a well-formed prompt has no errors', () async {
      expect(await _svc().validatePrompt(prompt: prompt()), isEmpty);
    });

    test('flags empty messages and a non-positive unit count', () async {
      final errors = await _svc()
          .validatePrompt(prompt: prompt(system: '  ', user: '', units: 0));

      final fields = errors.map((e) => e.field).toSet();
      expect(fields, containsAll(['systemMessage', 'userMessage', 'unitCount']));
    });

    test('flags an over-long system message', () async {
      final errors = await _svc()
          .validatePrompt(prompt: prompt(system: 'x' * 50001));

      expect(errors.any((e) => e.field == 'systemMessage'), isTrue);
    });
  });

  group('optimizePrompt / estimateTokens', () {
    BuiltPrompt prompt(String system, String user) => BuiltPrompt(
          systemMessage: system,
          userMessage: user,
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

    test('estimateTokens uses the calculator (length ~/ 4)', () async {
      // 'aaaa' + '\n\n' + 'bbbb' = 10 chars -> 2 tokens
      final tokens = await _svc()
          .estimateTokens(prompt: prompt('aaaa', 'bbbb'), providerCode: 'x');
      expect(tokens, 2);
    });

    test('returns the prompt unchanged when already within the limit',
        () async {
      final p = prompt('short', 'short');
      final result =
          await _svc().optimizePrompt(prompt: p, maxTokens: 1000, providerCode: 'x');

      expect(result.isOk, isTrue);
      expect(identical(result.unwrap(), p), isTrue);
    });

    test('errors when the prompt cannot be shrunk under the limit', () async {
      final p = prompt('x' * 400, 'y' * 400); // ~200 tokens, no examples/context
      final result =
          await _svc().optimizePrompt(prompt: p, maxTokens: 5, providerCode: 'x');

      expect(result.isErr, isTrue);
    });
  });
}
