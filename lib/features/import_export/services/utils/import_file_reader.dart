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
          final result = await _fileService.importFromJson(filePath: filePath);

          if (result.isErr) {
            return Err(
              ServiceException('Failed to read JSON: ${result.error}'),
            );
          }

          final data = result.value;
          if (data is List) {
            rows = data
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
                .toList();
            if (rows.isNotEmpty) {
              headers = rows.first.keys.toList();
            }
          }
          break;

        case ImportFormat.excel:
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
