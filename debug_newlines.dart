// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

/// Simulates _escapeTsvText from loc_file_service_impl.dart (FIXED)
String escapeTsvText(String text) {
  return text
      .replaceAll('\\', '\\\\')  // Escape existing backslashes: \ → \\
      .replaceAll('\t', '\\\\t') // Escape tabs: tab → \\t
      .replaceAll('\n', '\\\\n') // Escape newlines: newline → \\n
      .replaceAll('\r', '');     // Remove carriage returns
}

void main() async {
  // Initialize SQLite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = path.join(
    Platform.environment['APPDATA']!,
    'com.github.slavyk82',
    'twmt',
    'twmt.db',
  );

  print('Opening database: $dbPath');

  final db = await databaseFactory.openDatabase(dbPath);

  // Get specific translation by ID with source text
  final results = await db.rawQuery('''
    SELECT tv.id, tv.translated_text, tu.source_text, tu.key
    FROM translation_versions tv
    JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tv.id = '409f175a-9e6e-45ce-bdbb-2479333a88ca'
  ''');

  print('\n=== Sample translations ===\n');

  for (final row in results) {
    final id = row['id'] as String;
    final text = row['translated_text'] as String;
    final sourceText = row['source_text'] as String?;
    final key = row['key'] as String?;

    print('ID: $id');
    print('Key: $key');
    print('Length: ${text.length}');

    // Show full translated text
    print('\n--- TRANSLATED TEXT (full) ---');
    print(text);
    print('--- END TRANSLATED TEXT ---\n');

    // Show source text
    if (sourceText != null) {
      print('--- SOURCE TEXT (full) ---');
      print(sourceText);
      print('--- END SOURCE TEXT ---\n');
    }

    // Show first 200 chars with byte analysis
    final sample = text.length > 200 ? text.substring(0, 200) : text;

    // Check for specific byte sequences
    final bytes = text.codeUnits;

    // Count occurrences
    int realNewlines = 0;
    int backslashN = 0;
    int doubleBackslashN = 0;

    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 10) {
        // Real newline (char 10)
        realNewlines++;
      }
      if (i < bytes.length - 1 && bytes[i] == 92 && bytes[i + 1] == 110) {
        // Backslash (92) followed by 'n' (110)
        backslashN++;
      }
      if (i < bytes.length - 2 &&
          bytes[i] == 92 && bytes[i + 1] == 92 && bytes[i + 2] == 110) {
        // Double backslash followed by 'n'
        doubleBackslashN++;
      }
    }

    print('Real newlines (char 10): $realNewlines');
    print('Backslash-n sequences: $backslashN');
    print('Double-backslash-n sequences: $doubleBackslashN');
    print('---\n');
  }

  // Test TSV escaping
  print('\n=== TSV Escape Test ===\n');

  if (results.isNotEmpty) {
    final testText = results.first['translated_text'] as String;
    final escaped = escapeTsvText(testText);

    print('Original text bytes (first 100):');
    final origBytes = testText.codeUnits.take(100).toList();
    print(origBytes);

    print('\nEscaped text bytes (first 100):');
    final escBytes = escaped.codeUnits.take(100).toList();
    print(escBytes);

    print('\nEscaped text (first 300 chars):');
    print(escaped.length > 300 ? escaped.substring(0, 300) : escaped);

    // Check if escape produced double backslash before n
    int doubleBackslashN = 0;
    for (int i = 0; i < escBytes.length - 2; i++) {
      if (escBytes[i] == 92 && escBytes[i + 1] == 92 && escBytes[i + 2] == 110) {
        doubleBackslashN++;
      }
    }
    print('\nDouble-backslash-n in escaped: $doubleBackslashN');
  }

  // Count totals
  print('\n=== Totals ===\n');

  final countReal = await db.rawQuery('''
    SELECT COUNT(*) as cnt FROM translation_versions
    WHERE INSTR(translated_text, char(10)) > 0
  ''');
  print('Translations with real newlines: ${countReal.first['cnt']}');

  final countBackslashN = await db.rawQuery('''
    SELECT COUNT(*) as cnt FROM translation_versions
    WHERE INSTR(translated_text, char(92) || 'n') > 0
  ''');
  print('Translations with backslash-n: ${countBackslashN.first['cnt']}');

  final countDoubleBackslashN = await db.rawQuery('''
    SELECT COUNT(*) as cnt FROM translation_versions
    WHERE INSTR(translated_text, char(92) || char(92) || 'n') > 0
  ''');
  print('Translations with double-backslash-n: ${countDoubleBackslashN.first['cnt']}');

  await db.close();

  // Generate a test TSV file to inspect
  print('\n=== Generating test TSV ===\n');

  final testTsvPath = path.join(Directory.current.path, 'test_export.tsv');
  final buffer = StringBuffer();
  buffer.writeln('key\ttext\ttooltip');
  buffer.writeln('#Loc;1;text/db/test.loc\t\t');

  // Add a test entry with newlines
  const testKey = 'test_key_001';
  const testText = 'First line\nSecond line\nThird line';
  final escapedTestText = escapeTsvText(testText);
  buffer.writeln('$testKey\t$escapedTestText\tfalse');

  await File(testTsvPath).writeAsString(buffer.toString());
  print('Test TSV written to: $testTsvPath');

  // Read back and show bytes
  final content = await File(testTsvPath).readAsString();
  print('\nTSV file content:');
  print(content);
  print('\nTSV bytes around newline escape:');
  final bytes = content.codeUnits;
  // Find 'First line' and show surrounding bytes
  for (int i = 0; i < bytes.length - 10; i++) {
    if (bytes[i] == 70 && bytes[i+1] == 105) { // 'Fi'
      print('Bytes at "First line\\nSecond": ${bytes.sublist(i, i + 30)}');
      break;
    }
  }

  print('\nDone!');
}
