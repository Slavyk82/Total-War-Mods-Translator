import 'dart:io';
import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../models/import_export_settings.dart';
import '../models/import_preview.dart';
import '../models/import_result.dart';
import 'utils/import_file_reader.dart';

/// Service responsible for generating import previews and validation
class ImportPreviewService {
  final ImportFileReader _fileReader;

  const ImportPreviewService(this._fileReader);

  /// Parse import file and return preview
  Future<Result<ImportPreview, ServiceException>> previewImport(
    String filePath,
    ImportSettings settings,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          ServiceException('File not found: $filePath'),
        );
      }

      final fileSize = await file.length();

      final fileDataResult = await _fileReader.readFile(filePath, settings);

      if (fileDataResult.isErr) {
        return Err(fileDataResult.error);
      }

      final fileData = fileDataResult.value;
      final previewRows = fileData.rows.take(10).toList();
      final suggestedMapping = _fileReader.detectColumnMapping(fileData.headers);

      return Ok(
        ImportPreview(
          filePath: filePath,
          headers: fileData.headers,
          previewRows: previewRows,
          totalRows: fileData.rows.length,
          fileSize: fileSize,
          encoding: settings.encoding,
          suggestedMapping: suggestedMapping,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Failed to preview import: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Validate import data
  Future<Result<ImportValidationResult, ServiceException>> validateImport(
    ImportPreview preview,
    ImportSettings settings,
  ) async {
    try {
      final errors = <String>[];
      final warnings = <String>[];
      final duplicateKeys = <String>[];
      final missingColumns = <String>[];

      // Check required columns
      final hasKeyColumn = settings.columnMapping.values
          .any((col) => col == ImportColumn.key);

      if (!hasKeyColumn) {
        errors.add('Key column mapping is required');
        missingColumns.add('key');
      }

      final hasSourceOrTarget = settings.columnMapping.values.any(
        (col) => col == ImportColumn.sourceText || col == ImportColumn.targetText,
      );

      if (!hasSourceOrTarget) {
        errors.add('At least one of Source Text or Target Text column is required');
      }

      // Check for duplicate keys
      if (settings.validationOptions.checkDuplicates) {
        final keyColumn = settings.columnMapping.entries
            .firstWhere((e) => e.value == ImportColumn.key,
                orElse: () => const MapEntry('', ImportColumn.skip))
            .key;

        if (keyColumn.isNotEmpty) {
          final keys = <String>{};

          for (final row in preview.previewRows) {
            final key = row[keyColumn];
            if (key != null && key.isNotEmpty) {
              if (keys.contains(key)) {
                duplicateKeys.add(key);
              }
              keys.add(key);
            }
          }

          if (duplicateKeys.isNotEmpty) {
            warnings.add(
              'Found ${duplicateKeys.length} duplicate keys in preview',
            );
          }
        }
      }

      final isValid = errors.isEmpty;

      return Ok(
        ImportValidationResult(
          isValid: isValid,
          errors: errors,
          warnings: warnings,
          duplicateKeys: duplicateKeys,
          missingColumns: missingColumns,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Validation failed: $e', stackTrace: stackTrace),
      );
    }
  }
}
