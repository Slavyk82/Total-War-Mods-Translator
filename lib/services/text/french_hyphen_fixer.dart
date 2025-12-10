import 'dart:convert';

import 'package:flutter/services.dart';

import '../database/database_service.dart';
import '../shared/logging_service.dart';

/// Model for a single hyphen pattern.
class HyphenPattern {
  final String incorrect;
  final String correct;

  const HyphenPattern({required this.incorrect, required this.correct});

  factory HyphenPattern.fromJson(Map<String, dynamic> json) {
    return HyphenPattern(
      incorrect: json['incorrect'] as String,
      correct: json['correct'] as String,
    );
  }
}

/// Service to fix missing hyphens in French translations.
///
/// French language uses hyphens extensively in compound words, reflexive
/// pronouns, dialogue inversions, and common expressions. LLM translations
/// sometimes omit these hyphens.
///
/// This service runs at application startup to restore missing hyphens
/// in existing French translations.
class FrenchHyphenFixer {
  FrenchHyphenFixer._();

  static const String _assetPath = 'assets/data/french_hyphen_patterns.json';

  /// Cached hyphen patterns loaded from JSON asset.
  static List<HyphenPattern>? _cachedPatterns;

  /// Load hyphen patterns from JSON asset file.
  ///
  /// Patterns are cached after first load for performance.
  static Future<List<HyphenPattern>> _loadPatterns() async {
    if (_cachedPatterns != null) {
      return _cachedPatterns!;
    }

    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final patternsList = jsonData['patterns'] as List<dynamic>;

      _cachedPatterns = patternsList
          .map((p) => HyphenPattern.fromJson(p as Map<String, dynamic>))
          .toList();

      LoggingService.instance.debug(
        'Loaded ${_cachedPatterns!.length} French hyphen patterns from asset',
      );

      return _cachedPatterns!;
    } catch (e, stackTrace) {
      LoggingService.instance.error(
        'Failed to load French hyphen patterns from asset',
        e,
        stackTrace,
      );
      return [];
    }
  }

  /// Fix missing hyphens in French translations.
  ///
  /// Scans all French translations and restores missing hyphens
  /// using pattern matching. Only updates records that actually change.
  ///
  /// Returns the number of translations fixed.
  static Future<int> fixMissingHyphens() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for missing hyphens in French translations...');

      // Load patterns from JSON asset
      final hyphenPatterns = await _loadPatterns();
      if (hyphenPatterns.isEmpty) {
        logging.warning('No hyphen patterns loaded, skipping hyphen fix');
        return 0;
      }

      // Get French language project_language IDs
      final frenchProjectLanguages = await DatabaseService.database.rawQuery('''
        SELECT pl.id
        FROM project_languages pl
        INNER JOIN languages l ON pl.language_id = l.id
        WHERE l.code = 'fr'
      ''');

      if (frenchProjectLanguages.isEmpty) {
        logging.debug('No French project languages found, skipping hyphen fix');
        return 0;
      }

      final plIds = frenchProjectLanguages.map((r) => "'${r['id']}'").join(',');
      logging.debug(
        'Found ${frenchProjectLanguages.length} French project language(s)',
      );

      // Count potential matches first
      int totalFixed = 0;
      const batchSize = 500;

      // Process each pattern
      for (final pattern in hyphenPatterns) {
        // Skip if pattern already has hyphen (shouldn't happen but safety check)
        if (pattern.incorrect.contains('-')) continue;

        // Build case-insensitive search pattern
        // We need to find the pattern as a whole word/phrase
        final searchPattern = pattern.incorrect.toLowerCase();

        // Find translations with this pattern
        final matches = await DatabaseService.database.rawQuery('''
          SELECT id, translated_text
          FROM translation_versions
          WHERE project_language_id IN ($plIds)
            AND translated_text IS NOT NULL
            AND LOWER(translated_text) LIKE ?
          LIMIT $batchSize
        ''', ['%$searchPattern%']);

        if (matches.isEmpty) continue;

        // Update each match
        for (final row in matches) {
          final id = row['id'] as String;
          final text = row['translated_text'] as String;

          // Apply case-insensitive replacement
          final newText = _replaceIgnoreCase(
            text,
            pattern.incorrect,
            pattern.correct,
          );

          if (newText != text) {
            await DatabaseService.database.rawUpdate('''
              UPDATE translation_versions
              SET translated_text = ?, updated_at = ?
              WHERE id = ?
            ''', [newText, DateTime.now().millisecondsSinceEpoch ~/ 1000, id]);
            totalFixed++;
          }
        }
      }

      if (totalFixed > 0) {
        logging.info('Fixed missing hyphens in $totalFixed French translations');

        // Rebuild FTS index for updated translations
        try {
          await DatabaseService.execute('''
            INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')
          ''').timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              logging.warning('FTS rebuild timed out after hyphen fix');
            },
          );
        } catch (e) {
          logging.warning('FTS rebuild skipped after hyphen fix: $e');
        }
      } else {
        logging.debug('No missing hyphens found in French translations');
      }

      return totalFixed;
    } catch (e, stackTrace) {
      logging.error('Failed to fix French hyphens', e, stackTrace);
      return 0;
    }
  }

  /// Replace text case-insensitively while preserving the original case of surrounding text.
  static String _replaceIgnoreCase(String text, String from, String to) {
    final lowerText = text.toLowerCase();
    final lowerFrom = from.toLowerCase();

    final buffer = StringBuffer();
    int lastEnd = 0;

    int index = lowerText.indexOf(lowerFrom, lastEnd);
    while (index != -1) {
      // Add text before match
      buffer.write(text.substring(lastEnd, index));

      // Check word boundaries to avoid partial matches
      final isWordStart =
          index == 0 || !_isWordChar(text.codeUnitAt(index - 1));
      final isWordEnd = index + from.length >= text.length ||
          !_isWordChar(text.codeUnitAt(index + from.length));

      if (isWordStart && isWordEnd) {
        // Apply replacement, preserving first letter case
        final originalFirst = text[index];
        if (originalFirst.toUpperCase() == originalFirst) {
          // Original starts with uppercase, capitalize replacement
          buffer.write(to[0].toUpperCase());
          buffer.write(to.substring(1));
        } else {
          buffer.write(to);
        }
      } else {
        // Not a word boundary match, keep original
        buffer.write(text.substring(index, index + from.length));
      }

      lastEnd = index + from.length;
      index = lowerText.indexOf(lowerFrom, lastEnd);
    }

    // Add remaining text
    buffer.write(text.substring(lastEnd));

    return buffer.toString();
  }

  /// Check if character is a word character (letter or digit).
  static bool _isWordChar(int codeUnit) {
    // a-z, A-Z, 0-9, or common accented characters
    return (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
        (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0xC0 && codeUnit <= 0xFF); // Latin Extended-A (accents)
  }
}
