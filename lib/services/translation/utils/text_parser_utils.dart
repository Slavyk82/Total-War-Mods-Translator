/// Utility class for extracting variables, markup tags, and numbers from text
///
/// Used by validation service to check preservation of placeholders
/// and formatting in translations.
class TextParserUtils {
  /// Private constructor - all methods are static
  TextParserUtils._();

  /// Extract variables from text
  ///
  /// Supports:
  /// - {{expression}} (Total War double-brace templates)
  /// - {0}, {1}, {2} (positional)
  /// - {name}, {count} (named)
  /// - %s, %d, %f (printf-style)
  /// - [%s], [%d], [%f] (bracketed printf-style)
  /// - $var, ${var} (template-style)
  static List<String> extractVariables(String text) {
    final variables = <String>[];

    // Total War double-brace templates: {{CcoCampaignEventDilemma:GetIfElse(...)}}
    // These can contain nested braces, so match {{ until }}
    // Pattern: {{ followed by any char except }} until }}
    final doubleBracePattern = RegExp(r'\{\{(?:[^}]|\}(?!\}))*\}\}');
    final doubleBraceMatches = doubleBracePattern.allMatches(text).toList();
    variables.addAll(
      doubleBraceMatches.map((m) => m.group(0)!),
    );

    // Build a set of ranges covered by double-brace matches to avoid double-counting
    final doubleBraceRanges = doubleBraceMatches
        .map((m) => (start: m.start, end: m.end))
        .toList();

    // Positional and named placeholders: {0}, {name}
    // Skip matches that fall within double-brace ranges
    final bracePattern = RegExp(r'\{([^}]+)\}');
    for (final match in bracePattern.allMatches(text)) {
      final isInsideDoubleBrace = doubleBraceRanges.any(
        (r) => match.start >= r.start && match.end <= r.end,
      );
      if (!isInsideDoubleBrace) {
        variables.add(match.group(0)!);
      }
    }

    // Bracketed printf-style: [%s], [%d], [%f], etc.
    // Must be checked BEFORE single printf and BBCode patterns to avoid conflicts
    final bracketedPrintfPattern = RegExp(r'\[%[sdf]\]');
    variables.addAll(
      bracketedPrintfPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Printf-style: %s, %d, %f, etc.
    final printfPattern = RegExp(r'%[sdf]');
    variables.addAll(
      printfPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Template-style: $var, ${var}
    final templatePattern = RegExp(r'\$\{?(\w+)\}?');
    variables.addAll(
      templatePattern.allMatches(text).map((m) => m.group(0)!),
    );

    return variables;
  }


  /// Extract markup tags from text
  ///
  /// Supports:
  /// - XML: `<tag>`, `</tag>`
  /// - BBCode: `[tag]`, `[/tag]`
  /// - Double-bracket: `[[tag]]`, `[[/tag]]`
  ///
  /// Excludes printf-style placeholders like `[%s]` which are variables, not tags
  static List<String> extractMarkupTags(String text) {
    // Collect every match across the three patterns together with its start
    // offset, then sort by start index so the tags are returned in DOCUMENT
    // ORDER. areTagsBalanced is a stack-based nesting check that depends on
    // the true left-to-right sequence; grouping tags by type would mask real
    // imbalances of interleaved tags (e.g. `[[col:red]]<b>text[[/col]]</b>`).
    final entries = <({int start, String tag})>[];

    // XML tags: <tag>, </tag>, <tag attr="value">
    final xmlPattern = RegExp(r'<[^>]+>');
    for (final match in xmlPattern.allMatches(text)) {
      entries.add((start: match.start, tag: match.group(0)!));
    }

    // Double-bracket tags: [[tag:value]], [[/tag]]
    // Must be checked BEFORE single-bracket pattern to avoid partial matches
    final doubleBracketPattern = RegExp(r'\[\[[^\]]+\]\]');
    for (final match in doubleBracketPattern.allMatches(text)) {
      entries.add((start: match.start, tag: match.group(0)!));
    }

    // Single BBCode tags: [tag], [/tag], [tag=value]
    // Use negative lookbehind/lookahead to avoid matching double brackets
    // Match [ but not [[, and ] but not ]]
    // Exclude [%s], [%d], [%f] which are printf-style placeholders, not tags
    final bbcodePattern = RegExp(r'(?<!\[)\[[^\[\]]+\](?!\])');
    for (final match in bbcodePattern.allMatches(text)) {
      final tag = match.group(0)!;
      // Skip if this is a bracketed printf placeholder
      if (!RegExp(r'^\[%[sdf]\]$').hasMatch(tag)) {
        entries.add((start: match.start, tag: tag));
      }
    }

    // Sort by start offset to restore document order before returning.
    entries.sort((a, b) => a.start.compareTo(b.start));

    return entries.map((e) => e.tag).toList();
  }
}
