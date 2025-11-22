import '../../models/history/diff_models.dart';

/// Calculates character-level differences between two text strings
///
/// Uses a simplified Myers diff algorithm for efficient character-level
/// comparison. Suitable for text up to 10k characters.
class DiffCalculator {
  /// Calculate character-level diff between two strings
  ///
  /// Returns list of segments with their type (unchanged, added, removed).
  /// The segments can be used to reconstruct both original strings.
  ///
  /// [oldText] - Original text
  /// [newText] - Modified text
  ///
  /// Returns list of DiffSegment objects
  static List<DiffSegment> calculateDiff(String oldText, String newText) {
    // Handle edge cases
    if (oldText == newText) {
      return [DiffSegment(text: oldText, type: DiffType.unchanged)];
    }

    if (oldText.isEmpty) {
      return [DiffSegment(text: newText, type: DiffType.added)];
    }

    if (newText.isEmpty) {
      return [DiffSegment(text: oldText, type: DiffType.removed)];
    }

    // Use LCS (Longest Common Subsequence) algorithm
    final lcs = _longestCommonSubsequence(oldText, newText);
    return _buildDiffFromLCS(oldText, newText, lcs);
  }

  /// Calculate longest common subsequence between two strings
  ///
  /// This is a classic dynamic programming algorithm that finds the
  /// longest sequence of characters that appear in the same order
  /// in both strings.
  static String _longestCommonSubsequence(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;

    // Create DP table
    final dp = List.generate(
      m + 1,
      (_) => List.filled(n + 1, 0),
    );

    // Fill DP table
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack to build LCS
    final lcs = StringBuffer();
    var i = m;
    var j = n;

    while (i > 0 && j > 0) {
      if (s1[i - 1] == s2[j - 1]) {
        lcs.write(s1[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    // LCS was built backwards, so reverse it
    return lcs.toString().split('').reversed.join('');
  }

  /// Build diff segments from LCS
  static List<DiffSegment> _buildDiffFromLCS(
    String oldText,
    String newText,
    String lcs,
  ) {
    final segments = <DiffSegment>[];
    var oldPos = 0;
    var newPos = 0;
    var lcsPos = 0;

    while (lcsPos < lcs.length) {
      final char = lcs[lcsPos];

      // Find next occurrence in old text
      final oldNextPos = oldText.indexOf(char, oldPos);
      if (oldNextPos > oldPos) {
        // Characters removed
        segments.add(DiffSegment(
          text: oldText.substring(oldPos, oldNextPos),
          type: DiffType.removed,
        ));
        oldPos = oldNextPos;
      }

      // Find next occurrence in new text
      final newNextPos = newText.indexOf(char, newPos);
      if (newNextPos > newPos) {
        // Characters added
        segments.add(DiffSegment(
          text: newText.substring(newPos, newNextPos),
          type: DiffType.added,
        ));
        newPos = newNextPos;
      }

      // Add unchanged character
      segments.add(DiffSegment(
        text: char,
        type: DiffType.unchanged,
      ));

      oldPos++;
      newPos++;
      lcsPos++;
    }

    // Add remaining removed characters
    if (oldPos < oldText.length) {
      segments.add(DiffSegment(
        text: oldText.substring(oldPos),
        type: DiffType.removed,
      ));
    }

    // Add remaining added characters
    if (newPos < newText.length) {
      segments.add(DiffSegment(
        text: newText.substring(newPos),
        type: DiffType.added,
      ));
    }

    // Merge consecutive segments of same type
    return _mergeConsecutiveSegments(segments);
  }

  /// Merge consecutive segments of the same type
  ///
  /// This optimization reduces the number of segments by combining
  /// adjacent segments with the same type.
  static List<DiffSegment> _mergeConsecutiveSegments(
    List<DiffSegment> segments,
  ) {
    if (segments.isEmpty) return segments;

    final merged = <DiffSegment>[];
    var current = segments[0];

    for (var i = 1; i < segments.length; i++) {
      final next = segments[i];

      if (current.type == next.type) {
        // Merge with current segment
        current = DiffSegment(
          text: current.text + next.text,
          type: current.type,
        );
      } else {
        // Start new segment
        merged.add(current);
        current = next;
      }
    }

    // Add final segment
    merged.add(current);

    return merged;
  }

  /// Calculate word-level diff (for display purposes)
  ///
  /// This is a simpler word-based comparison that's easier to read
  /// for longer texts.
  static List<DiffSegment> calculateWordDiff(String oldText, String newText) {
    final oldWords = _splitWords(oldText);
    final newWords = _splitWords(newText);

    final lcs = _longestCommonSubsequenceList(oldWords, newWords);
    return _buildWordDiffFromLCS(oldWords, newWords, lcs);
  }

  /// Split text into words, preserving whitespace
  static List<String> _splitWords(String text) {
    final words = <String>[];
    final buffer = StringBuffer();
    var inWord = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final isWhitespace = char.trim().isEmpty;

      if (isWhitespace && inWord) {
        // End of word
        words.add(buffer.toString());
        buffer.clear();
        buffer.write(char);
        inWord = false;
      } else if (!isWhitespace && !inWord) {
        // Start of word
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
        buffer.write(char);
        inWord = true;
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      words.add(buffer.toString());
    }

    return words;
  }

  /// LCS for lists of strings
  static List<String> _longestCommonSubsequenceList(
    List<String> list1,
    List<String> list2,
  ) {
    final m = list1.length;
    final n = list2.length;

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (list1[i - 1] == list2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    final lcs = <String>[];
    var i = m;
    var j = n;

    while (i > 0 && j > 0) {
      if (list1[i - 1] == list2[j - 1]) {
        lcs.insert(0, list1[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return lcs;
  }

  /// Build word diff from LCS
  static List<DiffSegment> _buildWordDiffFromLCS(
    List<String> oldWords,
    List<String> newWords,
    List<String> lcs,
  ) {
    final segments = <DiffSegment>[];
    var oldPos = 0;
    var newPos = 0;
    var lcsPos = 0;

    while (lcsPos < lcs.length) {
      final word = lcs[lcsPos];

      // Find next occurrence in old words
      while (oldPos < oldWords.length && oldWords[oldPos] != word) {
        segments.add(DiffSegment(
          text: oldWords[oldPos],
          type: DiffType.removed,
        ));
        oldPos++;
      }

      // Find next occurrence in new words
      while (newPos < newWords.length && newWords[newPos] != word) {
        segments.add(DiffSegment(
          text: newWords[newPos],
          type: DiffType.added,
        ));
        newPos++;
      }

      // Add unchanged word
      if (oldPos < oldWords.length && newPos < newWords.length) {
        segments.add(DiffSegment(
          text: word,
          type: DiffType.unchanged,
        ));
        oldPos++;
        newPos++;
      }

      lcsPos++;
    }

    // Add remaining removed words
    while (oldPos < oldWords.length) {
      segments.add(DiffSegment(
        text: oldWords[oldPos],
        type: DiffType.removed,
      ));
      oldPos++;
    }

    // Add remaining added words
    while (newPos < newWords.length) {
      segments.add(DiffSegment(
        text: newWords[newPos],
        type: DiffType.added,
      ));
      newPos++;
    }

    return segments;
  }
}
