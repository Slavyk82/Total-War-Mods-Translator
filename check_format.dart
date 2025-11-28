// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = path.join(
    Platform.environment['APPDATA']!,
    'com.github.slavyk82',
    'twmt',
    'twmt.db',
  );

  final db = await databaseFactory.openDatabase(dbPath);

  // Find the unit
  final units = await db.rawQuery('''
    SELECT tu.id, tu.source_text, tv.translated_text
    FROM translation_units tu
    LEFT JOIN translation_versions tv ON tv.unit_id = tu.id
    WHERE tu.source_text LIKE '%crooked towers%'
    LIMIT 1
  ''');

  if (units.isEmpty) {
    print('Unit not found');
    await db.close();
    return;
  }

  final unit = units.first;
  final sourceText = unit['source_text'] as String;
  final translatedText = unit['translated_text'] as String;

  print('=== SOURCE TEXT ===');
  final sourceSnippet = sourceText.substring(
    sourceText.indexOf('towers'),
    sourceText.indexOf('towers') + 30,
  );
  print('Snippet: "$sourceSnippet"');
  print('Bytes: ${sourceSnippet.codeUnits}');

  print('\n=== TRANSLATED TEXT ===');
  final transSnippet = translatedText.substring(
    translatedText.indexOf('biscornues'),
    translatedText.indexOf('biscornues') + 30,
  );
  print('Snippet: "$transSnippet"');
  print('Bytes: ${transSnippet.codeUnits}');

  // Analysis
  print('\n=== ANALYSIS ===');
  print('Source format explanation:');
  print('  92, 92, 110 = backslash(92) + backslash(92) + n(110) = "\\\\n"');
  print('  92, 110 = backslash(92) + n(110) = "\\n"');

  // Count patterns in source
  final sourceDoubleBackslash = RegExp(r'\\\\n').allMatches(sourceText).length;
  final sourceSingleBackslash = RegExp(r'(?<!\\)\\n(?!\\)').allMatches(sourceText).length;
  print('\nSource: $sourceDoubleBackslash double-backslash patterns, $sourceSingleBackslash single-backslash patterns');

  // Count patterns in translation
  final transDoubleBackslash = RegExp(r'\\\\n').allMatches(translatedText).length;
  final transSingleBackslash = RegExp(r'(?<!\\)\\n(?!\\)').allMatches(translatedText).length;
  print('Translation: $transDoubleBackslash double-backslash patterns, $transSingleBackslash single-backslash patterns');

  await db.close();
}
