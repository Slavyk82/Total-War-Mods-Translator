// Script to fix reformatted numbers in existing translations
// e.g., "13140" in source becoming "13 140" in translation
//
// Run with: dart run fix_reformatted_numbers.dart

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

/// Regular expression to find numbers in text
final _numberPattern = RegExp(r'\d+');

/// Find the formatted version of a number in text
/// e.g., find "13 140" when looking for "13140"
String? _findFormattedNumber(String text, String number) {
  // Build a regex pattern that matches the number with optional separators
  // For "13140", match "1[sep]?3[sep]?1[sep]?4[sep]?0"
  const separatorPattern = r'[\s\u00A0\u202F,.]?';
  final patternStr = number.split('').join(separatorPattern);
  final pattern = RegExp(patternStr);

  final match = pattern.firstMatch(text);
  if (match != null) {
    final found = match.group(0)!;
    // Only return if it actually contains separators (is different from source)
    if (found != number &&
        found.replaceAll(RegExp(r'[\s\u00A0\u202F,.]'), '') == number) {
      return found;
    }
  }
  return null;
}

/// Fix modified numbers by replacing formatted versions with original
String _fixModifiedNumbers(String text, Map<String, String> modifiedNumbers) {
  String result = text;
  for (final entry in modifiedNumbers.entries) {
    final original = entry.key;
    final formatted = entry.value;
    result = result.replaceAll(formatted, original);
  }
  return result;
}

/// Detect and fix reformatted numbers
/// Returns the fixed text, or null if no changes needed
String? detectAndFixNumbers(String sourceText, String translatedText) {
  final sourceNumbers =
      _numberPattern.allMatches(sourceText).map((m) => m.group(0)!).toList();

  final translatedNumbers = _numberPattern
      .allMatches(translatedText)
      .map((m) => m.group(0)!)
      .toList();

  // Check for exact number preservation
  final sourceNumbersSet = sourceNumbers.toSet();
  final translatedNumbersSet = translatedNumbers.toSet();

  final missingNumbers =
      sourceNumbersSet.difference(translatedNumbersSet).toList();

  // Check if missing numbers might have been reformatted with separators
  final modifiedNumbers = <String, String>{};

  for (final sourceNum in missingNumbers) {
    // Check if the number might have been split by spaces/separators
    final normalizedTranslated = translatedText
        .replaceAll(' ', '')
        .replaceAll('\u00A0', '') // non-breaking space
        .replaceAll('\u202F', '') // narrow non-breaking space
        .replaceAll(',', '')
        .replaceAll('.', '');

    if (normalizedTranslated.contains(sourceNum)) {
      // The number exists when separators are removed - it was reformatted
      final formattedVersion = _findFormattedNumber(translatedText, sourceNum);
      if (formattedVersion != null && formattedVersion != sourceNum) {
        modifiedNumbers[sourceNum] = formattedVersion;
      }
    }
  }

  if (modifiedNumbers.isNotEmpty) {
    return _fixModifiedNumbers(translatedText, modifiedNumbers);
  }

  return null;
}

Future<void> main() async {
  // Initialize SQLite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Get database path
  final appData = Platform.environment['APPDATA'];
  if (appData == null) {
    print('ERROR: APPDATA environment variable not found');
    exit(1);
  }

  final dbPath = path.join(appData, 'com.github.slavyk82', 'twmt', 'twmt.db');
  print('Database path: $dbPath');

  if (!File(dbPath).existsSync()) {
    print('ERROR: Database file not found');
    exit(1);
  }

  // Open database
  final db = await databaseFactory.openDatabase(dbPath);
  print('Database opened successfully\n');

  // Query translations with their source text
  final results = await db.rawQuery('''
    SELECT
      tv.id AS version_id,
      tu.source_text,
      tv.translated_text,
      tu.key
    FROM translation_versions tv
    INNER JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tv.translated_text IS NOT NULL
      AND tv.translated_text != ''
  ''');

  print('Found ${results.length} translations to check\n');

  int fixedCount = 0;
  final fixedItems = <Map<String, String>>[];

  for (final row in results) {
    final versionId = row['version_id'] as String;
    final sourceText = row['source_text'] as String;
    final translatedText = row['translated_text'] as String;
    final key = row['key'] as String;

    final fixedText = detectAndFixNumbers(sourceText, translatedText);

    if (fixedText != null) {
      fixedItems.add({
        'version_id': versionId,
        'key': key,
        'source': sourceText,
        'original': translatedText,
        'fixed': fixedText,
      });
      fixedCount++;
    }
  }

  print('Found $fixedCount translations with reformatted numbers:\n');
  print('=' * 80);

  for (final item in fixedItems) {
    print('Key: ${item['key']}');
    print('Source:   "${item['source']}"');
    print('Original: "${item['original']}"');
    print('Fixed:    "${item['fixed']}"');
    print('-' * 80);
  }

  if (fixedItems.isEmpty) {
    print('\nNo reformatted numbers found. Database is clean!');
    await db.close();
    return;
  }

  // Ask for confirmation
  print('\nDo you want to apply these fixes? (y/n): ');
  final input = stdin.readLineSync()?.toLowerCase();

  if (input != 'y' && input != 'yes') {
    print('Aborted. No changes made.');
    await db.close();
    return;
  }

  // Apply fixes
  print('\nApplying fixes...');

  int updatedCount = 0;
  for (final item in fixedItems) {
    try {
      await db.rawUpdate('''
        UPDATE translation_versions
        SET translated_text = ?,
            updated_at = strftime('%s', 'now')
        WHERE id = ?
      ''', [item['fixed'], item['version_id']]);
      updatedCount++;
    } catch (e) {
      print('ERROR updating ${item['key']}: $e');
    }
  }

  print('\nSuccessfully updated $updatedCount translations!');

  await db.close();
  print('Database closed.');
}
