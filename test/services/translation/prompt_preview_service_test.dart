import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/prompt_preview_service.dart';

class MockPromptBuilderService extends Mock
    implements IPromptBuilderService {}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

TranslationUnit _unit({
  String id = 'u1',
  String sourceText = 'Hello world',
}) {
  return TranslationUnit(
    id: id,
    projectId: 'p1',
    key: 'k1',
    sourceText: sourceText,
    createdAt: 0,
    updatedAt: 0,
  );
}

TranslationContext _context({
  String? providerId,
  String? modelId,
  String targetLanguage = 'fr',
}) {
  return TranslationContext(
    id: 'c1',
    projectId: 'p1',
    projectLanguageId: 'lang_fr',
    providerId: providerId,
    modelId: modelId,
    targetLanguage: targetLanguage,
    createdAt: _epoch,
    updatedAt: _epoch,
  );
}

BuiltPrompt _builtPrompt({
  String systemMessage = 'SYSTEM',
  String userMessage = 'USER',
}) {
  return BuiltPrompt(
    systemMessage: systemMessage,
    userMessage: userMessage,
    unitCount: 1,
    metadata: PromptMetadata(
      includesExamples: true,
      exampleCount: 0,
      includesGlossary: false,
      glossaryTermCount: 0,
      includesGameContext: false,
      includesProjectContext: false,
      createdAt: _epoch,
    ),
  );
}

void main() {
  late MockPromptBuilderService promptBuilder;
  late PromptPreviewService service;

  setUpAll(() {
    registerFallbackValue(<TranslationUnit>[]);
    registerFallbackValue(_context());
  });

  setUp(() {
    promptBuilder = MockPromptBuilderService();
    service = PromptPreviewService(promptBuilder);
  });

  void stubBuild(BuiltPrompt prompt) {
    when(() => promptBuilder.buildPrompt(
          units: any(named: 'units'),
          context: any(named: 'context'),
          includeExamples: any(named: 'includeExamples'),
          maxExamples: any(named: 'maxExamples'),
        )).thenAnswer((_) async => Ok(prompt));
  }

  group('buildPreview - success', () {
    test('defaults provider to anthropic and builds all provider payloads',
        () async {
      stubBuild(_builtPrompt(systemMessage: 'SYS', userMessage: 'USR'));

      final result = await service.buildPreview(
        unit: _unit(),
        context: _context(),
      );

      final preview = (result as Ok<PromptPreview, String>).value;
      expect(preview.providerCode, 'anthropic');
      expect(preview.modelName, 'default');
      expect(preview.systemMessage, 'SYS');
      expect(preview.userMessage, 'USR');
      expect(preview.fullPrompt, 'SYS\n\nUSR');
      // ~4 chars per token, ceil("SYS\n\nUSR".length / 4) = ceil(8/4) = 2
      expect(preview.estimatedTokens, ('SYS\n\nUSR'.length / 4).ceil());

      // Three providers always generated, in order.
      expect(preview.providerPayloads.map((p) => p.providerCode),
          ['anthropic', 'openai', 'deepl']);

      // Default formatted payload follows the anthropic shape.
      final decoded = jsonDecode(preview.formattedPayload) as Map;
      expect(decoded['system'], 'SYS');
      expect(decoded['max_tokens'], 4096);
      expect(decoded['model'], 'default');
    });

    test('uses the context model id in the payload', () async {
      stubBuild(_builtPrompt());

      final result = await service.buildPreview(
        unit: _unit(),
        context: _context(modelId: 'claude-opus-4-8'),
      );

      final preview = (result as Ok).value;
      expect(preview.modelName, 'claude-opus-4-8');
      final anthropic = preview.providerPayloads
          .firstWhere((p) => p.providerCode == 'anthropic');
      expect(jsonDecode(anthropic.payload)['model'], 'claude-opus-4-8');
    });

    test('formats the default payload as OpenAI when provider is openai',
        () async {
      stubBuild(_builtPrompt(systemMessage: 'S', userMessage: 'U'));

      final result = await service.buildPreview(
        unit: _unit(),
        context: _context(providerId: 'provider_openai'),
      );

      final preview = (result as Ok).value;
      expect(preview.providerCode, 'openai');
      final decoded = jsonDecode(preview.formattedPayload) as Map;
      expect(decoded['response_format'], {'type': 'json_object'});
      final messages = decoded['messages'] as List;
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], 'S');
      expect(messages.last['content'], 'U');
    });

    test('formats the default payload as DeepL when provider is deepl',
        () async {
      stubBuild(_builtPrompt());

      final result = await service.buildPreview(
        unit: _unit(sourceText: 'Greetings'),
        context: _context(providerId: 'provider_deepl', targetLanguage: 'de'),
      );

      final preview = (result as Ok).value;
      expect(preview.providerCode, 'deepl');
      final decoded = jsonDecode(preview.formattedPayload) as Map;
      expect(decoded['text'], ['Greetings']);
      expect(decoded['target_lang'], 'DE');
      expect(decoded['source_lang'], 'EN');
    });
  });

  group('buildPreview - failure', () {
    test('returns Err when the prompt builder returns an error', () async {
      when(() => promptBuilder.buildPrompt(
            units: any(named: 'units'),
            context: any(named: 'context'),
            includeExamples: any(named: 'includeExamples'),
            maxExamples: any(named: 'maxExamples'),
          )).thenAnswer(
        (_) async => Err(const PromptBuildingException('no template')),
      );

      final result = await service.buildPreview(
        unit: _unit(),
        context: _context(),
      );

      expect(result, isA<Err>());
      expect((result as Err).error, contains('Failed to build prompt'));
    });

    test('returns Err when the prompt builder throws', () async {
      when(() => promptBuilder.buildPrompt(
            units: any(named: 'units'),
            context: any(named: 'context'),
            includeExamples: any(named: 'includeExamples'),
            maxExamples: any(named: 'maxExamples'),
          )).thenThrow(Exception('kaboom'));

      final result = await service.buildPreview(
        unit: _unit(),
        context: _context(),
      );

      expect(result, isA<Err>());
      expect((result as Err).error, contains('Error building prompt preview'));
    });
  });
}
