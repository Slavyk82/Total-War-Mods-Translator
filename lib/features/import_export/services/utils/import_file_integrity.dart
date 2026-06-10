import 'dart:io';

import 'package:crypto/crypto.dart';

/// Integrity helper for the import workflow.
///
/// The import pipeline re-reads the import file from disk at every stage
/// (preview, conflict detection, execution). If the file changes between the
/// preview the user reviewed and the actual import, the conflicts shown were
/// computed on content A while the import applies content B. The preview
/// stores [computeContentHash]'s result and the executor re-verifies it right
/// before importing.
abstract final class ImportFileIntegrity {
  /// sha256 hash (hex) of the file's raw bytes.
  static Future<String> computeContentHash(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
