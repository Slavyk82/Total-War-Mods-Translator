import 'package:twmt/models/domain/glossary_entry.dart';

/// Match result for a glossary term found in text
class GlossaryMatch {
  /// The glossary entry that matched
  final GlossaryEntry entry;

  /// Start position in the text
  final int startIndex;

  /// End position in the text (exclusive)
  final int endIndex;

  /// Matched text (exact substring from source)
  final String matchedText;

  const GlossaryMatch({
    required this.entry,
    required this.startIndex,
    required this.endIndex,
    required this.matchedText,
  });

  /// Length of the matched text
  int get length => endIndex - startIndex;

  @override
  String toString() {
    return 'GlossaryMatch(term: "${entry.sourceTerm}", '
        'matched: "$matchedText", pos: $startIndex-$endIndex)';
  }
}

/// Utility for matching glossary terms in text
///
/// Supports:
/// - Case-sensitive and case-insensitive matching
/// - Whole word matching (prevents partial matches)
/// - Multiple matches per term
/// - Overlapping match detection
/// - Longest match priority
class GlossaryMatcher {
  /// Find all glossary term matches in the source text
  ///
  /// [text] - Text to search for glossary terms
  /// [entries] - List of glossary entries to search for
  /// [wholeWordOnly] - If true, only match complete words
  ///
  /// Returns list of matches sorted by position
  static List<GlossaryMatch> findMatches({
    required String text,
    required List<GlossaryEntry> entries,
    bool wholeWordOnly = true,
  }) {
    final matches = <GlossaryMatch>[];

    // Sort entries by term length (descending) to prioritize longer matches
    final sortedEntries = List<GlossaryEntry>.from(entries)
      ..sort((a, b) => b.sourceTerm.length.compareTo(a.sourceTerm.length));

    for (final entry in sortedEntries) {
      final termMatches = _findTermMatches(
        text: text,
        entry: entry,
        wholeWordOnly: wholeWordOnly,
      );
      matches.addAll(termMatches);
    }

    // Remove overlapping matches (keep longest/first)
    final nonOverlapping = _removeOverlaps(matches);

    // Sort by position
    nonOverlapping.sort((a, b) => a.startIndex.compareTo(b.startIndex));

    return nonOverlapping;
  }

  /// Find all occurrences of a specific term in text
  static List<GlossaryMatch> _findTermMatches({
    required String text,
    required GlossaryEntry entry,
    bool wholeWordOnly = true,
  }) {
    final matches = <GlossaryMatch>[];
    final searchText = entry.caseSensitive ? text : text.toLowerCase();
    final searchTerm =
        entry.caseSensitive ? entry.sourceTerm : entry.sourceTerm.toLowerCase();

    int startIndex = 0;
    while (true) {
      final index = searchText.indexOf(searchTerm, startIndex);
      if (index == -1) break;

      final endIndex = index + searchTerm.length;

      // Check if whole word match is required
      if (wholeWordOnly) {
        final isWholeWord = _isWholeWordMatch(
          text: searchText,
          startIndex: index,
          endIndex: endIndex,
        );
        if (!isWholeWord) {
          startIndex = index + 1;
          continue;
        }
      }

      matches.add(GlossaryMatch(
        entry: entry,
        startIndex: index,
        endIndex: endIndex,
        matchedText: text.substring(index, endIndex),
      ));

      startIndex = endIndex;
    }

    return matches;
  }

  /// Check if a match is a whole word (not part of a larger word)
  static bool _isWholeWordMatch({
    required String text,
    required int startIndex,
    required int endIndex,
  }) {
    // Check character before match
    if (startIndex > 0) {
      final charBefore = text[startIndex - 1];
      if (_isWordCharacter(charBefore)) {
        return false;
      }
    }

    // Check character after match
    if (endIndex < text.length) {
      final charAfter = text[endIndex];
      if (_isWordCharacter(charAfter)) {
        return false;
      }
    }

    return true;
  }

  /// Check if a character is a word character (letter, digit, underscore)
  static bool _isWordCharacter(String char) {
    final code = char.codeUnitAt(0);

    // A-Z, a-z
    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
      return true;
    }

    // 0-9
    if (code >= 48 && code <= 57) {
      return true;
    }

