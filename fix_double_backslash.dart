// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

/// Migration script to fix double-backslash sequences in translations
///
/// Problem: Translations have `\\n` (3 chars: 92,92,110) instead of `\n` (2 chars: 92,110)
/// This causes visible `\\` in the game before each line break.
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

  // Count affected translation_versions
  final countResult = await db.rawQuery(r'''
    SELECT COUNT(*) as count
    FROM translation_versions
    WHERE translated_text LIKE '%\\n%'
  ''');
  final affectedTranslations = countResult.first['count'] as int;
  print('Found $affectedTranslations translations with \\\\n to fix');

  // Count affected source texts (translation_units)
  final sourceCountResult = await db.rawQuery(r'''
    SELECT COUNT(*) as count
    FROM translation_units
    WHERE source_text LIKE '%\\n%'
  ''');
  final affectedSources = sourceCountResult.first['count'] as int;
  print('Found $affectedSources source texts with \\\\n to fix');

  if (affectedTranslations == 0 && affectedSources == 0) {
    print('No migrations needed.');
    await db.close();
    return;
  }

  print('\nThis will convert \\\\n (3 chars) to \\n (2 chars)');
  print('Press Enter to continue or Ctrl+C to cancel...');
  stdin.readLineSync();

  var updatedTranslations = 0;
  var updatedSources = 0;

  await db.transaction((txn) async {
    // Fix translations
    if (affectedTranslations > 0) {
      print('\nFixing translations...');
      final translations = await txn.rawQuery(r'''
        SELECT id, translated_text
        FROM translation_versions
        WHERE translated_text LIKE '%\\n%'
      ''');

      for (final row in translations) {
        final id = row['id'] as String;
        final text = row['translated_text'] as String;

        // Replace \\n (92,92,110) with \n (92,110)
        // In Dart: r'\\n' matches literal backslash-backslash-n
        // Replace with r'\n' which is literal backslash-n
        final fixed = text
            .replaceAll(r'\\r\\n', r'\r\n')
            .replaceAll(r'\\n', r'\n');

        if (fixed != text) {
          await txn.rawUpdate(
            'UPDATE translation_versions SET translated_text = ?, updated_at = ? WHERE id = ?',
            [fixed, DateTime.now().millisecondsSinceEpoch, id],
          );
          updatedTranslations++;
        }
      }
    }

    // Fix source texts
    if (affectedSources > 0) {
      print('Fixing source texts...');
      final sources = await txn.rawQuery(r'''
        SELECT id, source_text
        FROM translation_units
        WHERE source_text LIKE '%\\n%'
      ''');

      for (final row in sources) {
        final id = row['id'] as String;
        final text = row['source_text'] as String;

        final fixed = text
            .replaceAll(r'\\r\\n', r'\r\n')
            .replaceAll(r'\\n', r'\n');

        if (fixed != text) {
          await txn.rawUpdate(
            'UPDATE translation_units SET source_text = ? WHERE id = ?',
            [fixed, id],
          );
          updatedSources++;
        }
      }
    }
  });

  print('\n=== Migration Complete ===');
  print('Updated translations: $updatedTranslations');
  print('Updated source texts: $updatedSources');

  // Verify
  final verifyResult = await db.rawQuery('''
    SELECT tu.source_text, tv.translated_text
    FROM translation_units tu
    LEFT JOIN translation_versions tv ON tv.unit_id = tu.id
    WHERE tu.source_text LIKE '%crooked towers%'
    LIMIT 1
  ''');

  if (verifyResult.isNotEmpty) {
    final row = verifyResult.first;
    final sourceText = row['source_text'] as String;
    final translatedText = row['translated_text'] as String;

    print('\n=== Verification ===');

    // Check source
    final sourceIdx = sourceText.indexOf('towers') + 6;
    final sourceSnippet = sourceText.substring(sourceIdx, sourceIdx + 10);
    print('Source after "towers": bytes ${sourceSnippet.codeUnits}');

    // Check translation
    final transIdx = translatedText.indexOf('biscornues') + 10;
    final transSnippet = translatedText.substring(transIdx, transIdx + 10);
    print('Translation after "biscornues": bytes ${transSnippet.codeUnits}');

    // Verify format
    final expectedBytes = [46, 92, 110, 92, 110]; // .\n\n
    final sourceMatch = sourceSnippet.codeUnits.take(5).toList();
    final transMatch = transSnippet.codeUnits.take(5).toList();

    if (sourceMatch.toString() == expectedBytes.toString()) {
      print('✓ Source format correct: .\\n\\n (bytes 46,92,110,92,110)');
    } else {
      print('✗ Source format: $sourceMatch (expected $expectedBytes)');
    }

    if (transMatch.toString() == expectedBytes.toString()) {
      print('✓ Translation format correct: .\\n\\n (bytes 46,92,110,92,110)');
    } else {
      print('✗ Translation format: $transMatch (expected $expectedBytes)');
    }
  }

  await db.close();
}
