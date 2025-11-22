import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Service for building contextual prompts for LLM translation
///
/// This service constructs prompts that include:
/// - System instructions (role, rules, format)
/// - Game-specific context (lore, universe, tone)
/// - Project-specific context (mod type, faction, period)
/// - Few-shot examples from Translation Memory
/// - Glossary terms to preserve
/// - Format instructions for structured output
/// - Token optimization strategies
abstract class IPromptBuilderService {
  /// Build a complete prompt for translating a batch of units
  ///
  /// The prompt includes:
  /// 1. System prompt with role and rules
  /// 2. Game context (if available)
  /// 3. Project context (if available)
  /// 4. Few-shot examples from TM (2-5 examples)
  /// 5. Glossary terms (if any)
  /// 6. Format instructions (JSON output)
  /// 7. Input units to translate
  ///
  /// [units]: Translation units to include in the prompt
  /// [context]: Translation context with game, project, and glossary info
  /// [includeExamples]: Whether to include few-shot examples (default: true)
  /// [maxExamples]: Maximum number of TM examples to include (default: 3)
  ///
  /// Returns:
  /// - [BuiltPrompt] containing system message and user message
  ///
  /// Throws:
  /// - [PromptBuildingException] if prompt construction fails
  /// - [InvalidContextException] if context is invalid
  Future<Result<BuiltPrompt, PromptBuildingException>> buildPrompt({
    required List<TranslationUnit> units,
    required TranslationContext context,
    bool includeExamples = true,
    int maxExamples = 3,
  });

  /// Build system prompt with role and rules
  ///
  /// The system prompt establishes:
  /// - Role: Professional translator for Total War games
  /// - Rules: Preserve formatting, maintain tone, use glossary
  /// - Output format: JSON with specific structure
  /// - Quality expectations
  ///
  /// [context]: Translation context for language pair and category
  ///
  /// Returns the system message text
  Future<String> buildSystemPrompt({
    required TranslationContext context,
  });

  /// Build game-specific context section
  ///
  /// Adds context about the game's:
  /// - Historical period or fantasy setting
  /// - Lore and universe details
  /// - Tone and style (epic, formal, gritty, etc.)
  /// - Cultural references
  ///
  /// [gameContext]: Game-specific context text
  /// [category]: Content category (UI, narrative, tutorial, etc.)
  ///
  /// Returns formatted context text, or empty string if no context
  Future<String> buildGameContext({
    required String? gameContext,
    String? category,
  });

  /// Build project-specific context section
  ///
  /// Adds context about the mod:
  /// - Mod type (overhaul, faction, campaign, etc.)
  /// - Specific faction or nation
  /// - Time period or era
  /// - Custom instructions from project settings
  ///
  /// [projectContext]: Project-specific context text
  /// [customInstructions]: Additional custom instructions
  ///
  /// Returns formatted context text, or empty string if no context
  Future<String> buildProjectContext({
    required String? projectContext,
    String? customInstructions,
  });

  /// Build few-shot examples from Translation Memory
  ///
  /// Selects the best TM matches as examples to guide the LLM.
  /// Examples show source -> target pairs in the same context.
  ///
  /// [context]: Translation context for TM lookup
  /// [maxExamples]: Maximum number of examples to include (2-5)
  /// [category]: Optional category filter
  ///
  /// Returns formatted examples text, or empty string if no examples found
  Future<String> buildFewShotExamples({
    required TranslationContext context,
    int maxExamples = 3,
    String? category,
  });

  /// Build glossary terms section
  ///
  /// Includes glossary terms that must be preserved or translated consistently.
  /// Format: "term (source) -> translation (target)"
  ///
  /// [glossaryTerms]: Map of source terms to target translations
  ///
  /// Returns formatted glossary text, or empty string if no terms
  Future<String> buildGlossarySection({
    required Map<String, String>? glossaryTerms,
  });

  /// Build format instructions for structured output
  ///
  /// Instructs the LLM to output JSON in a specific format:
  /// ```json
  /// {
  ///   "translations": [
  ///     {"key": "key1", "translation": "..."},
  ///     {"key": "key2", "translation": "..."}
  ///   ]
  /// }
  /// ```
  ///
  /// Returns format instructions text
  Future<String> buildFormatInstructions();