    // Underscore
    if (code == 95) {
      return true;
    }

    // Extended Unicode letters (accented characters, etc.)
    if (code > 127) {
      return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char);
    }

    return false;
  }

  /// Remove overlapping matches, keeping the longest or first match
  static List<GlossaryMatch> _removeOverlaps(List<GlossaryMatch> matches) {
    if (matches.isEmpty) return matches;

    // Sort by start position, then by length (descending)
    final sorted = List<GlossaryMatch>.from(matches)
      ..sort((a, b) {
        final posCompare = a.startIndex.compareTo(b.startIndex);
        if (posCompare != 0) return posCompare;
        return b.length.compareTo(a.length); // Longer matches first
      });

    final result = <GlossaryMatch>[];
    int lastEndIndex = -1;

    for (final match in sorted) {
      // Skip if overlaps with previous match
      if (match.startIndex < lastEndIndex) {
        continue;
      }

      result.add(match);
      lastEndIndex = match.endIndex;
    }

    return result;
  }

  /// Apply glossary substitutions to target text
  ///
  /// Replaces matched terms in target text with glossary translations.
  ///
  /// [sourceText] - Original source text
  /// [targetText] - Translation to apply substitutions to
  /// [matches] - List of glossary matches from source text
  ///
  /// Returns modified target text with substitutions
  static String applySubstitutions({
    required String sourceText,
    required String targetText,
    required List<GlossaryMatch> matches,
  }) {
    if (matches.isEmpty) return targetText;

    // Sort matches by position (descending) to apply from end to start
    // This prevents index shifting issues
    final sortedMatches = List<GlossaryMatch>.from(matches)
      ..sort((a, b) => b.startIndex.compareTo(a.startIndex));

    String result = targetText;

    for (final match in sortedMatches) {
      // Find the corresponding position in target text
      // This is a simplistic approach - in reality, translation may reorder words
      // For now, we'll just do a case-insensitive search and replace
      final sourceTermEscaped = RegExp.escape(match.matchedText);
      final pattern = RegExp(
        sourceTermEscaped,
        caseSensitive: match.entry.caseSensitive,
      );

      result = result.replaceAll(pattern, match.entry.targetTerm);
    }

    return result;
  }

  /// Highlight glossary terms in text (for UI display)
  ///
  /// [text] - Text to highlight
  /// [matches] - List of glossary matches
  /// [highlightPrefix] - String to insert before match (e.g., '<mark>')
  /// [highlightSuffix] - String to insert after match (e.g., '</mark>')
  ///
  /// Returns text with highlights inserted
  static String highlightMatches({
    required String text,
    required List<GlossaryMatch> matches,
    String highlightPrefix = '**',
    String highlightSuffix = '**',
  }) {
    if (matches.isEmpty) return text;

    // Sort matches by position (descending) to insert from end to start
    final sortedMatches = List<GlossaryMatch>.from(matches)
      ..sort((a, b) => b.startIndex.compareTo(a.startIndex));

    String result = text;

    for (final match in sortedMatches) {
      result = result.substring(0, match.startIndex) +
          highlightPrefix +
          result.substring(match.startIndex, match.endIndex) +
          highlightSuffix +
          result.substring(match.endIndex);
    }

    return result;
  }

  /// Get statistics about glossary matches
  ///
  /// Returns:
  /// - totalMatches: Total number of matches found
  /// - uniqueTerms: Number of unique glossary terms matched
  /// - coveragePercent: Percentage of text covered by glossary terms
  static Map<String, dynamic> getMatchStatistics({
    required String text,
    required List<GlossaryMatch> matches,
  }) {
    if (text.isEmpty) {
      return {
        'totalMatches': 0,
        'uniqueTerms': 0,
        'coveragePercent': 0.0,
      };
    }

    final uniqueTerms = <String>{};
    int totalCoveredChars = 0;

    for (final match in matches) {
      uniqueTerms.add(match.entry.sourceTerm);
      totalCoveredChars += match.length;
    }

    final coveragePercent = (totalCoveredChars / text.length) * 100;

    return {
      'totalMatches': matches.length,
      'uniqueTerms': uniqueTerms.length,
      'coveragePercent': coveragePercent,
    };
  }
}
