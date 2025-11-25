import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/file_service_impl.dart';

void main() {
  group('FileServiceImpl - CSV Import/Export', () {
    late FileServiceImpl fileService;
    late Directory tempDir;

    setUp(() async {
      fileService = FileServiceImpl();
      tempDir = await Directory.systemTemp.createTemp('csv_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // ========================================================================
    // CSV IMPORT TESTS
    // ========================================================================

    group('importFromCsv', () {
      test('imports simple CSV with header', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''Name,Age,City
John,30,New York
Jane,25,Los Angeles
Bob,35,Chicago''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(3));
        expect(data[0]['Name'], equals('John'));
        expect(data[0]['Age'], equals('30'));
        expect(data[0]['City'], equals('New York'));
        expect(data[1]['Name'], equals('Jane'));
        expect(data[2]['Name'], equals('Bob'));
      });

      test('imports CSV without header', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''John,30,New York
Jane,25,Los Angeles''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: false,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2));
        expect(data[0]['col_0'], equals('John'));
        expect(data[0]['col_1'], equals('30'));
        expect(data[0]['col_2'], equals('New York'));
      });

      test('imports CSV with UTF-8 BOM', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '\uFEFFName,Value\nTest,123';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(1));
        expect(data[0]['Name'], equals('Test'));
        expect(data[0]['Value'], equals('123'));
      });

      test('imports CSV with quoted fields containing commas', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''Name,Description
"Smith, John","Software Developer, Senior"
Jane,Designer''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2));
        expect(data[0]['Name'], equals('Smith, John'));
        expect(data[0]['Description'], equals('Software Developer, Senior'));
      });

      test('imports CSV with escaped quotes', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''Name,Quote
John,"He said ""Hello"""
Jane,"She said ""Hi"""''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2));
        expect(data[0]['Quote'], equals('He said "Hello"'));
        expect(data[1]['Quote'], equals('She said "Hi"'));
      });

      test('imports CSV with empty fields', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''Name,Age,City
John,,New York
,25,
Bob,35,Chicago''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(3));
        expect(data[0]['Age'], equals(''));
        expect(data[1]['Name'], equals(''));
        expect(data[1]['City'], equals(''));
      });

      test('imports empty CSV returns empty list', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        await csvFile.writeAsString('');

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data, isEmpty);
      });

      test('imports CSV with only header returns empty list', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = 'Name,Age,City';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data, isEmpty);
      });

      test('imports CSV skips empty lines', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/test.csv');
        const csvContent = '''Name,Age

John,30

Jane,25

''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2));
        expect(data[0]['Name'], equals('John'));
        expect(data[1]['Name'], equals('Jane'));
      });

      test('returns error for non-existent file', () async {
        // Arrange
        final nonExistentPath = '${tempDir.path}/nonexistent.csv';

        // Act
        final result = await fileService.importFromCsv(
          filePath: nonExistentPath,
          hasHeader: true,
        );

        // Assert
        expect(result.isErr, isTrue);
        final error = result.unwrapErr();
        expect(error.toString(), contains('CSV file not found'));
      });

      test('imports translation CSV format', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/translations.csv');
        const csvContent = '''Key,Source Text,Translation,Status,Comments
menu.file.open,Open File,Ouvrir le fichier,translated,
menu.file.save,Save File,Enregistrer le fichier,reviewed,Verified by translator
app.title,Application,Application,translated,Same in French''';
        await csvFile.writeAsString(csvContent);

        // Act
        final result = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(3));
        expect(data[0]['Key'], equals('menu.file.open'));
        expect(data[0]['Source Text'], equals('Open File'));
        expect(data[0]['Translation'], equals('Ouvrir le fichier'));
        expect(data[0]['Status'], equals('translated'));
        expect(data[1]['Comments'], equals('Verified by translator'));
      });
    });

    // ========================================================================
    // CSV EXPORT TESTS
    // ========================================================================

    group('exportToCsv', () {
      test('exports simple data to CSV', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Name': 'John', 'Age': '30', 'City': 'New York'},
          {'Name': 'Jane', 'Age': '25', 'City': 'Los Angeles'},
          {'Name': 'Bob', 'Age': '35', 'City': 'Chicago'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        expect(await csvFile.exists(), isTrue);

        // Verify content
        final content = await csvFile.readAsString();
        expect(content, contains('Name,Age,City'));
        expect(content, contains('John,30,New York'));
        expect(content, contains('Jane,25,Los Angeles'));
      });

      test('exports with UTF-8 BOM for Excel compatibility', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Name': 'Test', 'Value': '123'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        // Read as bytes to verify BOM
        final bytes = await csvFile.readAsBytes();
        // UTF-8 BOM is EF BB BF
        expect(bytes[0], equals(0xEF));
        expect(bytes[1], equals(0xBB));
        expect(bytes[2], equals(0xBF));
      });

      test('exports with custom column order', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Name': 'John', 'Age': '30', 'City': 'New York'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
          headers: ['City', 'Name', 'Age'],
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        final lines = content.split('\n');
        expect(lines[0], equals('City,Name,Age'));
        expect(lines[1], equals('New York,John,30'));
      });

      test('exports fields with commas in quotes', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Name': 'Smith, John', 'Role': 'Developer, Senior'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        expect(content, contains('"Smith, John"'));
        expect(content, contains('"Developer, Senior"'));
      });

      test('exports fields with quotes escaped', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Text': 'He said "Hello"'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        expect(content, contains('"He said ""Hello"""'));
      });

      test('exports fields with newlines in quotes', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Text': 'Line 1\nLine 2'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        expect(content, contains('"Line 1\nLine 2"'));
      });

      test('exports empty fields', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = [
          {'Name': 'John', 'Age': '', 'City': 'New York'},
          {'Name': '', 'Age': '25', 'City': ''},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        final lines = content.split('\n');
        expect(lines[1], contains('John,,New York'));
        expect(lines[2], contains(',25,'));
      });

      test('exports creates parent directory if not exists', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/subdir/export.csv');
        final data = [
          {'Name': 'Test'},
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        expect(await csvFile.exists(), isTrue);
        expect(await csvFile.parent.exists(), isTrue);
      });

      test('returns error for empty data', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/export.csv');
        final data = <Map<String, String>>[];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isErr, isTrue);
        final error = result.unwrapErr();
        expect(error.toString(), contains('No data to export'));
      });

      test('exports translation data correctly', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/translations.csv');
        final data = [
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
            'Status': 'reviewed',
            'Comments': 'Verified by translator',
          },
        ];

        // Act
        final result = await fileService.exportToCsv(
          data: data,
          filePath: csvFile.path,
        );

        // Assert
        expect(result.isOk, isTrue);
        final content = await csvFile.readAsString();
        expect(content, contains('Key,Source Text,Translation,Status,Comments'));
        expect(content, contains('menu.file.open'));
        expect(content, contains('Ouvrir le fichier'));
      });
    });

    // ========================================================================
    // ROUND-TRIP TESTS
    // ========================================================================

    group('CSV Import/Export Round-trip', () {
      test('exported CSV can be imported back correctly', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/roundtrip.csv');
        final originalData = [
          {'Name': 'John', 'Age': '30', 'City': 'New York'},
          {'Name': 'Jane', 'Age': '25', 'City': 'Los Angeles'},
          {'Name': 'Bob', 'Age': '35', 'City': 'Chicago'},
        ];

        // Act - Export
        final exportResult = await fileService.exportToCsv(
          data: originalData,
          filePath: csvFile.path,
        );
        expect(exportResult.isOk, isTrue);

        // Act - Import
        final importResult = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(importResult.isOk, isTrue);
        final importedData = importResult.unwrap();
        expect(importedData.length, equals(originalData.length));
        for (var i = 0; i < originalData.length; i++) {
          expect(importedData[i], equals(originalData[i]));
        }
      });

      test('handles special characters in round-trip', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/special.csv');
        final originalData = [
          {
            'Text': 'Contains "quotes"',
            'Comma': 'Has, comma',
            'Newline': 'Line1\nLine2',
          },
        ];

        // Act - Export
        final exportResult = await fileService.exportToCsv(
          data: originalData,
          filePath: csvFile.path,
        );
        expect(exportResult.isOk, isTrue);

        // Act - Import
        final importResult = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(importResult.isOk, isTrue);
        final importedData = importResult.unwrap();
        expect(importedData[0]['Text'], equals('Contains "quotes"'));
        expect(importedData[0]['Comma'], equals('Has, comma'));
        expect(importedData[0]['Newline'], equals('Line1\nLine2'));
      });

      test('translation workflow round-trip preserves data', () async {
        // Arrange
        final csvFile = File('${tempDir.path}/translations.csv');
        final originalData = [
          {
            'Key': 'app.welcome',
            'Source Text': 'Welcome, "User"!',
            'Translation': 'Bienvenue, "Utilisateur"!',
            'Status': 'reviewed',
            'Comments': 'Checked by native speaker, looks good',
          },
          {
            'Key': 'error.not.found',
            'Source Text': 'Item not found',
            'Translation': 'Élément non trouvé',
            'Status': 'translated',
            'Comments': '',
          },
        ];

        // Act - Export
        final exportResult = await fileService.exportToCsv(
          data: originalData,
          filePath: csvFile.path,
        );
        expect(exportResult.isOk, isTrue);

        // Act - Import
        final importResult = await fileService.importFromCsv(
          filePath: csvFile.path,
          hasHeader: true,
        );

        // Assert
        expect(importResult.isOk, isTrue);
        final importedData = importResult.unwrap();
        expect(importedData.length, equals(2));
        expect(importedData[0]['Key'], equals('app.welcome'));
        expect(
          importedData[0]['Comments'],
          equals('Checked by native speaker, looks good'),
        );
        expect(importedData[1]['Translation'], equals('Élément non trouvé'));
      });
    });
  });
}
