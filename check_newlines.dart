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

  print('Opening: $dbPath');
  final db = await databaseFactory.openDatabase(dbPath);

  // Find a unit with "crooked towers"
  final units = await db.rawQuery('''
    SELECT id, key, source_text
    FROM translation_units
    WHERE source_text LIKE '%crooked towers%'
    LIMIT 1
  ''');

  if (units.isEmpty) {
    print('No units found with "crooked towers"');
    await db.close();
    return;
  }

  final unit = units.first;
  final unitId = unit['id'] as String;
  final sourceText = unit['source_text'] as String;

  print('Unit ID: $unitId');
  print('Key: ${unit['key']}');
  print('\n--- SOURCE TEXT ANALYSIS ---');
  print('Length: ${sourceText.length}');

  // Check for different newline representations
  final actualNewlines = RegExp('\n').allMatches(sourceText).length;
  final escapedNewlines = RegExp(r'\\n').allMatches(sourceText).length;
  final doubleEscapedNewlines = RegExp(r'\\\\n').allMatches(sourceText).length;

  print('Actual newlines (\\n char): $actualNewlines');
  print('Escaped newlines (\\\\n literal): $escapedNewlines');
  print('Double-escaped (\\\\\\\\n literal): $doubleEscapedNewlines');

  // Show a snippet around "crooked towers"
  final idx = sourceText.indexOf('crooked towers');
  if (idx >= 0) {
    final start = (idx + 14).clamp(0, sourceText.length);
    final end = (start + 50).clamp(0, sourceText.length);
    final snippet = sourceText.substring(start, end);
    print('\nSnippet after "crooked towers":');
    print('Raw bytes: ${snippet.codeUnits}');
    print('String: "$snippet"');
  }

  // Now check translations
  final versions = await db.rawQuery('''
    SELECT tv.id, tv.translated_text, tv.translation_source
    FROM translation_versions tv
    WHERE tv.unit_id = ?
    LIMIT 1
  ''', [unitId]);

  if (versions.isEmpty) {
    print('\nNo translation found for this unit');
  } else {
    final version = versions.first;
    final translatedText = version['translated_text'] as String;

    print('\n--- TRANSLATED TEXT ANALYSIS ---');
    print('Length: ${translatedText.length}');
    print('Source: ${version['translation_source']}');

    final actualNewlinesTr = RegExp('\n').allMatches(translatedText).length;
    final escapedNewlinesTr = RegExp(r'\\n').allMatches(translatedText).length;
    final doubleEscapedNewlinesTr = RegExp(r'\\\\n').allMatches(translatedText).length;

    print('Actual newlines (\\n char): $actualNewlinesTr');
    print('Escaped newlines (\\\\n literal): $escapedNewlinesTr');
    print('Double-escaped (\\\\\\\\n literal): $doubleEscapedNewlinesTr');

    // Show corresponding snippet
    final idxTr = translatedText.indexOf('biscornues');
    if (idxTr >= 0) {
      final startTr = (idxTr + 10).clamp(0, translatedText.length);
      final endTr = (startTr + 50).clamp(0, translatedText.length);
      final snippetTr = translatedText.substring(startTr, endTr);
      print('\nSnippet after "biscornues":');
      print('Raw bytes: ${snippetTr.codeUnits}');
      print('String: "$snippetTr"');
    }
  }

  await db.close();
}
