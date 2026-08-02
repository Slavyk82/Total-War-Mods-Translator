import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

/// Streams [sources] into a zip archive at [tempZipPath].
///
/// Pure Dart by design — no Flutter, no Riverpod, no sqflite, no GetIt — so it
/// can be handed to `Isolate.run` and so it stays inside the services layer.
/// [workDirPath] must be a scratch directory the caller owns; per-entry
/// deflate temp files are written there and deleted as they are consumed.
///
/// The worker cannot log: it holds no [ILoggingService] and, once running in
/// a background isolate, could not reach one anyway. Failures surface as
/// thrown exceptions for the caller to log.
///
/// Each entry is compressed file→file and copied into the zip in chunks, so
/// peak memory stays a few stream buffers instead of the full database size.
Future<void> writeBackupArchive({
  required String tempZipPath,
  required List<(String, String)> sources,
  required String workDirPath,
}) async {
  OutputFileStream? zipOutput;
  try {
    zipOutput = OutputFileStream(tempZipPath);
    final encoder = ZipEncoder();
    encoder.startEncode(zipOutput);
    var entryIndex = 0;
    for (final (entryName, sourcePath) in sources) {
      final deflateTempPath =
          path.join(workDirPath, 'entry-${entryIndex++}.deflate');
      await _addFileToZipStreamed(
        encoder,
        entryName,
        sourcePath,
        deflateTempPath,
      );
    }
    encoder.endEncode();
    await zipOutput.close();
    zipOutput = null;
  } finally {
    // Close the zip output on the failure path: an open handle keeps the file
    // locked on Windows and would block the caller's temp-file cleanup. This
    // branch only runs while an exception from the try block is already
    // propagating, so a close failure here is secondary to that exception —
    // swallow it rather than mask the original error; the caller
    // (createBackup) logs the propagating exception via
    // `_logging.error('Failed to create backup', ...)`.
    if (zipOutput != null) {
      try {
        zipOutput.closeSync();
      } catch (_) {}
    }
  }
}

/// Add the file at [sourcePath] to [encoder] as [entryName] without ever
/// materializing it in memory.
///
/// The file is first deflate-compressed file→file into [deflateTempPath]:
/// [Deflate.buffer] reads the input and writes the compressed output
/// through fixed-size stream buffers and keeps a running CRC-32 of the
/// uncompressed input as a side effect. The pre-compressed bytes are then
/// handed to [ZipEncoder.addFile] as an already-deflated entry, which the
/// encoder copies into the archive in 1 MB chunks. (ZipFileEncoder.addFile
/// in archive 3.x is NOT used because it buffers both the whole
/// uncompressed file and its deflated form in memory.)
///
/// [Deflate.BEST_SPEED] matches the compression level the previous
/// in-memory `ZipEncoder().encode` implementation used, so produced
/// archives stay byte-compatible with the validate/restore path.
Future<void> _addFileToZipStreamed(
  ZipEncoder encoder,
  String entryName,
  String sourcePath,
  String deflateTempPath,
) async {
  final sourceLength = await File(sourcePath).length();

  var crc32 = 0;
  final input = InputFileStream(sourcePath);
  try {
    final deflateOutput = OutputFileStream(deflateTempPath);
    try {
      final deflate = Deflate.buffer(
        input,
        level: Deflate.BEST_SPEED,
        output: deflateOutput,
      );
      deflate.finish();
      crc32 = deflate.crc32;
    } finally {
      await deflateOutput.close();
    }
  } finally {
    await input.close();
  }

  final compressedInput = InputFileStream(deflateTempPath);
  try {
    final entry = ArchiveFile(
      entryName,
      sourceLength,
      compressedInput,
      ArchiveFile.DEFLATE,
    )
      ..crc32 = crc32
      // The constructor falls back to the COMPRESSED stream length when
      // size <= 0; force the real uncompressed size so zero-byte sources
      // (e.g. a TRUNCATE-checkpointed WAL) carry correct zip metadata.
      ..size = sourceLength;
    // addFile streams the pre-compressed bytes into the zip output and
    // closes [compressedInput] (autoClose defaults to true).
    encoder.addFile(entry);
  } finally {
    // Idempotent when addFile already closed the stream; required when
    // addFile threw before closing it (Windows file locks).
    compressedInput.closeSync();
  }
  await File(deflateTempPath).delete();
}
