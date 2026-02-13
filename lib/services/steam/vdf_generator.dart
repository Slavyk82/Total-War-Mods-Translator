import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';

/// Generates VDF files for steamcmd workshop_build_item
class VdfGenerator {
  /// Generate a VDF file from publish parameters.
  ///
  /// Returns the path to the generated VDF file.
  /// [outputDir] defaults to the system temp directory.
  Future<Result<String, SteamServiceException>> generateVdf(
    WorkshopPublishParams params, {
    String? outputDir,
  }) async {
    // Validate parameters
    final validationError = await _validateParams(params);
    if (validationError != null) {
      return Err(validationError);
    }

    try {
      final dir = outputDir ?? Directory.systemTemp.path;
      final vdfPath = path.join(dir, 'workshop_item_${DateTime.now().millisecondsSinceEpoch}.vdf');

      final content = _buildVdfContent(params);
      await File(vdfPath).writeAsString(content);

      return Ok(vdfPath);
    } catch (e, stackTrace) {
      return Err(VdfGenerationException(
        'Failed to generate VDF file: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Build VDF file content string
  String _buildVdfContent(WorkshopPublishParams params) {
    final buffer = StringBuffer();
    buffer.writeln('"workshopitem"');
    buffer.writeln('{');
    buffer.writeln('  "appid"           "${_escapeVdf(params.appId)}"');
    buffer.writeln('  "publishedfileid" "${_escapeVdf(params.publishedFileId)}"');
    buffer.writeln('  "contentfolder"   "${_escapeVdf(params.contentFolder)}"');
    buffer.writeln('  "previewfile"     "${_escapeVdf(params.previewFile)}"');
    buffer.writeln('  "title"           "${_escapeVdf(params.title)}"');
    buffer.writeln('  "description"     "${_escapeVdf(params.description)}"');
    buffer.writeln('  "changenote"      "${_escapeVdf(params.changeNote)}"');
    buffer.writeln('  "visibility"      "${params.visibility.value}"');
    buffer.writeln('}');
    return buffer.toString();
  }

  /// Escape special characters for VDF format.
  /// Newlines are kept as-is — steamcmd passes them through to Steam.
  String _escapeVdf(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\r', '');
  }

  /// Validate publish parameters
  Future<VdfGenerationException?> _validateParams(
    WorkshopPublishParams params,
  ) async {
    // Check content folder exists
    final contentDir = Directory(params.contentFolder);
    if (!await contentDir.exists()) {
      return VdfGenerationException(
        'Content folder does not exist: ${params.contentFolder}',
      );
    }

    // Check content folder contains a .pack file
    final hasPackFile = await contentDir
        .list()
        .any((entity) => entity is File && entity.path.endsWith('.pack'));
    if (!hasPackFile) {
      return VdfGenerationException(
        'Content folder does not contain a .pack file: ${params.contentFolder}',
      );
    }

    // Check preview file exists
    final previewFile = File(params.previewFile);
    if (!await previewFile.exists()) {
      return VdfGenerationException(
        'Preview file does not exist: ${params.previewFile}',
      );
    }

    // Check preview file size (< 1MB)
    final previewSize = await previewFile.length();
    if (previewSize > 1024 * 1024) {
      return VdfGenerationException(
        'Preview file exceeds 1MB limit (${(previewSize / 1024 / 1024).toStringAsFixed(2)}MB)',
      );
    }

    // Check title is not empty
    if (params.title.trim().isEmpty) {
      return const VdfGenerationException('Title cannot be empty');
    }

    return null;
  }
}
