import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Handles recording export operations to history
///
/// Responsible for creating and persisting export history records.
/// Failures in history recording do not affect the export operation.
class ExportHistoryRecorder {
  final ExportHistoryRepository _exportHistoryRepository;
  final LoggingService _logger;

  ExportHistoryRecorder({
    required ExportHistoryRepository exportHistoryRepository,
    LoggingService? logger,
  })  : _exportHistoryRepository = exportHistoryRepository,
        _logger = logger ?? LoggingService.instance;

  /// Ensure the export history table exists
  Future<void> ensureTableExists() async {
    await _exportHistoryRepository.ensureTableExists();
  }

  /// Record an export operation in history
  ///
  /// Creates a new [ExportHistory] record with the provided details.
  /// Any errors during recording are logged but do not throw.
  Future<void> recordExport({
    required String projectId,
    required List<String> languageCodes,
    required ExportFormat format,
    required bool validatedOnly,
    required String outputPath,
    required int fileSize,
    required int entryCount,
  }) async {
    try {
      final history = ExportHistory(
        id: const Uuid().v4(),
        projectId: projectId,
        languages: jsonEncode(languageCodes),
        format: format,
        validatedOnly: validatedOnly,
        outputPath: outputPath,
        fileSize: fileSize,
        entryCount: entryCount,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await _exportHistoryRepository.insert(history);

      _logger.info('Export history recorded', {
        'id': history.id,
        'format': format.toString(),
        'entryCount': entryCount,
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to record export history', e, stackTrace);
      // Don't fail the export if history recording fails
    }
  }

  /// Record multiple exports (e.g., for TMX with multiple languages)
  Future<void> recordMultipleExports({
    required String projectId,
    required ExportFormat format,
    required bool validatedOnly,
    required List<ExportRecord> records,
  }) async {
    for (final record in records) {
      await recordExport(
        projectId: projectId,
        languageCodes: record.languageCodes,
        format: format,
        validatedOnly: validatedOnly,
        outputPath: record.outputPath,
        fileSize: record.fileSize,
        entryCount: record.entryCount,
      );
    }
  }
}

/// Data class for batch export recording
class ExportRecord {
  final List<String> languageCodes;
  final String outputPath;
  final int fileSize;
  final int entryCount;

  const ExportRecord({
    required this.languageCodes,
    required this.outputPath,
    required this.fileSize,
    required this.entryCount,
  });
}
