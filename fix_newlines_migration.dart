// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

/// Migration script to fix corrupted newline sequences in translation_versions
///
/// Problem: Old normalization converted \\n to actual newlines, resulting in
/// corrupted patterns like `\<newline>` instead of proper `\\n` sequences.
///
/// This script:
/// 1. Finds all translations with actual newlines
/// 2. Converts them back to escaped format \\n to match source text format
void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = path.join(
    Platform.environment['APPDATA']!,
    'com.github.slavyk82',
    'twmt',
    'twmt.db',
  );

  print('Opening: $dbPath');
  final db = await databaseFactory.openDatabase(dbPath);

  // Count affected records
  final countResult = await db.rawQuery('''
    SELECT COUNT(*) as count
    FROM translation_versions
    WHERE translated_text LIKE '%' || char(10) || '%'
  ''');
  final affectedCount = countResult.first['count'] as int;
  print('Found $affectedCount translations with actual newlines to fix');

  if (affectedCount == 0) {
    print('No migrations needed.');
    await db.close();
    return;
  }

  // Ask for confirmation
  print('\nThis will update $affectedCount records.');
  print('Press Enter to continue or Ctrl+C to cancel...');
  stdin.readLineSync();

  // Fetch all affected records
  final affected = await db.rawQuery('''
    SELECT id, translated_text
    FROM translation_versions
    WHERE translated_text LIKE '%' || char(10) || '%'
  ''');

  print('\nProcessing ${affected.length} records...');

  var updated = 0;
  var errors = 0;

  await db.transaction((txn) async {
    for (final row in affected) {
      final id = row['id'] as String;
      final originalText = row['translated_text'] as String;

      // Apply normalization
      var fixedText = originalText;

      // Step 1: Handle corrupted pattern `\<newline>` → `\\n`
      fixedText = fixedText.replaceAll('\\\r\n', r'\\r\\n');
      fixedText = fixedText.replaceAll('\\\n', r'\\n');

      // Step 2: Handle remaining actual newlines
      fixedText = fixedText.replaceAll('\r\n', r'\\r\\n');
      fixedText = fixedText.replaceAll('\n', r'\\n');

      if (fixedText != originalText) {
        try {
          await txn.rawUpdate(
            'UPDATE translation_versions SET translated_text = ?, updated_at = ? WHERE id = ?',
            [fixedText, DateTime.now().millisecondsSinceEpoch, id],
          );
          updated++;
        } catch (e) {
          print('Error updating $id: $e');
          errors++;
        }
      }
    }
  });

  print('\n=== Migration Complete ===');
  print('Updated: $updated records');
  print('Errors: $errors');

  // Verify one of the fixes
  if (updated > 0) {
    final verifyResult = await db.rawQuery('''
      SELECT tv.id, tv.translated_text, tu.source_text
      FROM translation_versions tv
      JOIN translation_units tu ON tv.unit_id = tu.id
      WHERE tu.source_text LIKE '%crooked towers%'
      LIMIT 1
    ''');

    if (verifyResult.isNotEmpty) {
      final verify = verifyResult.first;
      final translatedText = verify['translated_text'] as String;

      print('\n=== Verification ===');
      print('Checking translation for "crooked towers" unit:');

      final actualNewlines = RegExp('\n').allMatches(translatedText).length;
      final escapedNewlines = RegExp(r'\\n').allMatches(translatedText).length;

      print('Actual newlines: $actualNewlines (should be 0)');
      print('Escaped newlines: $escapedNewlines (should be > 0)');

      if (actualNewlines == 0) {
        print('✓ SUCCESS: Newlines are now properly escaped');
      } else {
        print('✗ FAILED: Still has actual newlines');
      }
    }
  }

  await db.close();
}
