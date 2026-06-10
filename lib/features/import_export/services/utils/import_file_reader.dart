import '../../../../models/common/result.dart';
import '../../../../models/common/service_exception.dart';
import '../../../../services/file/i_file_service.dart';
import '../../models/import_export_settings.dart';

/// Utility class for reading import files in various formats
class ImportFileReader {
  final IFileService _fileService;

  const ImportFileReader(this._fileService);

  /// Read file data based on format settings
  Future<Result<ImportFileData, ServiceException>> readFile(
    String filePath,
    ImportSettings settings,
  ) async {
    try {
      List<Map<String, String>> rows = [];
      List<String> headers = [];

      switch (settings.format) {
        case ImportFormat.csv:
          final result = await _fileService.importFromCsv(
            filePath: filePath,
            hasHeader: settings.hasHeaderRow,
            encoding: settings.encoding,
          );

          if (result.isErr) {
            return Err(
              ServiceException('Failed to read CSV: ${result.error}'),
            );
          }

          rows = result.value;
          if (rows.isNotEmpty) {
            headers = rows.first.keys.toList();
          }
          break;

        case ImportFormat.json:
          final result = await _fileService.importFromJson(
            filePath: filePath,
            encoding: settings.encoding,
          );

          if (result.isErr) {
            return Err(
              ServiceException('Failed to read JSON: ${result.error}'),
            );
          }

          final data = result.value;
          final jsonRows = _rowsFromJson(data);
          if (jsonRows == null) {
            return Err(
              ServiceException(
                'Unsupported JSON structure: expected an array of objects, a '
                'wrapper object with a single array property, or a map of '
                'objects.',
              ),
            );
          }
          rows = jsonRows;
          if (rows.isNotEmpty) {
            headers = rows.first.keys.toList();
          }
          break;

        case ImportFormat.excel:
          // Excel (.xlsx) is a binary format: settings.encoding does not
          // apply; cell text is always Unicode per the OOXML spec.
          final result = await _fileService.importFromExcel(
            filePath: filePath,
            hasHeader: settings.hasHeaderRow,
          );

          if (result.isErr) {
            return Err(
              ServiceException('Failed to read Excel: ${result.error}'),
            );
          }

          rows = result.value;
          if (rows.isNotEmpty) {
            headers = rows.first.keys.toList();
          }
          break;

        case ImportFormat.loc:
          return Err(
            ServiceException('.loc format import not yet implemented'),
          );
      }

      return Ok(
        ImportFileData(
          rows: rows,
          headers: headers,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Failed to read file: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Convert decoded JSON into import rows.
  ///
  /// Accepts three shapes and returns `null` (→ a reported error) for anything
  /// else, so an unexpected structure is never silently imported as zero rows:
  ///  - a top-level array of objects: `[{...}, {...}]`;
  ///  - a wrapper object with a single array property: `{"rows": [...]}`;
  ///  - a key→object map: `{"unit_a": {...}, "unit_b": {...}}`, where each
  ///    outer key is exposed as a `key` column (without clobbering an existing
  ///    `key` field in the inner object).
  List<Map<String, String>>? _rowsFromJson(dynamic data) {
    List<Map<String, String>> rowsFromList(List list) => list
        .whereType<Map>()
        .map((e) => e.map(
            (k, v) => MapEntry(k.toString(), v == null ? '' : v.toString())))
        .toList();

    if (data is List) {
      return rowsFromList(data);
    }
    if (data is Map) {
      if (data.isEmpty) return null;

      // Wrapper object: exactly one property whose value is an array.
      final listValues = data.values.whereType<List>().toList();
      if (listValues.length == 1) {
        return rowsFromList(listValues.first);
      }

      // Key→object map: every value is an object.
      if (data.values.every((v) => v is Map)) {
        return data.entries.map((entry) {
          final inner = (entry.value as Map).map((k, v) =>
              MapEntry(k.toString(), v == null ? '' : v.toString()));
          inner.putIfAbsent('key', () => entry.key.toString());
          return inner;
        }).toList();
      }
    }
    return null;
  }

  /// Auto-detect column mapping from headers
  Map<String, String> detectColumnMapping(List<String> headers) {
    final mapping = <String, String>{};

    for (final header in headers) {
      final lowerHeader = header.toLowerCase().trim();

      // Use pattern matching to determine column type
      final columnType = switch (lowerHeader) {
        _ when lowerHeader.contains('key') || lowerHeader == 'id' => ImportColumn.key,
        _ when lowerHeader.contains('source') => ImportColumn.sourceText,
        _ when lowerHeader.contains('target') ||
               lowerHeader.contains('translation') ||
               lowerHeader.contains('translated') => ImportColumn.targetText,
        _ when lowerHeader.contains('status') => ImportColumn.status,
        _ when lowerHeader.contains('note') => ImportColumn.notes,
        _ when lowerHeader.contains('context') => ImportColumn.context,
        _ => null,
      };

      if (columnType != null) {
        mapping[header] = columnType.name;
      }
    }

    return mapping;
  }
}

/// Data structure for file reading results
class ImportFileData {
  final List<Map<String, String>> rows;
  final List<String> headers;

  const ImportFileData({
    required this.rows,
    required this.headers,
  });
}
