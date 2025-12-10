import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';
import 'package:twmt/services/glossary/utils/glossary_matcher.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Implementation of prompt builder service for LLM translation
///
/// Constructs contextual prompts with:
/// - System instructions
/// - Game and project context
/// - Few-shot examples from TM
/// - Glossary terms
/// - Structured output format
class PromptBuilderServiceImpl implements IPromptBuilderService {
  final TokenCalculator _tokenCalculator;
  final GlossaryRepository? _glossaryRepository;
  final LlmCustomRulesService? _customRulesService;

  PromptBuilderServiceImpl(
    this._tokenCalculator, [
    this._glossaryRepository,
    this._customRulesService,
  ]);

  @override
  Future<Result<BuiltPrompt, PromptBuildingException>> buildPrompt({
    required List<TranslationUnit> units,
    required TranslationContext context,
    bool includeExamples = true,
    int maxExamples = 3,
  }) async {
    try {
      if (units.isEmpty) {
        return Err(
          PromptBuildingException(
            'Cannot build prompt with empty units list',
            error: EmptyBatchException('No translation units provided'),
          ),
        );
      }

      // Build all prompt components
      final systemMessage = await buildSystemPrompt(context: context);

      final gameContextText = await buildGameContext(
        gameContext: context.gameContext,
        category: null,
      );

      final projectContextText = await buildProjectContext(
        projectContext: context.projectContext,
        customInstructions: null,
      );

      final examplesText = includeExamples
          ? await buildFewShotExamples(
              context: context,
              maxExamples: maxExamples,
            )
          : '';

      // Extract source texts for glossary filtering
      final sourceTexts = units.map((u) => u.sourceText).toList();

      // Use new variant-aware glossary if available, otherwise fall back to legacy
      final glossaryText = context.glossaryEntries != null
          ? await buildGlossarySectionWithVariants(
              glossaryEntries: context.glossaryEntries,
              sourceTexts: sourceTexts,
            )
          : await buildGlossarySection(
              glossaryTerms: context.glossaryTerms,
            );

      final formatInstructions = await buildFormatInstructions();

      // Get custom rules if service is available (global + project-specific)
      final customRulesText = await _buildCustomRulesSection(context.projectId);

      final userMessage = await buildUserMessage(units: units);

      // Combine all sections
      final fullSystemMessage = _combineSystemSections(
        systemMessage,
        gameContextText,
        projectContextText,
        glossaryText,
        formatInstructions,
        customRulesText,
      );

      final fullUserMessage = _combineUserSections(
        examplesText,
        userMessage,
      );

      // Calculate actual glossary term count (filtered terms included in prompt)
      final glossaryTermCount = glossaryText.isEmpty
          ? 0
          : glossaryText.split('\n').where((l) => l.startsWith('- "')).length;

      final prompt = BuiltPrompt(
        systemMessage: fullSystemMessage,
        userMessage: fullUserMessage,
        unitCount: units.length,
        metadata: PromptMetadata(
          includesExamples: examplesText.isNotEmpty,
          exampleCount: includeExamples ? maxExamples : 0,
          includesGlossary: glossaryText.isNotEmpty,
          glossaryTermCount: glossaryTermCount,
          includesGameContext: gameContextText.isNotEmpty,
          includesProjectContext: projectContextText.isNotEmpty,
          createdAt: DateTime.now(),
        ),
      );

      return Ok(prompt);
    } catch (e, stackTrace) {
      return Err(
        PromptBuildingException(
          'Failed to build prompt: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<String> buildSystemPrompt({
    required TranslationContext context,
  }) async {
    return '''You are a professional translator specializing in Total War games.

Your task is to translate game text to ${context.targetLanguage}.

CRITICAL RULES:
1. Preserve ALL formatting tags EXACTLY as they appear:
   - Total War color tags: [[col:red]], [[col:yellow]], etc.
   - BBCode tags: [b], [/b], [i], [/i]
   - XML tags: <color=#FF0000>, <b>, </b>
   - Double brackets: [[tag:value]]
2. Preserve ALL variables and placeholders EXACTLY as they appear (e.g., %s, [%s], {0}, \$var)
3. Template expressions {{...}} contain game logic - preserve structure but you MAY translate display strings inside:
   - PRESERVE: function names, property names, operators, syntax (CcoCampaignEventDilemma, GetIfElse, Filter, Size, etc.)
   - MAY TRANSLATE: quoted strings that will display to users (e.g., "Tradeable resources:" → "Ressources échangeables :")
   - Example: {{GetIfElse(x, "Landmarks:", "")}} → {{GetIfElse(x, "Monuments :", "")}}
4. When translating, preserve HYPHENS in compound words. Many languages use hyphenated compound words (e.g., French: "lui-même", "peut-être", "c'est-à-dire"; German: "Halb-Gott"; English: "self-proclaimed"). Output the correct hyphenated form - never merge into one word ("luimême") or split with spaces ("lui même").
5. Maintain the same tone and style as the source
6. Use glossary terms when provided
7. Keep translations culturally appropriate for gaming context
8. Preserve line breaks (\\n) and special characters
9. Do NOT add explanations or notes
10. Output ONLY the JSON response in the specified format
11. If source text has unbalanced tags (e.g., [[/col]] without opening tag), preserve them as-is

EXAMPLES OF TAG PRESERVATION:
- "[[col:red]]Warning" → "[[col:red]]Avertissement"
- "Changes on [%s] lost" → "Modifications sur [%s] perdues"
- "<b>Attack</b>" → "<b>Attaquer</b>"
- "Settings[[/col]]" → "Paramètres[[/col]]" (preserve even if unbalanced)
- "The {{CcoContext:GetIfElse(x, "yes", "no")}} is ready" → "Le {{CcoContext:GetIfElse(x, "oui", "non")}} est prêt" (structure preserved, display strings translated)

QUALITY EXPECTATIONS:
- Accurate: Convey the exact meaning
- Natural: Sound like a native speaker
- Consistent: Use same terminology throughout
- Game-appropriate: Match the epic/historical/fantasy tone''';
  }

  @override
  Future<String> buildGameContext({
    required String? gameContext,
    String? category,
  }) async {
    if (gameContext == null || gameContext.trim().isEmpty) {
      return '';
    }

    return '\nGAME CONTEXT:\n$gameContext';
  }

  @override
  Future<String> buildProjectContext({
    required String? projectContext,
    String? customInstructions,
  }) async {
    final sections = <String>[];

    if (projectContext != null && projectContext.trim().isNotEmpty) {
      sections.add('PROJECT CONTEXT:\n$projectContext');
    }

    if (customInstructions != null && customInstructions.trim().isNotEmpty) {
      sections.add('CUSTOM INSTRUCTIONS:\n$customInstructions');
    }

    if (sections.isEmpty) return '';

    return '\n${sections.join('\n\n')}';
  }

  @override
  Future<String> buildFewShotExamples({
    required TranslationContext context,
    int maxExamples = 3,
    String? category,
  }) async {
    final examples = context.fewShotExamples;

    if (examples == null || examples.isEmpty) {
      return '';
    }

    final limitedExamples = examples.take(maxExamples).toList();
    final examplesText = StringBuffer();

    examplesText.writeln('\nEXAMPLES (for reference):');
    for (var i = 0; i < limitedExamples.length; i++) {
      final example = limitedExamples[i];
      final source = example['source'] ?? '';
      final target = example['target'] ?? '';

      examplesText.writeln('${i + 1}. Source: "$source"');
      examplesText.writeln('   Target: "$target"');
    }

    return examplesText.toString();
  }

  @override
  Future<String> buildGlossarySection({
    required Map<String, String>? glossaryTerms,
  }) async {
    if (glossaryTerms == null || glossaryTerms.isEmpty) {
      return '';
    }

    final glossaryText = StringBuffer();
    glossaryText.writeln('\nGLOSSARY (must use these translations):');

    glossaryTerms.forEach((source, target) {
      // Check if target includes notes in format "translation [Note: ...]"
      final noteMatch = RegExp(r'^(.+?) \[Note: (.+)\]$').firstMatch(target);
      if (noteMatch != null) {
        final translation = noteMatch.group(1)!;
        final note = noteMatch.group(2)!;
        glossaryText.writeln('- "$source" → "$translation"');
        glossaryText.writeln('  Context: $note');
      } else {
        glossaryText.writeln('- "$source" → "$target"');
      }
    });

    return glossaryText.toString();
  }

  @override
  Future<String> buildGlossarySectionWithVariants({
    required List<GlossaryTermWithVariants>? glossaryEntries,
    required List<String> sourceTexts,
  }) async {
    if (glossaryEntries == null || glossaryEntries.isEmpty) {
      return '';
    }

    // Concatenate source texts for matching
    final combinedText = sourceTexts.join(' ');

    // Convert glossary entries to GlossaryEntry format for matcher
    final allEntries = <GlossaryEntry>[];
    for (final term in glossaryEntries) {
      for (final variant in term.variants) {
        allEntries.add(GlossaryEntry(
          id: variant.entryId,
          glossaryId: '', // Not needed for matching
          targetLanguageCode: '', // Not needed for matching
          sourceTerm: term.sourceTerm,
          targetTerm: variant.targetTerm,
          caseSensitive: term.caseSensitive,
          notes: variant.notes,
          createdAt: 0,
          updatedAt: 0,
        ));
      }
    }

    // Find matches in combined text
    final matches = GlossaryMatcher.findMatches(
      text: combinedText,
      entries: allEntries,
      wholeWordOnly: true,
    );

    if (matches.isEmpty) {
      return '';
    }

    // Get unique matched source terms (case-insensitive)
    final matchedSourceTerms = matches
        .map((m) => m.entry.sourceTerm.toLowerCase())
        .toSet();

    // Filter to only matched glossary entries
    final relevantEntries = glossaryEntries
        .where((e) => matchedSourceTerms.contains(e.sourceTerm.toLowerCase()))
        .toList();

    if (relevantEntries.isEmpty) {
      return '';
    }

    // Increment usage count for matched glossary entries
    if (_glossaryRepository != null) {
      final matchedEntryIds = <String>[];
      for (final entry in relevantEntries) {
        for (final variant in entry.variants) {
          matchedEntryIds.add(variant.entryId);
        }
      }
      if (matchedEntryIds.isNotEmpty) {
        try {
          await _glossaryRepository.incrementUsageCount(matchedEntryIds);
        } catch (e) {
          // Non-critical: stats update failure shouldn't block translation
          // Log the error for debugging purposes
          // ignore: avoid_print
          print('[PromptBuilder] Failed to increment glossary usage: $e');
        }
      }
    }

    // Build formatted glossary section
    final glossaryText = StringBuffer();
    glossaryText.writeln('\nGLOSSARY (must use these translations):');

    for (final entry in relevantEntries) {
      glossaryText.writeln('- ${entry.formatForPrompt()}');
    }

    return glossaryText.toString();
  }

  @override
  Future<String> buildFormatInstructions() async {
    return '''

OUTPUT FORMAT (JSON only, no other text):
{
  "translations": [
    {"key": "key1", "translation": "translated text 1"},
    {"key": "key2", "translation": "translated text 2"}
  ]
}''';
  }

  @override
  Future<String> buildUserMessage({
    required List<TranslationUnit> units,
  }) async {
    if (units.isEmpty) {
      throw InvalidContextException(
        'Cannot build user message with empty units list',
      );
    }

    final message = StringBuffer();
    message.writeln('Translate the following ${units.length} text entries:\n');

    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      message.writeln('${i + 1}. Key: "${unit.key}"');
      message.writeln('   Source: "${unit.sourceText}"');

      if (i < units.length - 1) {
        message.writeln();
      }
    }

    return message.toString();
  }

  @override
  Future<Result<BuiltPrompt, PromptBuildingException>> optimizePrompt({
    required BuiltPrompt prompt,
    required int maxTokens,
    required String providerCode,
  }) async {
    try {
      // Calculate current token count
      final currentTokens = _tokenCalculator.calculateTokens(
        '${prompt.systemMessage}\n\n${prompt.userMessage}',
      );

      if (currentTokens <= maxTokens) {
        // Already within limits
        return Ok(prompt);
      }

      // Strategy 1: Remove examples if present
      if (prompt.metadata.includesExamples) {
        final optimized = await _removeExamples(prompt);
        final newTokens = _tokenCalculator.calculateTokens(
          '${optimized.systemMessage}\n\n${optimized.userMessage}',
        );

        if (newTokens <= maxTokens) {
          return Ok(optimized);
        }
      }

      // Strategy 2: Shorten contexts
      final shortened = await _shortenContexts(prompt);
      final shortenedTokens = _tokenCalculator.calculateTokens(
        '${shortened.systemMessage}\n\n${shortened.userMessage}',
      );

      if (shortenedTokens <= maxTokens) {
        return Ok(shortened);
      }

      // Cannot optimize further - prompt is too large
      return Err(
        PromptBuildingException(
          'Cannot optimize prompt to fit within $maxTokens tokens '
          '(current: $currentTokens, after optimization: $shortenedTokens)',
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        PromptBuildingException(
          'Failed to optimize prompt: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<int> estimateTokens({
    required BuiltPrompt prompt,
    required String providerCode,
  }) async {
    return _tokenCalculator.calculateTokens(
      '${prompt.systemMessage}\n\n${prompt.userMessage}',
    );
  }

  @override
  Future<List<ValidationError>> validatePrompt({
    required BuiltPrompt prompt,
  }) async {
    final errors = <ValidationError>[];

    // Check system message
    if (prompt.systemMessage.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        field: 'systemMessage',
        message: 'System message cannot be empty',
      ));
    }

    // Check user message
    if (prompt.userMessage.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        field: 'userMessage',
        message: 'User message cannot be empty',
      ));
    }

    // Check unit count
    if (prompt.unitCount <= 0) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        field: 'unitCount',
        message: 'Must have at least one unit to translate',
      ));
    }

    // Check for reasonable size limits
    const maxSystemLength = 50000; // ~12k tokens
    const maxUserLength = 150000; // ~37k tokens

    if (prompt.systemMessage.length > maxSystemLength) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        field: 'systemMessage',
        message: 'System message exceeds maximum length '
            '(${prompt.systemMessage.length} > $maxSystemLength)',
      ));
    }

    if (prompt.userMessage.length > maxUserLength) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        field: 'userMessage',
        message: 'User message exceeds maximum length '
            '(${prompt.userMessage.length} > $maxUserLength)',
      ));
    }

    return errors;
  }

  /// Combine system message sections into full system prompt
  String _combineSystemSections(
    String systemMessage,
    String gameContext,
    String projectContext,
    String glossary,
    String formatInstructions,
    String customRules,
  ) {
    final sections = <String>[systemMessage];

    if (gameContext.isNotEmpty) sections.add(gameContext);
    if (projectContext.isNotEmpty) sections.add(projectContext);
    if (glossary.isNotEmpty) sections.add(glossary);
    sections.add(formatInstructions);
    // Custom rules are added at the very end
    if (customRules.isNotEmpty) sections.add(customRules);

    return sections.join('\n');
  }

  /// Build custom rules section from user-defined rules
  ///
  /// Includes both global rules and project-specific rules.
  /// Global rules are applied first, followed by project-specific rules.
  ///
  /// Returns formatted section with all enabled custom rules,
  /// or empty string if no rules are enabled or service unavailable.
  Future<String> _buildCustomRulesSection(String projectId) async {
    if (_customRulesService == null) return '';

    final rulesText = await _customRulesService.getCombinedRulesTextForProject(projectId);
    if (rulesText.isEmpty) return '';

    return '''
CUSTOM TRANSLATION RULES:
$rulesText''';
  }

  /// Combine user message sections
  String _combineUserSections(String examples, String userMessage) {
    if (examples.isEmpty) return userMessage;
    return '$examples\n\n$userMessage';
  }

  /// Remove few-shot examples from prompt
  Future<BuiltPrompt> _removeExamples(BuiltPrompt prompt) async {
    // Remove "EXAMPLES" section from system message
    final systemLines = prompt.systemMessage.split('\n');
    final filteredLines = <String>[];
    bool inExamplesSection = false;

    for (final line in systemLines) {
      if (line.startsWith('EXAMPLES')) {
        inExamplesSection = true;
        continue;
      }

      if (inExamplesSection && line.trim().isEmpty) {
        inExamplesSection = false;
        continue;
      }

      if (!inExamplesSection) {
        filteredLines.add(line);
      }
    }

    return BuiltPrompt(
      systemMessage: filteredLines.join('\n'),
      userMessage: prompt.userMessage,
      unitCount: prompt.unitCount,
      metadata: PromptMetadata(
        includesExamples: false,
        exampleCount: 0,
        includesGlossary: prompt.metadata.includesGlossary,
        glossaryTermCount: prompt.metadata.glossaryTermCount,
        includesGameContext: prompt.metadata.includesGameContext,
        includesProjectContext: prompt.metadata.includesProjectContext,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Shorten context sections to reduce token count
  Future<BuiltPrompt> _shortenContexts(BuiltPrompt prompt) async {
    // Remove game and project contexts if present
    final systemLines = prompt.systemMessage.split('\n');
    final filteredLines = <String>[];
    bool inContextSection = false;

    for (final line in systemLines) {
      if (line.startsWith('GAME CONTEXT:') ||
          line.startsWith('PROJECT CONTEXT:') ||
          line.startsWith('CUSTOM INSTRUCTIONS:')) {
        inContextSection = true;
        continue;
      }

      if (inContextSection && (line.trim().isEmpty || line.startsWith('GLOSSARY'))) {
        inContextSection = false;
      }

      if (!inContextSection) {
        filteredLines.add(line);
      }
    }

    return BuiltPrompt(
      systemMessage: filteredLines.join('\n'),
      userMessage: prompt.userMessage,
      unitCount: prompt.unitCount,
      metadata: PromptMetadata(
        includesExamples: prompt.metadata.includesExamples,
        exampleCount: prompt.metadata.exampleCount,
        includesGlossary: prompt.metadata.includesGlossary,
        glossaryTermCount: prompt.metadata.glossaryTermCount,
        includesGameContext: false,
        includesProjectContext: false,
        createdAt: DateTime.now(),
      ),
    );
  }
}