  /// Build the user message with units to translate
  ///
  /// Formats the translation units as a structured list:
  /// - Key: unique identifier
  /// - Source: text to translate
  /// - Context: optional contextual info
  ///
  /// [units]: Translation units to include
  ///
  /// Returns formatted user message
  Future<String> buildUserMessage({
    required List<TranslationUnit> units,
  });

  /// Optimize prompt to fit within token limits
  ///
  /// Strategies:
  /// 1. Reduce number of few-shot examples
  /// 2. Shorten context descriptions
  /// 3. Remove less critical information
  /// 4. Split into multiple smaller prompts if necessary
  ///
  /// [prompt]: Original prompt to optimize
  /// [maxTokens]: Maximum allowed tokens
  /// [providerCode]: LLM provider for token calculation
  ///
  /// Returns optimized prompt that fits within limits
  ///
  /// Throws:
  /// - [PromptBuildingException] if prompt cannot be optimized enough
  Future<Result<BuiltPrompt, PromptBuildingException>> optimizePrompt({
    required BuiltPrompt prompt,
    required int maxTokens,
    required String providerCode,
  });

  /// Estimate token count for a prompt
  ///
  /// Uses the appropriate tokenizer for the provider.
  ///
  /// [prompt]: Prompt to estimate
  /// [providerCode]: LLM provider code
  ///
  /// Returns estimated token count
  Future<int> estimateTokens({
    required BuiltPrompt prompt,
    required String providerCode,
  });

  /// Validate that a prompt is well-formed
  ///
  /// Checks:
  /// - System message is not empty
  /// - User message contains units
  /// - No invalid characters or formatting
  /// - Within reasonable size limits
  ///
  /// Returns list of validation errors, or empty list if valid
  Future<List<ValidationError>> validatePrompt({
    required BuiltPrompt prompt,
  });
}

/// A complete prompt ready for LLM translation
class BuiltPrompt {
  /// System message (role, rules, instructions)
  final String systemMessage;

  /// User message (units to translate)
  final String userMessage;

  /// Number of units included in this prompt
  final int unitCount;

  /// Metadata about the prompt
  final PromptMetadata metadata;

  const BuiltPrompt({
    required this.systemMessage,
    required this.userMessage,
    required this.unitCount,
    required this.metadata,
  });

  /// Full prompt text (system + user)
  String get fullPrompt => '$systemMessage\n\n$userMessage';

  /// Estimated total tokens (if calculated)
  int? get estimatedTokens => metadata.estimatedTokens;

  @override
  String toString() {
    return 'BuiltPrompt(units: $unitCount, '
        'systemLength: ${systemMessage.length}, '
        'userLength: ${userMessage.length}, '
        'tokens: ${estimatedTokens ?? "not calculated"})';
  }
}

/// Metadata about a built prompt
class PromptMetadata {
  /// Whether few-shot examples are included
  final bool includesExamples;

  /// Number of few-shot examples
  final int exampleCount;

  /// Whether glossary terms are included
  final bool includesGlossary;

  /// Number of glossary terms
  final int glossaryTermCount;

  /// Whether game context is included
  final bool includesGameContext;

  /// Whether project context is included
  final bool includesProjectContext;

  /// Estimated token count (if calculated)
  final int? estimatedTokens;

  /// Provider code used for token estimation
  final String? providerCode;

  /// Timestamp when prompt was built
  final DateTime createdAt;

  const PromptMetadata({
    required this.includesExamples,
    required this.exampleCount,
    required this.includesGlossary,
    required this.glossaryTermCount,
    required this.includesGameContext,
    required this.includesProjectContext,
    this.estimatedTokens,
    this.providerCode,
    required this.createdAt,
  });

  @override
  String toString() {
    return 'PromptMetadata(examples: $exampleCount, glossary: $glossaryTermCount, '
        'tokens: ${estimatedTokens ?? "N/A"})';
  }
}
