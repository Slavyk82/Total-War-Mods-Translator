import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/file_service_impl.dart';

/// Integration test for CSV import/export with translation workflow
///
/// This test demonstrates the complete workflow:
/// 1. Export translations to CSV
/// 2. External reviewer edits CSV in Excel
/// 3. Import updated translations back
void main() {
  group('Translation CSV Workflow Integration', () {
    late FileServiceImpl fileService;
    late Directory tempDir;

    setUp(() async {
      fileService = FileServiceImpl();
      tempDir = await Directory.systemTemp.createTemp('csv_integration_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('complete translation review workflow', () async {
      // =====================================================================
      // STEP 1: Export translations for external review
      // =====================================================================

      final exportPath = '${tempDir.path}/translations_fr.csv';
      final translationsToReview = [
        {
          'Key': 'app.welcome',
          'Source Text': 'Welcome to TWMT',
          'Translation': 'Bienvenue à TWMT',
          'Status': 'needs_review',
          'Comments': '',
        },
        {
          'Key': 'menu.file.open',
          'Source Text': 'Open File',
          'Translation': 'Ouvrir le fichier',
          'Status': 'translated',
          'Comments': '',
        },
        {
          'Key': 'menu.file.save',
          'Source Text': 'Save File',
          'Translation': 'Enregistrer le fichier',
          'Status': 'translated',
          'Comments': '',
        },
        {
          'Key': 'error.not_found',
          'Source Text': 'Item not found',
          'Translation': 'Élément non trouvé',
          'Status': 'needs_review',
          'Comments': '',
        },
      ];

      final exportResult = await fileService.exportToCsv(
        data: translationsToReview,
        filePath: exportPath,
      );

      expect(exportResult.isOk, isTrue);
      expect(await File(exportPath).exists(), isTrue);

      // =====================================================================
      // STEP 2: Simulate external reviewer editing CSV
      // =====================================================================

      // Reviewer opens CSV in Excel, makes changes:
      // - Updates status to "reviewed" for checked items
      // - Adds comments
      // - Fixes translations

      final reviewedCsv = '''Key,Source Text,Translation,Status,Comments
app.welcome,Welcome to TWMT,Bienvenue dans TWMT,reviewed,"Changed 'à' to 'dans' for better flow"
menu.file.open,Open File,Ouvrir le fichier,reviewed,Looks good
menu.file.save,Save File,Enregistrer le fichier,reviewed,Correct
error.not_found,Item not found,Élément non trouvé,reviewed,Verified with native speaker''';

      // Write the reviewed CSV (simulating Excel save with UTF-8 BOM)
      await File(exportPath).writeAsString('\uFEFF$reviewedCsv');

      // =====================================================================
      // STEP 3: Import reviewed translations back
      // =====================================================================

      final importResult = await fileService.importFromCsv(
        filePath: exportPath,
        hasHeader: true,
      );

      expect(importResult.isOk, isTrue);
      final importedData = importResult.unwrap();

      // =====================================================================
      // STEP 4: Verify imported changes
      // =====================================================================

      expect(importedData.length, equals(4));

      // Check first translation (updated)
      expect(importedData[0]['Key'], equals('app.welcome'));
      expect(importedData[0]['Translation'], equals('Bienvenue dans TWMT'));
      expect(importedData[0]['Status'], equals('reviewed'));
      expect(
        importedData[0]['Comments'],
        equals("Changed 'à' to 'dans' for better flow"),
      );

      // Check all translations are now reviewed
      for (final translation in importedData) {
        expect(translation['Status'], equals('reviewed'));
        expect(translation['Comments']?.isNotEmpty, isTrue);
      }

      // Verify last translation
      expect(importedData[3]['Key'], equals('error.not_found'));
      expect(importedData[3]['Translation'], equals('Élément non trouvé'));
      expect(
        importedData[3]['Comments'],
        equals('Verified with native speaker'),
      );
    });

    test('handles special characters in translations', () async {
      // Export translations with special characters
      final exportPath = '${tempDir.path}/special_chars.csv';
      final translations = [
        {
          'Key': 'quote.example',
          'Source Text': 'He said "Hello"',
          'Translation': 'Il a dit "Bonjour"',
          'Status': 'translated',
          'Comments': 'Quotes preserved',
        },
        {
          'Key': 'multiline.example',
          'Source Text': 'Line 1\nLine 2\nLine 3',
          'Translation': 'Ligne 1\nLigne 2\nLigne 3',
          'Status': 'translated',
          'Comments': 'Multiline text',
        },
        {
          'Key': 'comma.example',
          'Source Text': 'Last, First',
          'Translation': 'Nom, Prénom',
          'Status': 'translated',
          'Comments': 'Contains comma',
        },
        {
          'Key': 'unicode.example',
          'Source Text': 'Café',
          'Translation': 'Café',
          'Status': 'translated',
          'Comments': 'Unicode characters: é, è, à',
        },
      ];

      // Export
      final exportResult = await fileService.exportToCsv(
        data: translations,
        filePath: exportPath,
      );
      expect(exportResult.isOk, isTrue);

      // Import
      final importResult = await fileService.importFromCsv(
        filePath: exportPath,
        hasHeader: true,
      );
      expect(importResult.isOk, isTrue);

      final importedData = importResult.unwrap();

      // Verify all special characters preserved
      expect(importedData[0]['Translation'], equals('Il a dit "Bonjour"'));
      expect(
        importedData[1]['Translation'],
        equals('Ligne 1\nLigne 2\nLigne 3'),
      );
      expect(importedData[2]['Translation'], equals('Nom, Prénom'));
      expect(importedData[3]['Translation'], equals('Café'));
      expect(importedData[3]['Comments'], equals('Unicode characters: é, è, à'));
    });

    test('exports with specific column order for consistency', () async {
      // Translation workflow requires specific column order
      final exportPath = '${tempDir.path}/ordered.csv';
      final translations = [
        {
          'Status': 'translated',
          'Key': 'test.key',
          'Translation': 'Test translation',
          'Source Text': 'Test source',
          'Comments': 'Test comment',
        },
      ];

      // Define desired column order
      final columnOrder = [
        'Key',
        'Source Text',
        'Translation',
        'Status',
        'Comments',
      ];

      // Export with specific order
      final exportResult = await fileService.exportToCsv(
        data: translations,
        filePath: exportPath,
        headers: columnOrder,
      );
      expect(exportResult.isOk, isTrue);

      // Verify header order by reading file
      final content = await File(exportPath).readAsString();
      final lines = content.split('\n');
      expect(lines[0], equals('Key,Source Text,Translation,Status,Comments'));
      expect(
        lines[1],
        equals('test.key,Test source,Test translation,translated,Test comment'),
      );
    });

    test('handles empty translations and comments', () async {
      final exportPath = '${tempDir.path}/empty_fields.csv';
      final translations = [
        {
          'Key': 'new.key',
          'Source Text': 'New text',
          'Translation': '',
          'Status': 'needs_translation',
          'Comments': '',
        },
        {
          'Key': 'partial.key',
          'Source Text': 'Partial text',
          'Translation': 'Texte partiel',
          'Status': 'needs_review',
          'Comments': '',
        },
      ];

      // Export
      final exportResult = await fileService.exportToCsv(
        data: translations,
        filePath: exportPath,
      );
      expect(exportResult.isOk, isTrue);

      // Import
      final importResult = await fileService.importFromCsv(
        filePath: exportPath,
        hasHeader: true,
      );
      expect(importResult.isOk, isTrue);

      final importedData = importResult.unwrap();

      // Verify empty fields are preserved
      expect(importedData[0]['Translation'], equals(''));
      expect(importedData[0]['Comments'], equals(''));
      expect(importedData[1]['Translation'], equals('Texte partiel'));
    });
  });
}
