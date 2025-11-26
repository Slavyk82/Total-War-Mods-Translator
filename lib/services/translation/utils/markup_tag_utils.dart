/// Utility class for markup tag analysis and validation
///
/// Provides methods for checking tag balance and extracting tag names
/// from various markup formats (XML, BBCode, double-bracket).
class MarkupTagUtils {
  /// Private constructor - all methods are static
  MarkupTagUtils._();

  /// Check if markup tags are balanced
  ///
  /// Returns true if all opening tags have corresponding closing tags
  /// in the correct order.
  static bool areTagsBalanced(List<String> tags) {
    final stack = <String>[];

    for (final tag in tags) {
      // Self-closing tags (e.g., <br/>, <img/>)
      if (tag.endsWith('/>')) {
        continue; // Self-closing, no need to track
      }

      // Closing tags (including double-bracket [[/tag]])
      if (tag.startsWith('</') ||
          tag.startsWith('[/') ||
          tag.startsWith('[[/')) {
        final tagName = extractTagName(tag);
        if (stack.isEmpty) return false;

        final expectedOpening = stack.removeLast();
        final expectedName = extractTagName(expectedOpening);

        // Check if closing tag matches opening tag
        if (tagName != expectedName) {
          return false;
        }
      } else {
        // Opening tag (including tags with attributes like [tag=value])
        stack.add(tag);
      }
    }

    return stack.isEmpty;
  }

  /// Extract tag name from a markup tag
  ///
  /// Examples:
  /// - <b> -> b
  /// - </b> -> b
  /// - <div class="foo"> -> div
  /// - <color=#FF0000> -> color
  /// - [color=red] -> color
  /// - [/color] -> color
  /// - [[col:red]] -> col
  /// - [[/col]] -> col
  static String extractTagName(String tag) {
    // XML/HTML tags
    if (tag.startsWith('<')) {
      return _extractXmlTagName(tag);
    }

    // BBCode tags (including double-bracket style [[tag]])
    if (tag.startsWith('[')) {
      return _extractBbcodeTagName(tag);
    }

    return tag;
  }

  /// Extract tag name from XML/HTML tag
  static String _extractXmlTagName(String tag) {
    // Remove < and > and / if present
    var name = tag.substring(1);
    if (name.startsWith('/')) {
      name = name.substring(1);
    }
    if (name.endsWith('>')) {
      name = name.substring(0, name.length - 1);
    }
    // Remove self-closing marker
    if (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    // Remove attributes (everything after first space or =)
    var cutIndex = name.indexOf(' ');
    final equalsIndex = name.indexOf('=');
    if (equalsIndex != -1 && (cutIndex == -1 || equalsIndex < cutIndex)) {
      cutIndex = equalsIndex;
    }
    if (cutIndex != -1) {
      name = name.substring(0, cutIndex);
    }
    return name.trim();
  }

  /// Extract tag name from BBCode tag (single or double bracket)
  static String _extractBbcodeTagName(String tag) {
    // Remove outer brackets
    var name = tag.substring(1);
    if (name.endsWith(']')) {
      name = name.substring(0, name.length - 1);
    }

    // For double-bracket tags: [[col:red]] -> [col:red], [[/col]] -> [/col]
    // We'll keep the inner bracket as part of the tag name

    // First, handle the slash for closing tags
    // [[/col]] -> [col] (after outer bracket removal we have [/col])
    if (name.startsWith('[/')) {
      name = name.substring(2); // Remove [/
      // Also remove trailing ] for double-bracket tags
      if (name.endsWith(']')) {
        name = name.substring(0, name.length - 1);
      }
    } else if (name.startsWith('/')) {
      name = name.substring(1); // Remove /
    } else if (name.startsWith('[')) {
      name = name.substring(1); // Remove [ for double-bracket opening
      // Also remove trailing ] for double-bracket tags
      if (name.endsWith(']')) {
        name = name.substring(0, name.length - 1);
      }
    }

    // Remove attributes (everything after = or :)
    var cutIndex = name.indexOf('=');
    final colonIndex = name.indexOf(':');
    if (colonIndex != -1 && (cutIndex == -1 || colonIndex < cutIndex)) {
      cutIndex = colonIndex;
    }
    if (cutIndex != -1) {
      name = name.substring(0, cutIndex);
    }

    return name.trim();
  }
}
