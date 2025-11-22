import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for file import/export operations
///
/// Handles CSV, JSON, and Excel import/export functionality.
///
/// This service is used internally by FileServiceImpl to provide
/// import/export capabilities while keeping file sizes manageable.
class FileImportExportService {
  /// Singleton instance
  static final FileImportExportService _instance =
      FileImportExportService._internal();

  factory FileImportExportService() => _instance;

  FileImportExportService._internal();

  /// Logging service instance
  final LoggingService _logger = LoggingService.instance;

  // ============================================================================
  // CSV OPERATIONS
  // ============================================================================

  /// Import data from CSV file
  ///
  /// [filePath]: Path to CSV file
  /// [hasHeader]: Whether first row is header
  ///
  /// Returns list of rows (each row is a map of column name → value)
  ///
  /// Supports:
  /// - UTF-8 with BOM (Excel compatibility)
  /// - Quoted fields with commas and newlines
  /// - Escaped quotes (double quotes)
  /// - Comma delimiter
  Future<Result<List<Map<String, String>>, ImportException>> importFromCsv({
    required String filePath,
    bool hasHeader = true,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          ImportException(
            'CSV file not found: $filePath',
            filePath,
            'csv',
          ),
        );
      }

      // Read with UTF-8 BOM handling
      final contents = await file.readAsString(encoding: utf8);
      // Remove BOM if present
      final cleanContents =
          contents.startsWith('\uFEFF') ? contents.substring(1) : contents;

      if (cleanContents.trim().isEmpty) {
        _logger.warning('CSV file is empty', {'filePath': filePath});
        return Ok([]);
      }

      // Parse CSV (handle multiline fields)
      final allRecords = _parseCsv(cleanContents);
      if (allRecords.isEmpty) {
        return Ok([]);
      }

      // Parse header
      List<String> headers;
      int dataStartIndex;

      if (hasHeader) {
        headers = allRecords[0];
        dataStartIndex = 1;
      } else {
        // Generate column names: col_0, col_1, etc.
        headers = List.generate(allRecords[0].length, (i) => 'col_$i');
        dataStartIndex = 0;
      }

      // Parse data rows
      final rows = <Map<String, String>>[];
      for (var i = dataStartIndex; i < allRecords.length; i++) {
        final values = allRecords[i];
        final row = <String, String>{};

        for (var j = 0; j < headers.length && j < values.length; j++) {
          row[headers[j]] = values[j];
        }

        // Skip completely empty rows
        if (row.values.any((v) => v.isNotEmpty)) {
          rows.add(row);
        }
      }

      _logger.info('CSV import successful', {
        'filePath': filePath,
        'rows': rows.length,
        'columns': headers.length,
      });

