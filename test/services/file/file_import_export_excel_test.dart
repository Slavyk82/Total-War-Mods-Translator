import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/file_import_export_service.dart';

void main() {
  group('FileImportExportService - Excel Operations', () {
    late FileImportExportService service;
    late Directory tempDir;

    setUp(() async {
      service = FileImportExportService();
      tempDir = await Directory.systemTemp.createTemp('excel_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Excel Import', () {
      test('importFromExcel - successfully imports valid Excel file', () async {
        // Arrange: Create a test Excel file
        final excel = Excel.createExcel();

        // Delete default sheet
        if (excel.tables.containsKey('Sheet1')) {
          excel.delete('Sheet1');
        }

        final sheet = excel['TestSheet'];

        // Add rows using appendRow (which works properly with Excel package)
        sheet.appendRow([TextCellValue('Key'), TextCellValue('Value')]);
        sheet.appendRow([TextCellValue('key1'), TextCellValue('value1')]);
        sheet.appendRow([TextCellValue('key2'), TextCellValue('value2')]);

        final filePath = '${tempDir.path}/test.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'TestSheet', // Specify sheet explicitly
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2));
        expect(data[0]['Key'], equals('key1'));
        expect(data[0]['Value'], equals('value1'));
        expect(data[1]['Key'], equals('key2'));
        expect(data[1]['Value'], equals('value2'));
      });

      test('importFromExcel - imports without header row', () async {
        // Arrange
        final excel = Excel.createExcel();
        if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
        final sheet = excel['TestSheet'];

        // Add data rows (no header)
        sheet.appendRow([TextCellValue('data1'), TextCellValue('data2')]);

        final filePath = '${tempDir.path}/test_no_header.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'TestSheet',
          hasHeader: false,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(1));
        expect(data[0]['col_0'], equals('data1'));
        expect(data[0]['col_1'], equals('data2'));
      });

      test('importFromExcel - handles empty cells', () async {
        // Arrange
        final excel = Excel.createExcel();
        if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
        final sheet = excel['TestSheet'];

        sheet.appendRow([TextCellValue('Col1'), TextCellValue('Col2')]);
        sheet.appendRow([TextCellValue('value1'), TextCellValue('')]);

        final filePath = '${tempDir.path}/test_empty.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'TestSheet',
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(1));
        expect(data[0]['Col1'], equals('value1'));
        expect(data[0]['Col2'], equals(''));
      });

      test('importFromExcel - imports specific sheet by name', () async {
        // Arrange
        final excel = Excel.createExcel();

        // Create two sheets
        final sheet1 = excel['Sheet1'];
        sheet1.appendRow([TextCellValue('Name')]);
        sheet1.appendRow([TextCellValue('Sheet1Data')]);

        final sheet2 = excel['Sheet2'];
        sheet2.appendRow([TextCellValue('Name')]);
        sheet2.appendRow([TextCellValue('Sheet2Data')]);

        final filePath = '${tempDir.path}/test_multi_sheet.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'Sheet2',
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(1));
        expect(data[0]['Name'], equals('Sheet2Data'));
      });

      test('importFromExcel - returns error for non-existent file', () async {
        // Arrange
        final filePath = '${tempDir.path}/non_existent.xlsx';

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          hasHeader: true,
        );

        // Assert
        expect(result.isErr, isTrue);
        final error = result.unwrapErr();
        expect(error.toString(), contains('Excel file not found'));
      });

      test('importFromExcel - returns error for non-existent sheet', () async {
        // Arrange
        final excel = Excel.createExcel();
        if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
        final sheet = excel['OnlySheet'];
        sheet.appendRow([TextCellValue('Data')]);

        final filePath = '${tempDir.path}/test_sheet.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'NonExistentSheet',
          hasHeader: true,
        );

        // Assert
        expect(result.isErr, isTrue);
        final error = result.unwrapErr();
        expect(error.toString(), contains('not found'));
      });

      test('importFromExcel - handles empty sheet', () async {
        // Arrange
        final excel = Excel.createExcel();
        excel['EmptySheet']; // Create empty sheet

        final filePath = '${tempDir.path}/test_empty_sheet.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data, isEmpty);
      });

      test('importFromExcel - skips empty rows', () async {
        // Arrange
        final excel = Excel.createExcel();
        if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
        final sheet = excel['TestSheet'];

        // Header
        sheet.appendRow([TextCellValue('Col1')]);

        // Data row
        sheet.appendRow([TextCellValue('value1')]);

        // Empty row
        sheet.appendRow([TextCellValue('')]);

        // Another data row
        sheet.appendRow([TextCellValue('value3')]);

        final filePath = '${tempDir.path}/test_skip_empty.xlsx';
        final bytes = excel.encode();
        await File(filePath).writeAsBytes(bytes!);

        // Act
        final result = await service.importFromExcel(
          filePath: filePath,
          sheetName: 'TestSheet',
          hasHeader: true,
        );

        // Assert
        expect(result.isOk, isTrue);
        final data = result.unwrap();
        expect(data.length, equals(2)); // Empty row should be skipped
        expect(data[0]['Col1'], equals('value1'));
        expect(data[1]['Col1'], equals('value3'));
      });
    });

    group('Excel Export', () {
      test('exportToExcel - successfully exports data to Excel', () async {
        // Arrange
        final data = [
          {'Key': 'key1', 'Value': 'value1'},
          {'Key': 'key2', 'Value': 'value2'},
        ];
        final filePath = '${tempDir.path}/export_test.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);
        expect(await File(filePath).exists(), isTrue);

        // Verify content
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        expect(sheet.rows.length, equals(3)); // Header + 2 data rows
      });

      test('exportToExcel - creates custom sheet name', () async {
        // Arrange
        final data = [
          {'Col1': 'data1'},
        ];
        final filePath = '${tempDir.path}/export_custom_sheet.xlsx';
        const sheetName = 'Translations';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
          sheetName: sheetName,
        );

        // Assert
        expect(result.isOk, isTrue);

        // Verify sheet name
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        expect(excel.tables.containsKey(sheetName), isTrue);
      });

      test('exportToExcel - uses custom header order', () async {
        // Arrange
        final data = [
          {'Value': 'v1', 'Key': 'k1'},
          {'Value': 'v2', 'Key': 'k2'},
        ];
        final headers = ['Key', 'Value']; // Specific order
        final filePath = '${tempDir.path}/export_header_order.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
          headers: headers,
        );

        // Assert
        expect(result.isOk, isTrue);

        // Verify header order
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        final firstRow = sheet.rows[0];
        expect(firstRow[0]?.value.toString(), equals('Key'));
        expect(firstRow[1]?.value.toString(), equals('Value'));
      });

      test('exportToExcel - creates parent directories', () async {
        // Arrange
        final data = [
          {'Test': 'value'},
        ];
        final filePath = '${tempDir.path}/nested/dir/export.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);
        expect(await File(filePath).exists(), isTrue);
      });

      test('exportToExcel - returns error for empty data', () async {
        // Arrange
        final data = <Map<String, String>>[];
        final filePath = '${tempDir.path}/export_empty.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isErr, isTrue);
        final error = result.unwrapErr();
        expect(error.toString(), contains('No data to export'));
      });

      test('exportToExcel - handles special characters', () async {
        // Arrange
        final data = [
          {'Key': 'test_key', 'Value': 'Hello, "World"!\nNew line\tTab'},
        ];
        final filePath = '${tempDir.path}/export_special.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);

        // Verify content
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        final valueCell = sheet.rows[1][1];
        expect(valueCell?.value.toString(),
            equals('Hello, "World"!\nNew line\tTab'));
      });

      test('exportToExcel - handles large dataset', () async {
        // Arrange
        final data = List.generate(
          1000,
          (i) => {
            'ID': 'id_$i',
            'Name': 'Name $i',
            'Value': 'Value $i',
          },
        );
        final filePath = '${tempDir.path}/export_large.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);
        expect(await File(filePath).exists(), isTrue);

        // Verify row count
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        expect(sheet.rows.length, equals(1001)); // Header + 1000 rows
      });

      test('exportToExcel - applies bold formatting to header', () async {
        // Arrange
        final data = [
          {'Column': 'data'},
        ];
        final filePath = '${tempDir.path}/export_format.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);

        // Verify formatting
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        final headerCell = sheet.rows[0][0];
        expect(headerCell?.cellStyle?.isBold, isTrue);
      });

      test('exportToExcel - sets column widths', () async {
        // Arrange
        final data = [
          {'Short': 'a', 'VeryLongColumnName': 'Some very long content here'},
        ];
        final filePath = '${tempDir.path}/export_width.xlsx';

        // Act
        final result = await service.exportToExcel(
          data: data,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, isTrue);

        // Verify column widths are set
        final bytes = await File(filePath).readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables.values.first;
        expect(sheet.getColumnWidth(0), greaterThan(0));
        expect(sheet.getColumnWidth(1), greaterThan(0));
      });
    });

    group('Excel Round-trip', () {
      test('export then import returns same data', () async {
        // Arrange
        final originalData = [
          {'Key': 'key1', 'Source': 'source1', 'Translation': 'trans1'},
          {'Key': 'key2', 'Source': 'source2', 'Translation': 'trans2'},
        ];
        final filePath = '${tempDir.path}/roundtrip.xlsx';

        // Act - Export
        final exportResult = await service.exportToExcel(
          data: originalData,
          filePath: filePath,
        );
        expect(exportResult.isOk, isTrue);

        // Act - Import
        final importResult = await service.importFromExcel(
          filePath: filePath,
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
    });
  });
}