      return Ok(rows);
    } on FileSystemException catch (e) {
      _logger.error('File system error during CSV import', e);
      return Err(
        ImportException(
          'Cannot read CSV file: ${e.message}',
          filePath,
          'csv',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to import CSV', e, stackTrace);
      return Err(
        ImportException(
          'Failed to import CSV: ${e.toString()}',
          filePath,
          'csv',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Export data to CSV file
  ///
  /// [data]: Data to export (list of maps)
  /// [filePath]: Destination CSV file path
  /// [headers]: Column headers (if null, use keys from first row)
  ///
  /// Returns path to exported file
  ///
  /// Format:
  /// - UTF-8 with BOM for Excel compatibility
  /// - Proper CSV escaping (quotes, commas, newlines)
  /// - Header row included
  Future<Result<String, ExportException>> exportToCsv({
    required List<Map<String, String>> data,
    required String filePath,
    List<String>? headers,
  }) async {
    try {
      if (data.isEmpty) {
        return Err(
          ExportException(
            'No data to export',
            filePath,
            'csv',
          ),
        );
      }

      // Determine columns (use provided headers or keys from first row)
      final columns = headers ?? data.first.keys.toList();

      final buffer = StringBuffer();

      // UTF-8 BOM for Excel compatibility
      buffer.write('\uFEFF');

      // Write header
      buffer.writeln(_formatCsvLine(columns));

      // Write data rows
      for (final row in data) {
        final values = columns.map((col) => row[col] ?? '').toList();
        buffer.writeln(_formatCsvLine(values));
      }

      // Write to file
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(buffer.toString(), encoding: utf8);

      _logger.info('CSV export successful', {
        'filePath': filePath,
        'rows': data.length,
        'columns': columns.length,
      });

      return Ok(filePath);
    } on FileSystemException catch (e) {
      _logger.error('File system error during CSV export', e);
      return Err(
        ExportException(
          'Cannot write CSV file: ${e.message}',
          filePath,
          'csv',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to export CSV', e, stackTrace);
      return Err(
        ExportException(
          'Failed to export CSV: ${e.toString()}',
          filePath,
          'csv',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ============================================================================
  // CSV HELPER METHODS
  // ============================================================================

  /// Parse entire CSV content into records
  ///
  /// Handles:
  /// - Quoted fields containing commas
  /// - Escaped quotes (double quotes)
  /// - Newlines within quoted fields
  /// - CRLF and LF line endings
  List<List<String>> _parseCsv(String content) {
    final records = <List<String>>[];
    final record = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < content.length; i++) {
      final char = content[i];

      if (char == '"') {
        // Handle double quotes (escaped quote)
        if (i + 1 < content.length && content[i + 1] == '"') {
          buffer.write('"');
          i++; // Skip next quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator
        record.add(buffer.toString());
        buffer.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        // Line ending (record separator)
        record.add(buffer.toString());
        buffer.clear();

        // Skip CRLF (Windows line ending)
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }

        // Add record if it has any content
        if (record.isNotEmpty && record.any((field) => field.isNotEmpty)) {
          records.add(List.from(record));
        }
        record.clear();
      } else {
        buffer.write(char);
      }
    }

    // Add last field and record
    if (buffer.isNotEmpty || record.isNotEmpty) {
      record.add(buffer.toString());
      if (record.any((field) => field.isNotEmpty)) {
        records.add(record);
      }
    }

    return records;
  }

  /// Format a list of fields into a CSV line with proper escaping
  ///
  /// Escapes:
  /// - Fields containing commas
  /// - Fields containing quotes
  /// - Fields containing newlines
  String _formatCsvLine(List<String> fields) {
    return fields.map((field) {
      // Escape quotes and wrap in quotes if needed
      var escaped = field.replaceAll('"', '""');
      if (escaped.contains(',') ||
          escaped.contains('"') ||
          escaped.contains('\n') ||
          escaped.contains('\r')) {
        escaped = '"$escaped"';
      }
      return escaped;
    }).join(',');
  }

  // ============================================================================
  // JSON OPERATIONS
  // ============================================================================

  /// Import data from JSON file
  ///
  /// [filePath]: Path to JSON file
  ///
  /// Returns parsed JSON data
  Future<Result<dynamic, ImportException>> importFromJson({
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          ImportException(
            'JSON file not found',
            filePath,
            'json',
          ),
        );
      }

      final content = await file.readAsString();
      final data = jsonDecode(content);

      return Ok(data);
    } on FormatException catch (e) {
      return Err(
        ImportException(
          'Invalid JSON format: ${e.message}',
          filePath,
          'json',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ImportException(
          'Failed to import JSON: ${e.toString()}',
          filePath,
          'json',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Export data to JSON file
  ///
  /// [data]: Data to export
  /// [filePath]: Destination JSON file path
  /// [prettyPrint]: Whether to format JSON with indentation
  ///
  /// Returns path to exported file
  Future<Result<String, ExportException>> exportToJson({
    required dynamic data,
    required String filePath,
    bool prettyPrint = true,
  }) async {
    try {
      final encoder = prettyPrint
          ? const JsonEncoder.withIndent('  ')
          : const JsonEncoder();

      final content = encoder.convert(data);

      // Write directly to file
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(content);

      return Ok(filePath);
    } on JsonUnsupportedObjectError catch (e) {
      return Err(
        ExportException(
          'Cannot encode data to JSON: ${e.cause}',
          filePath,
          'json',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ExportException(
          'Failed to export JSON: ${e.toString()}',
          filePath,
          'json',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ============================================================================
  // EXCEL OPERATIONS
  // ============================================================================

  /// Import data from Excel file (.xlsx)
  ///
  /// [filePath]: Path to Excel file
  /// [sheetName]: Sheet name to import (default: first sheet)
  /// [hasHeader]: Whether first row is header
  ///
  /// Returns list of rows
  Future<Result<List<Map<String, String>>, ImportException>> importFromExcel({
    required String filePath,
    String? sheetName,
    bool hasHeader = true,
  }) async {
    try {
      final file = File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        return Err(
          ImportException(
            'Excel file not found',
            filePath,
            'excel',
          ),
        );
      }

      // Read Excel file
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      // Get sheet (first sheet if not specified)
      Sheet? sheet;
      if (sheetName != null) {
        sheet = excel.tables[sheetName];
        if (sheet == null) {
          return Err(
            ImportException(
              'Sheet "$sheetName" not found in Excel file',
              filePath,
              'excel',
            ),
          );
        }
      } else {
        // Get first sheet
        if (excel.tables.isEmpty) {
          return Err(
            ImportException(
              'Excel file contains no sheets',
              filePath,
              'excel',
            ),
          );
        }
        sheet = excel.tables[excel.tables.keys.first];
      }

      if (sheet == null) {
        return Err(
          ImportException(
            'Cannot read sheet from Excel file',
            filePath,
            'excel',
          ),
        );
      }

      // At this point sheet is guaranteed to be non-null
      final nonNullSheet = sheet;

      // Use rows property which is populated by the Excel package
      final rows = nonNullSheet.rows;

      if (rows.isEmpty) {
        return Ok([]);
      }

      // Parse header
      List<String> headers;
      int dataStartIndex;

      if (hasHeader) {
        // Read header row
        headers =
            rows[0].map((cell) => cell?.value?.toString() ?? '').toList();
        dataStartIndex = 1;
      } else {
        // Generate column names (col_0, col_1, etc.)
        headers = List.generate(rows[0].length, (i) => 'col_$i');
        dataStartIndex = 0;
      }

      // Parse data rows
      final data = <Map<String, String>>[];
      for (var rowIdx = dataStartIndex; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        final rowData = <String, String>{};
        var hasNonEmptyCell = false;

        for (var colIdx = 0; colIdx < headers.length && colIdx < row.length;
            colIdx++) {
          final cell = row[colIdx];
          final cellValue = cell?.value?.toString() ?? '';
          rowData[headers[colIdx]] = cellValue;

          if (cellValue.isNotEmpty) {
            hasNonEmptyCell = true;
          }
        }

        // Skip empty rows
        if (hasNonEmptyCell) {
          data.add(rowData);
        }
      }

      _logger.info('Excel import successful', {
        'filePath': filePath,
        'rowCount': data.length,
        'columnCount': headers.length,
      });

      return Ok(data);
    } on FileSystemException catch (e) {
      _logger.error('Failed to import Excel: File system error', e);
      return Err(
        ImportException(
          'Cannot read Excel file: ${e.message}',
          filePath,
          'excel',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to import Excel', e, stackTrace);
      return Err(
        ImportException(
          'Failed to import Excel: ${e.toString()}',
          filePath,
          'excel',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Export data to Excel file (.xlsx)
  ///
  /// [data]: Data to export
  /// [filePath]: Destination Excel file path
  /// [sheetName]: Sheet name (default: "Sheet1")
  /// [headers]: Column headers
  ///
  /// Returns path to exported file
  Future<Result<String, ExportException>> exportToExcel({
    required List<Map<String, String>> data,
    required String filePath,
    String sheetName = 'Sheet1',
    List<String>? headers,
  }) async {
    try {
      if (data.isEmpty) {
        return Err(
          ExportException(
            'No data to export',
            filePath,
            'excel',
          ),
        );
      }

      // Create Excel workbook
      final excel = Excel.createExcel();

      // Remove default sheet
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Create named sheet
      final sheet = excel[sheetName];

      // Determine columns (use provided headers or keys from first row)
      final columns = headers ?? data.first.keys.toList();

      // Write header row with formatting
      for (var i = 0; i < columns.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = TextCellValue(columns[i]);
        // Apply bold formatting to header
        cell.cellStyle = CellStyle(bold: true);
      }

      // Write data rows
      for (var rowIdx = 0; rowIdx < data.length; rowIdx++) {
        final rowData = data[rowIdx];

        for (var colIdx = 0; colIdx < columns.length; colIdx++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIdx,
              rowIndex: rowIdx + 1, // +1 for header row
            ),
          );
          final value = rowData[columns[colIdx]] ?? '';
          cell.value = TextCellValue(value);
        }
      }

      // Set column widths (approximate auto-fit)
      for (var i = 0; i < columns.length; i++) {
        // Calculate max width based on header and sample data
        var maxWidth = columns[i].length.toDouble();

        // Check first few rows for longer content
        for (var rowIdx = 0; rowIdx < data.length && rowIdx < 10; rowIdx++) {
          final cellValue = data[rowIdx][columns[i]] ?? '';
          if (cellValue.length > maxWidth) {
            maxWidth = cellValue.length.toDouble();
          }
        }

        // Apply width with min/max constraints
        final width = (maxWidth + 2).clamp(10.0, 50.0);
        sheet.setColumnWidth(i, width);
      }

      // Encode Excel to bytes
      final bytes = excel.encode();
      if (bytes == null) {
        return Err(
          ExportException(
            'Failed to encode Excel file',
            filePath,
            'excel',
          ),
        );
      }

      // Write to file
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsBytes(bytes);

      _logger.info('Excel export successful', {
        'filePath': filePath,
        'rowCount': data.length,
        'columnCount': columns.length,
      });

      return Ok(filePath);
    } on FileSystemException catch (e) {
      _logger.error('Failed to export Excel: File system error', e);
      return Err(
        ExportException(
          'Cannot write Excel file: ${e.message}',
          filePath,
          'excel',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to export Excel', e, stackTrace);
      return Err(
        ExportException(
          'Failed to export Excel: ${e.toString()}',
          filePath,
          'excel',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
