# Non-blocking automatic backup with visible progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the daily automatic database backup from freezing the app, and show a discreet, self-dismissing card reporting its progress.

**Architecture:** The archive-writing code (`ZipEncoder` + `Deflate`) moves verbatim out of `DatabaseBackupService` into a pure-Dart worker, which then runs inside `Isolate.run`. Progress is *not* messaged out of the worker; instead the main isolate polls the sizes of the temp files the worker writes. A `@riverpod` notifier holds the UI state and a card in the global overlay `Stack` renders it.

**Tech Stack:** Flutter (Windows desktop), Riverpod with code generation (`@riverpod` + `build_runner`), `archive` 3.6.1, `sqflite_common_ffi`, slang for i18n, `flutter_test`.

**Design spec:** `docs/superpowers/specs/2026-08-02-auto-backup-progress-design.md`

## Global Constraints

- **Risk posture is conservative.** The body of `_addFileToZipStreamed` — in particular `Deflate.buffer(...)` and `deflate.finish()` — is **moved, never rewritten**. Any task that changes compression behaviour is out of scope.
- **No percentage anywhere.** Neither backup phase has an honest denominator. The UI shows an indeterminate bar plus a byte counter. Do not add `bytesTotal` or `fraction` to any model.
- **Log message content is always English.** Only UI chrome is localized.
- **`lib/services/**` must not import Riverpod or `package:flutter` widgets.** Dependencies are injected through constructors/parameters. Enforced by `test/architecture/import_boundaries_test.dart`.
- **`lib/widgets/**` must not import anything under `lib/features/**`.** Enforced by the same test.
- **`lib/models/**` imports nothing from the layers above it.**
- **No `SnackBar` / `ScaffoldMessenger`.** The app shell is `FluentScaffold`, not a Material `Scaffold`; `ScaffoldMessenger` throws.
- After editing any `@riverpod` file, run `dart run build_runner build --delete-conflicting-outputs`.
- Full check commands: `flutter test` and `flutter analyze`.
- Commits must **not** include a `Co-Authored-By` trailer.

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/models/backup/backup_progress.dart` (create) | `BackupPhase` enum, `BackupProgress` value object, human-readable byte formatting. Lowest layer, importable by widgets. |
| `lib/services/backup/backup_archive_worker.dart` (create) | Pure-Dart archive writer. Owns `OutputFileStream`/`ZipEncoder`/`Deflate`. Runs inside a background isolate. |
| `lib/services/backup/backup_progress_poller.dart` (create) | Timer that samples a `measure()` function and emits `BackupProgress`. Independently testable. |
| `lib/services/backup/database_backup_service.dart` (modify) | Orchestrates: snapshot, delegate to worker via `Isolate.run`, rename, cleanup. Gains optional `onProgress`. |
| `lib/services/backup/auto_backup_service.dart` (modify) | Returns a typed `AutoBackupOutcome`; forwards `onProgress`. |
| `lib/providers/backup/auto_backup_progress_provider.dart` (create) | `AutoBackupUiState` + `@riverpod` notifier. |
| `lib/widgets/backup/auto_backup_progress_card.dart` (create) | The overlay card. Owns the "Done" hold timer. |
| `lib/i18n/<locale>/bootstrap.i18n.json` (modify, 11 files) | `autoBackup` keys. |
| `lib/main.dart` (modify) | Feeds the notifier from `_runAutoBackup`; mounts the card in the overlay `Stack`. |

---

### Task 1: `BackupProgress` model

**Files:**
- Create: `lib/models/backup/backup_progress.dart`
- Test: `test/models/backup/backup_progress_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum BackupPhase { snapshot, compressing }`; `class BackupProgress` with `const BackupProgress({required BackupPhase phase, required int bytesDone})`, fields `phase` and `bytesDone`, and `String get formattedBytes`.

A byte formatter already exists in `lib/features/import_export/models/export_result.dart`, but `lib/widgets/**` may not import a feature, so the card cannot reuse it. The formatter therefore lives on the model, which every layer may import.

- [ ] **Step 1: Write the failing test**

Create `test/models/backup/backup_progress_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';

void main() {
  BackupProgress progress(int bytes) => BackupProgress(
        phase: BackupPhase.compressing,
        bytesDone: bytes,
      );

  test('formats bytes below 1 KB as plain bytes', () {
    expect(progress(0).formattedBytes, '0 B');
    expect(progress(512).formattedBytes, '512 B');
  });

  test('formats kilobytes, megabytes and gigabytes with one decimal', () {
    expect(progress(1536).formattedBytes, '1.5 KB');
    expect(progress(5 * 1024 * 1024).formattedBytes, '5.0 MB');
    expect(progress(1782579200).formattedBytes, '1.7 GB');
  });

  test('carries its phase', () {
    const p = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1);
    expect(p.phase, BackupPhase.snapshot);
  });

  test('is equatable by value so identical events can be de-duplicated', () {
    const a = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 10);
    const b = BackupProgress(phase: BackupPhase.snapshot, bytesDone: 10);
    const c = BackupProgress(phase: BackupPhase.compressing, bytesDone: 10);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/backup/backup_progress_test.dart -r compact`
Expected: FAIL — `Target of URI doesn't exist: 'package:twmt/models/backup/backup_progress.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/models/backup/backup_progress.dart`:

```dart
/// Which stage of a database backup is currently running.
///
/// Deliberately has no notion of a total or a fraction: neither stage can
/// produce an honest denominator. `VACUUM INTO` defragments, so its output is
/// smaller than the source database; compression progress is only observable
/// as compressed bytes written, whose total is unknown until the archive is
/// finished. See the design spec for why an estimated percentage was rejected.
enum BackupPhase {
  /// `VACUUM INTO` is writing a consistent snapshot of the database.
  snapshot,

  /// The snapshot is being compressed into the zip archive.
  compressing,
}

/// A single progress observation of a running backup.
class BackupProgress {
  final BackupPhase phase;

  /// Bytes observed on disk so far for [phase]. Monotonically non-decreasing
  /// within a phase, and reset when the phase changes.
  final int bytesDone;

  const BackupProgress({required this.phase, required this.bytesDone});

  /// [bytesDone] rendered for display, e.g. `1.7 GB`.
  String get formattedBytes {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytesDone < kb) return '$bytesDone B';
    if (bytesDone < mb) return '${(bytesDone / kb).toStringAsFixed(1)} KB';
    if (bytesDone < gb) return '${(bytesDone / mb).toStringAsFixed(1)} MB';
    return '${(bytesDone / gb).toStringAsFixed(1)} GB';
  }

  @override
  bool operator ==(Object other) =>
      other is BackupProgress &&
      other.phase == phase &&
      other.bytesDone == bytesDone;

  @override
  int get hashCode => Object.hash(phase, bytesDone);

  @override
  String toString() => 'BackupProgress(${phase.name}, $bytesDone)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/backup/backup_progress_test.dart -r compact`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/backup/backup_progress.dart test/models/backup/backup_progress_test.dart
git commit -m "feat(backup): add BackupProgress model"
```

---

### Task 2: Extract the archive writer into a pure-Dart worker

**Files:**
- Create: `lib/services/backup/backup_archive_worker.dart`
- Modify: `lib/services/backup/database_backup_service.dart` (remove lines 211-229 and the `_addFileToZipStreamed` method at 302-351; adjust the `finally` block at 248-260)
- Test: `test/unit/services/backup/backup_archive_worker_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Future<void> writeBackupArchive({required String tempZipPath, required List<(String, String)> sources, required String workDirPath})` — writes the zip; failures surface as thrown exceptions.

**This task does NOT introduce the isolate.** It only relocates code, so that a reviewer can judge "was the move faithful?" separately from "does `Isolate.run` behave?". `createBackup` calls `writeBackupArchive` directly, still on the main isolate. Task 3 adds the isolate.

The worker cannot log: it is pure Dart with no `ILoggingService`, and in Task 3 it will run in another isolate. The one warning the current code emits from this region — the `closeSync` failure at `database_backup_service.dart:255-258` — is therefore **returned** as a string rather than dropped, and logged by the caller.

- [ ] **Step 1: Write the failing test**

Create `test/unit/services/backup/backup_archive_worker_test.dart`:

```dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/backup/backup_archive_worker.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('twmt_archive_worker_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Incompressible content: deflate cannot shrink random bytes, which
  /// exercises the stored/expanded path through the encoder.
  Uint8List randomBytes(int size, {int seed = 7}) {
    final rnd = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(size, (_) => rnd.nextInt(256)),
    );
  }

  /// Highly compressible content: long runs collapse to almost nothing.
  Uint8List repetitiveBytes(int size) =>
      Uint8List.fromList(List<int>.filled(size, 0x41));

  Future<File> writeSource(String name, Uint8List bytes) async {
    final f = File(path.join(tmp.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  /// Read one entry back out of the produced archive.
  List<int> readEntry(String zipPath, String entryName) {
    final input = InputFileStream(zipPath);
    try {
      // verify: true actually checks CRC-32. Without it the decoder ignores
      // the checksum entirely, and a broken CRC would round-trip content fine
      // here while 7-Zip and Explorer reject the archive. These tests are the
      // regression net for moving compression into an isolate, so the checksum
      // has to be part of what they verify.
      final archive = ZipDecoder().decodeBuffer(input, verify: true);
      final entry = archive.files.firstWhere((f) => f.name == entryName);
      return entry.content as List<int>;
    } finally {
      input.closeSync();
    }
  }

  test('round-trips an incompressible entry byte-for-byte', () async {
    final bytes = randomBytes(3 * 1024 * 1024);
    final source = await writeSource('twmt.db', bytes);
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    expect(readEntry(zipPath, 'twmt.db'), equals(bytes));
  });

  test('round-trips a highly compressible entry byte-for-byte', () async {
    final bytes = repetitiveBytes(2 * 1024 * 1024);
    final source = await writeSource('twmt.db', bytes);
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    expect(readEntry(zipPath, 'twmt.db'), equals(bytes));
    // Sanity: it really did compress, so the deflate path ran.
    expect(await File(zipPath).length(), lessThan(bytes.length));
  });

  test('writes every source as its own entry, including a zero-byte one',
      () async {
    // Mirrors the legacy checkpoint-and-copy path: a TRUNCATE-checkpointed
    // WAL is zero bytes but must still become a valid entry.
    final db = await writeSource('twmt.db', randomBytes(64 * 1024));
    final wal = await writeSource('twmt.db-wal', Uint8List(0));
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [
        ('twmt.db', db.path),
        ('twmt.db-wal', wal.path),
      ],
      workDirPath: tmp.path,
    );

    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input, verify: true);
      expect(
        archive.files.map((f) => f.name).toList()..sort(),
        ['twmt.db', 'twmt.db-wal'],
      );
      final walEntry =
          archive.files.firstWhere((f) => f.name == 'twmt.db-wal');
      expect(walEntry.size, 0);
    } finally {
      input.closeSync();
    }
  });

  test('deletes its per-entry deflate temp files', () async {
    final source = await writeSource('twmt.db', randomBytes(128 * 1024));
    final zipPath = path.join(tmp.path, 'out.zip');

    await writeBackupArchive(
      tempZipPath: zipPath,
      sources: [('twmt.db', source.path)],
      workDirPath: tmp.path,
    );

    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.deflate'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('propagates a missing source file as an exception', () async {
    final zipPath = path.join(tmp.path, 'out.zip');

    expect(
      () => writeBackupArchive(
        tempZipPath: zipPath,
        sources: [('twmt.db', path.join(tmp.path, 'does-not-exist.db'))],
        workDirPath: tmp.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/backup/backup_archive_worker_test.dart -r compact`
Expected: FAIL — `Target of URI doesn't exist: 'package:twmt/services/backup/backup_archive_worker.dart'`

- [ ] **Step 3: Create the worker with the code moved verbatim**

Create `lib/services/backup/backup_archive_worker.dart`:

```dart
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
/// The worker cannot log: it holds no [ILoggingService] and, once running in a
/// background isolate, could not reach one anyway. Failures therefore surface
/// as thrown exceptions, which the caller catches and logs.
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
    // locked on Windows and would block the caller's temp-file cleanup.
    if (zipOutput != null) {
      try {
        zipOutput.closeSync();
      } catch (_) {
        // Secondary to the exception already unwinding, which createBackup
        // logs via _logging.error('Failed to create backup', ...). Nothing
        // useful can be reported from here: the worker holds no logger, and
        // a value returned from a finally block that an exception is passing
        // through would never reach the caller anyway.
      }
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
```

- [ ] **Step 4: Run the worker test to verify it passes**

Run: `flutter test test/unit/services/backup/backup_archive_worker_test.dart -r compact`
Expected: PASS, 5 tests.

- [ ] **Step 5: Delete the moved code from `DatabaseBackupService`**

In `lib/services/backup/database_backup_service.dart`:

Delete the entire `_addFileToZipStreamed` method (currently lines 302-351, from `/// Add the file at [sourcePath] to [encoder]...` down to and including the closing brace after `await File(deflateTempPath).delete();`).

Replace the archive-writing block — from `_logging.debug('Writing backup archive');` through `tempZipNeedsCleanup = false;` — with:

```dart
      _logging.debug('Writing backup archive');
      tempZipNeedsCleanup = true;
      await writeBackupArchive(
        tempZipPath: tempZipPath,
        sources: sources,
        workDirPath: workDir.path,
      );

      await File(tempZipPath).rename(destinationPath);
      tempZipNeedsCleanup = false;
```

Delete the now-unused local `OutputFileStream? zipOutput;` declaration (line 144) and the `if (zipOutput != null) { ... }` block at the top of the `finally` (lines 251-260) — the worker owns that stream now.

Add the import near the other relative imports:

```dart
import 'backup_archive_worker.dart';
```

Remove `import 'package:archive/archive_io.dart';` **only if** no other reference remains — `validateBackup` and `restoreBackup` still use `ZipDecoder`, `Archive`, `ArchiveFile`, `InputFileStream` and `OutputFileStream`, so **keep it**.

- [ ] **Step 6: Run the full backup suite to verify nothing regressed**

Run: `flutter test test/unit/services/backup/ -r compact`
Expected: PASS — the pre-existing `database_backup_service` tests still pass, proving the move was faithful.

- [ ] **Step 7: Verify the architecture boundary holds**

Run: `flutter test test/architecture/import_boundaries_test.dart -r compact`
Expected: PASS — the worker imports only `dart:io`, `archive` and `path`.

- [ ] **Step 8: Commit**

```bash
git add lib/services/backup/backup_archive_worker.dart \
        lib/services/backup/database_backup_service.dart \
        test/unit/services/backup/backup_archive_worker_test.dart
git commit -m "refactor(backup): extract the archive writer into a pure-Dart worker

Moved verbatim out of DatabaseBackupService so it can run in a background
isolate. The one warning this region used to log is now returned to the
caller, since the worker holds no logger."
```

---

### Task 3: Run the worker in a background isolate

**Files:**
- Modify: `lib/services/backup/database_backup_service.dart`
- Test: `test/unit/services/backup/database_backup_service_isolate_test.dart`

**Interfaces:**
- Consumes: `writeBackupArchive(...)` from Task 2.
- Produces: no signature change. `createBackup` behaves identically, but no longer blocks the calling isolate during compression.

This is the change that actually fixes the freeze. `Isolate.run` rethrows a worker exception in the caller, so the existing `try/catch` in `createBackup` keeps turning failures into `Err(BackupException(...))`.

Every value captured by the closure must be sendable: `tempZipPath` and `workDir.path` are `String`, and `sources` is a `List<(String, String)>` — records of strings, which are sendable.

- [ ] **Step 1: Write the failing test**

Create `test/unit/services/backup/database_backup_service_isolate_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/noop_logger.dart';

/// A file that passes DatabaseBackupService's SQLite header validation: the
/// magic string, a zero byte at offset 15, and a non-zero `user_version` at
/// offset 60 (big-endian 32-bit).
Uint8List fakeSqliteBytes(int payloadSize, {int userVersion = 1, int seed = 7}) {
  final bytes = Uint8List(100 + payloadSize);
  const magic = 'SQLite format 3';
  for (var i = 0; i < magic.length; i++) {
    bytes[i] = magic.codeUnitAt(i);
  }
  bytes[15] = 0x00;
  bytes[60] = (userVersion >> 24) & 0xff;
  bytes[61] = (userVersion >> 16) & 0xff;
  bytes[62] = (userVersion >> 8) & 0xff;
  bytes[63] = userVersion & 0xff;
  final rnd = Random(seed);
  for (var i = 100; i < bytes.length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('twmt_backup_isolate_test_');
    dbPath = path.join(tmp.path, 'twmt.db');
    await File(dbPath).writeAsBytes(fakeSqliteBytes(4 * 1024 * 1024));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DatabaseBackupService build() => DatabaseBackupService(
        logging: NoopLogger(),
        databasePathProvider: () async => dbPath,
        databaseCloser: () async {},
        databaseReinitializer: () async {},
      );

  test('creates a valid backup with the worker running in an isolate',
      () async {
    final destination = path.join(tmp.path, 'backup.zip');

    final result = await build().createBackup(destination);

    expect(result.isOk, isTrue);
    expect(await File(destination).exists(), isTrue);

    final validated = await build().validateBackup(destination);
    expect(validated.isOk, isTrue);
    expect(validated.value.hasDatabaseFile, isTrue);
  });

  test('keeps the calling isolate responsive during compression', () async {
    // 64 MB of incompressible data: large enough that a synchronous deflate
    // stalls the event loop for a clearly measurable stretch.
    await File(dbPath).writeAsBytes(fakeSqliteBytes(64 * 1024 * 1024));
    final destination = path.join(tmp.path, 'backup.zip');

    // Sample the wall clock on a fast timer and keep the largest gap between
    // consecutive ticks.
    //
    // Counting ticks would prove nothing: createBackup awaits file I/O either
    // way, so some ticks always get through even when compression blocks the
    // isolate. The GAP is the discriminating signal — while Deflate.finish()
    // holds the isolate, no tick can fire at all.
    final ticks = <DateTime>[DateTime.now()];
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks.add(DateTime.now()),
    );

    final result = await build().createBackup(destination);
    timer.cancel();

    expect(result.isOk, isTrue);

    var maxGapMs = 0;
    for (var i = 1; i < ticks.length; i++) {
      final gap = ticks[i].difference(ticks[i - 1]).inMilliseconds;
      if (gap > maxGapMs) maxGapMs = gap;
    }
    expect(
      maxGapMs,
      lessThan(500),
      reason: 'the event loop stalled for ${maxGapMs}ms, so compression is '
          'still running on the calling isolate',
    );
  });

  test('surfaces a worker failure as Err rather than throwing', () async {
    // NOT a non-existent parent directory: createBackup creates those
    // recursively, so such a destination succeeds. Occupying the worker's temp
    // path with a directory makes its very first OutputFileStream open throw,
    // inside the isolate.
    final destination = path.join(tmp.path, 'backup.zip');
    await Directory('$destination.tmp').create();

    final result = await build().createBackup(destination);

    expect(result.isErr, isTrue);
  });

  test('leaves no .tmp file behind when the backup fails', () async {
    // The failure has to happen AFTER compression has written a real .tmp,
    // otherwise this asserts nothing. Occupying the FINAL destination with a
    // directory lets compression finish, then breaks the rename — so a genuine
    // temp file exists at failure time and the finally block must delete it.
    final destination = path.join(tmp.path, 'backup.zip');
    await Directory(destination).create();

    final result = await build().createBackup(destination);
    expect(result.isErr, isTrue);

    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/backup/database_backup_service_isolate_test.dart -r compact`
Expected: FAIL on `keeps the calling isolate responsive during compression` — the reported `maxGapMs` is well above 500, because `Deflate.finish()` still holds this isolate for the whole 64 MB. The other three tests already pass; they are regression cover for the change, not new behaviour.

**Do not proceed until you have seen this specific failure.** It is the only automated proof that the fix in this task does what it claims. If it passes before the change, the test is not discriminating and must be fixed first — raise it rather than continuing.

- [ ] **Step 3: Wrap the worker call in `Isolate.run`**

In `lib/services/backup/database_backup_service.dart`, add the import:

```dart
import 'dart:isolate';
```

Replace the `writeBackupArchive(...)` call added in Task 2 with:

```dart
      // Compression is CPU-bound and fully synchronous. Running it on the
      // calling isolate froze the UI for tens of seconds on a large database
      // (1.78 GB observed), which users read as a crash. Isolate.run keeps the
      // event loop free; it rethrows a worker exception here, so the catch
      // below still turns failures into Err(BackupException).
      final capturedZipPath = tempZipPath;
      final capturedSources = sources;
      final capturedWorkDir = workDir.path;
      await Isolate.run(
        () => writeBackupArchive(
          tempZipPath: capturedZipPath,
          sources: capturedSources,
          workDirPath: capturedWorkDir,
        ),
      );
```

The locals exist so the closure captures only sendable values and never `this`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/services/backup/database_backup_service_isolate_test.dart -r compact`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the whole backup suite**

Run: `flutter test test/unit/services/backup/ -r compact`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/database_backup_service.dart \
        test/unit/services/backup/database_backup_service_isolate_test.dart
git commit -m "fix(backup): run archive compression in a background isolate

Deflate.finish() is CPU-bound and fully synchronous; on the UI isolate it
froze the app for tens of seconds on a 1.78 GB database and Windows reported
'Not responding'. Isolate.run keeps the event loop free."
```

---

### Task 4: Progress polling and the `onProgress` parameter

**Files:**
- Create: `lib/services/backup/backup_progress_poller.dart`
- Modify: `lib/services/backup/database_backup_service.dart`
- Test: `test/unit/services/backup/backup_progress_poller_test.dart`
- Test: `test/unit/services/backup/database_backup_service_progress_test.dart`

**Interfaces:**
- Consumes: `BackupProgress`, `BackupPhase` (Task 1).
- Produces:
  - `class BackupProgressPoller` with `BackupProgressPoller({Duration interval = const Duration(milliseconds: 500)})`, `void start({required BackupPhase phase, required Future<int> Function() measure, required void Function(BackupProgress) onProgress})`, and `void stop()`.
  - `DatabaseBackupService.createBackup(String destinationPath, {void Function(BackupProgress)? onProgress})`.
  - `DatabaseBackupService({..., Duration progressInterval = const Duration(milliseconds: 500)})`.

The poller emits **one event immediately** on `start`, before the first timer tick. Without that, a fast backup could finish before any tick and emit nothing, which would make both the tests and the UI non-deterministic.

- [ ] **Step 1: Write the failing poller test**

Create `test/unit/services/backup/backup_progress_poller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/services/backup/backup_progress_poller.dart';

void main() {
  test('emits one event immediately on start', () async {
    final events = <BackupProgress>[];
    final poller = BackupProgressPoller(interval: const Duration(hours: 1));
    addTearDown(poller.stop);

    poller.start(
      phase: BackupPhase.snapshot,
      measure: () async => 42,
      onProgress: events.add,
    );
    // The immediate emission goes through one async hop for `measure`.
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.phase, BackupPhase.snapshot);
    expect(events.single.bytesDone, 42);
  });

  test('keeps emitting on each interval', () async {
    final events = <BackupProgress>[];
    var value = 0;
    final poller = BackupProgressPoller(
      interval: const Duration(milliseconds: 5),
    );
    addTearDown(poller.stop);

    poller.start(
      phase: BackupPhase.compressing,
      measure: () async => value += 10,
      onProgress: events.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    poller.stop();

    expect(events.length, greaterThan(2));
    expect(events.first.bytesDone, 10);
    // Values only ever grow.
    for (var i = 1; i < events.length; i++) {
      expect(events[i].bytesDone, greaterThanOrEqualTo(events[i - 1].bytesDone));
    }
  });

  test('reuses the last known value when measure throws', () async {
    // Stat-ing a file another isolate holds open can throw on Windows. A poll
    // failure must degrade the counter, never break the caller.
    final events = <BackupProgress>[];
    var calls = 0;
    final poller = BackupProgressPoller(
      interval: const Duration(milliseconds: 5),
    );
    addTearDown(poller.stop);

    poller.start(
      phase: BackupPhase.compressing,
      measure: () async {
        calls++;
        if (calls == 1) return 100;
        throw const FileSystemException('locked');
      },
      onProgress: events.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    poller.stop();

    expect(events.length, greaterThan(1));
    expect(events.every((e) => e.bytesDone == 100), isTrue);
  });

  test('stops emitting after stop', () async {
    final events = <BackupProgress>[];
    final poller = BackupProgressPoller(
      interval: const Duration(milliseconds: 5),
    );

    poller.start(
      phase: BackupPhase.snapshot,
      measure: () async => 1,
      onProgress: events.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    poller.stop();
    final countAtStop = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(events.length, countAtStop);
  });

  test('stop is safe to call when never started and twice in a row', () {
    final poller = BackupProgressPoller();
    expect(poller.stop, returnsNormally);
    expect(poller.stop, returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/backup/backup_progress_poller_test.dart -r compact`
Expected: FAIL — `Target of URI doesn't exist: 'package:twmt/services/backup/backup_progress_poller.dart'`

- [ ] **Step 3: Implement the poller**

Create `lib/services/backup/backup_progress_poller.dart`:

```dart
import 'dart:async';

import '../../models/backup/backup_progress.dart';

/// Samples an external measurement on a fixed interval and reports it as
/// [BackupProgress].
///
/// Progress is observed from *outside* the work being measured: the backup
/// worker runs in another isolate and is never asked how far along it is. The
/// poller simply stats the temp files it is writing. That keeps the whole
/// progress mechanism read-only and outside the backup's code path — it cannot
/// corrupt an archive, because it cannot influence one.
class BackupProgressPoller {
  /// How often [measure] is sampled after the immediate first emission.
  final Duration interval;

  Timer? _timer;
  int _lastValue = 0;

  BackupProgressPoller({this.interval = const Duration(milliseconds: 500)});

  /// Begin reporting [phase] progress.
  ///
  /// Emits once immediately so a fast operation still produces at least one
  /// event, then once per [interval] until [stop].
  void start({
    required BackupPhase phase,
    required Future<int> Function() measure,
    required void Function(BackupProgress) onProgress,
  }) {
    stop();
    _lastValue = 0;

    Future<void> sample() async {
      try {
        _lastValue = await measure();
      } catch (_) {
        // Keep the last known value. Stat-ing a file another isolate holds
        // open can throw on Windows; a poll failure must never affect the
        // backup or the caller.
      }
      onProgress(BackupProgress(phase: phase, bytesDone: _lastValue));
    }

    unawaited(sample());
    _timer = Timer.periodic(interval, (_) => unawaited(sample()));
  }

  /// Stop reporting. Safe to call when not started, and repeatedly.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Run the poller test to verify it passes**

Run: `flutter test test/unit/services/backup/backup_progress_poller_test.dart -r compact`
Expected: PASS, 5 tests.

- [ ] **Step 5: Write the failing service-level progress test**

Create `test/unit/services/backup/database_backup_service_progress_test.dart`:

```dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/noop_logger.dart';

Uint8List fakeSqliteBytes(int payloadSize, {int userVersion = 1, int seed = 7}) {
  final bytes = Uint8List(100 + payloadSize);
  const magic = 'SQLite format 3';
  for (var i = 0; i < magic.length; i++) {
    bytes[i] = magic.codeUnitAt(i);
  }
  bytes[15] = 0x00;
  bytes[60] = (userVersion >> 24) & 0xff;
  bytes[61] = (userVersion >> 16) & 0xff;
  bytes[62] = (userVersion >> 8) & 0xff;
  bytes[63] = userVersion & 0xff;
  final rnd = Random(seed);
  for (var i = 100; i < bytes.length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('twmt_backup_progress_test_');
    dbPath = path.join(tmp.path, 'twmt.db');
    await File(dbPath).writeAsBytes(fakeSqliteBytes(6 * 1024 * 1024));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DatabaseBackupService build() => DatabaseBackupService(
        logging: NoopLogger(),
        databasePathProvider: () async => dbPath,
        databaseCloser: () async {},
        databaseReinitializer: () async {},
        progressInterval: const Duration(milliseconds: 5),
      );

  test('reports compressing progress and still succeeds', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    final result =
        await build().createBackup(destination, onProgress: events.add);

    expect(result.isOk, isTrue);
    expect(
      events.any((e) => e.phase == BackupPhase.compressing),
      isTrue,
      reason: 'the immediate emission guarantees at least one event',
    );
  });

  test('byte counts never decrease within the compressing phase', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    await build().createBackup(destination, onProgress: events.add);

    final compressing = events
        .where((e) => e.phase == BackupPhase.compressing)
        .map((e) => e.bytesDone)
        .toList();
    for (var i = 1; i < compressing.length; i++) {
      expect(compressing[i], greaterThanOrEqualTo(compressing[i - 1]));
    }
  });

  test('stops reporting once the backup has returned', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    await build().createBackup(destination, onProgress: events.add);
    final countAtReturn = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events.length, countAtReturn);
  });

  test('stops reporting when the backup fails', () async {
    final events = <BackupProgress>[];
    // Occupy the worker's temp path with a directory so its first
    // OutputFileStream open throws. A non-existent parent directory would NOT
    // fail — createBackup creates those recursively.
    final destination = path.join(tmp.path, 'backup.zip');
    await Directory('$destination.tmp').create();

    final result =
        await build().createBackup(destination, onProgress: events.add);
    expect(result.isErr, isTrue);
    final countAtReturn = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events.length, countAtReturn);
  });

  test('works with no onProgress supplied', () async {
    final destination = path.join(tmp.path, 'backup.zip');
    final result = await build().createBackup(destination);
    expect(result.isOk, isTrue);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/unit/services/backup/database_backup_service_progress_test.dart -r compact`
Expected: FAIL — `No named parameter with the name 'progressInterval'` / `'onProgress'`.

- [ ] **Step 7: Wire the poller into `createBackup`**

In `lib/services/backup/database_backup_service.dart`:

Add imports:

```dart
import '../../models/backup/backup_progress.dart';
import 'backup_progress_poller.dart';
```

Add the field and constructor parameter (alongside `debugForceLegacySnapshot`):

```dart
  /// How often the progress poller samples the worker's temp files.
  final Duration progressInterval;
```

and in the constructor parameter list add `this.progressInterval = const Duration(milliseconds: 500),`.

Change the signature:

```dart
  Future<Result<String, BackupException>> createBackup(
    String destinationPath, {
    void Function(BackupProgress)? onProgress,
  }) async {
```

Declare the poller next to the other locals at the top of the method body:

```dart
    final poller = BackupProgressPoller(interval: progressInterval);
```

Wrap the `VACUUM INTO` call so the snapshot phase is reported:

```dart
      if (useVacuumInto) {
        final snapshotPath =
            path.join(workDir.path, DatabaseConfig.databaseName);
        _logging.debug('Creating consistent snapshot via VACUUM INTO');
        if (onProgress != null) {
          poller.start(
            phase: BackupPhase.snapshot,
            measure: () => _fileLength(snapshotPath),
            onProgress: onProgress,
          );
        }
        await DatabaseService.database
            .execute('VACUUM INTO ?', [snapshotPath]);
        poller.stop();
        sources.add((DatabaseConfig.databaseName, snapshotPath));
      } else {
```

Replace the whole block introduced in Task 3 — the three `captured*` locals and the `Isolate.run` call — with this. The captured locals are declared **first** so the poller can reuse `capturedWorkDir`; `workDir` itself is a nullable local and would need a `!` inside the closure.

```dart
      final capturedZipPath = tempZipPath;
      final capturedSources = sources;
      final capturedWorkDir = workDir.path;

      if (onProgress != null) {
        poller.start(
          phase: BackupPhase.compressing,
          measure: () =>
              _compressedBytesSoFar(capturedWorkDir, capturedZipPath),
          onProgress: onProgress,
        );
      }
      await Isolate.run(
        () => writeBackupArchive(
          tempZipPath: capturedZipPath,
          sources: capturedSources,
          workDirPath: capturedWorkDir,
        ),
      );
      poller.stop();
```

`workDir` is non-null at this point (it is assigned earlier in the `try`), but it is declared as `Directory? workDir;` for the `finally` cleanup, so Dart's flow analysis may still require `workDir!.path` here depending on the surrounding code. Use whichever the analyzer accepts — `flutter analyze` in step 9 will tell you.

Add `poller.stop();` as the **first** statement of the existing `finally` block, so every failure path stops it too.

Add the two measurement helpers as private methods on the class:

```dart
  /// Length of [filePath], or 0 when it does not exist yet.
  static Future<int> _fileLength(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return 0;
    return file.length();
  }

  /// Compressed bytes the worker has produced so far.
  ///
  /// Sums the per-entry `entry-*.deflate` scratch files plus the archive
  /// itself. The zip alone is a poor signal: [ZipEncoder.addFile] only appends
  /// an entry *after* its deflate has fully completed, so the archive would sit
  /// near zero for the whole compression and then jump. The `.deflate` files
  /// grow continuously, so they are what actually moves.
  static Future<int> _compressedBytesSoFar(
    String workDirPath,
    String tempZipPath,
  ) async {
    var total = await _fileLength(tempZipPath);
    final dir = Directory(workDirPath);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.deflate')) {
          total += await entity.length();
        }
      }
    }
    return total;
  }
```

- [ ] **Step 8: Run the progress test to verify it passes**

Run: `flutter test test/unit/services/backup/database_backup_service_progress_test.dart -r compact`
Expected: PASS, 5 tests.

- [ ] **Step 9: Run the whole backup suite and the architecture test**

Run: `flutter test test/unit/services/backup/ test/architecture/ -r compact`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/services/backup/backup_progress_poller.dart \
        lib/services/backup/database_backup_service.dart \
        test/unit/services/backup/backup_progress_poller_test.dart \
        test/unit/services/backup/database_backup_service_progress_test.dart
git commit -m "feat(backup): report backup progress by polling the worker's temp files

Progress is observed from outside the work: the main isolate stats the files
the worker writes. Read-only and entirely outside the backup's code path, so
it cannot affect archive contents."
```

---

### Task 5: `AutoBackupOutcome`

**Files:**
- Modify: `lib/services/backup/auto_backup_service.dart`
- Modify: `test/unit/services/backup/auto_backup_service_test.dart`

**Interfaces:**
- Consumes: `BackupProgress` (Task 1), the widened `createBackup` signature (Task 4).
- Produces: `sealed class AutoBackupOutcome` with `AutoBackupSkipped`, `AutoBackupCreated(String path)`, `AutoBackupFailure(String message)`; `Future<AutoBackupOutcome> runIfDue({void Function(BackupProgress)? onProgress})`.

`runIfDue` currently returns `null` both when it skips (`auto_backup_service.dart:71`) and when the backup fails (`:85`). The card cannot show an error state without telling those apart.

The class names avoid `AutoBackupFailed`, which Task 6 uses for a UI state.

- [ ] **Step 1: Update the existing test to the new API**

In `test/unit/services/backup/auto_backup_service_test.dart`:

Add the import:

```dart
import 'package:twmt/models/backup/backup_progress.dart';
```

Change `fakeCreate` and the `build` helper to the widened signature:

```dart
  Future<Result<String, BackupException>> fakeCreate(
    String destination, {
    void Function(BackupProgress)? onProgress,
  }) async {
    createCalls++;
    await File(destination).writeAsString('zip');
    return Ok(destination);
  }

  AutoBackupService build({
    Duration minInterval = const Duration(days: 1),
    int retain = 5,
    DateTime Function()? now,
    Future<Result<String, BackupException>> Function(
      String, {
      void Function(BackupProgress)? onProgress,
    })? createBackup,
  }) {
    return AutoBackupService(
      logging: NoopLogger(),
      backupDirectoryProvider: () async => backupDir.path,
      createBackup: createBackup ?? fakeCreate,
      now: now,
      minInterval: minInterval,
      retain: retain,
    );
  }
```

Replace the two outcome assertions:

- in `creates a backup when the directory is empty`, replace `expect(result, isNotNull);` with `expect(result, isA<AutoBackupCreated>());`
- in `skips when a recent backup already exists`, replace `expect(result, isNull);` with `expect(result, isA<AutoBackupSkipped>());`
- in `takes a new backup when the newest is older than minInterval`, replace `expect(result, isNotNull);` with `expect(result, isA<AutoBackupCreated>());`

Append these new tests before the closing `}`:

```dart
  test('reports a failed backup as AutoBackupFailure', () async {
    final service = build(
      createBackup: (destination, {onProgress}) async =>
          const Err(BackupException('disk on fire')),
    );

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupFailure>());
    expect((result as AutoBackupFailure).message, contains('disk on fire'));
  });

  test('reports a thrown error as AutoBackupFailure', () async {
    final service = build(
      createBackup: (destination, {onProgress}) async =>
          throw StateError('boom'),
    );

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupFailure>());
  });

  test('exposes the created path', () async {
    final service = build();

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupCreated>());
    expect((result as AutoBackupCreated).path, endsWith('.zip'));
  });

  test('forwards onProgress to the underlying backup', () async {
    BackupProgress? seen;
    final service = build(
      createBackup: (destination, {onProgress}) async {
        onProgress?.call(
          const BackupProgress(phase: BackupPhase.compressing, bytesDone: 5),
        );
        await File(destination).writeAsString('zip');
        return Ok(destination);
      },
    );

    await service.runIfDue(onProgress: (p) => seen = p);

    expect(seen, isNotNull);
    expect(seen!.bytesDone, 5);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/backup/auto_backup_service_test.dart -r compact`
Expected: FAIL — `Undefined name 'AutoBackupCreated'` and signature mismatches.

- [ ] **Step 3: Implement the outcome type and the new signature**

In `lib/services/backup/auto_backup_service.dart`, add the import:

```dart
import '../../models/backup/backup_progress.dart';
```

Add above the `AutoBackupService` class:

```dart
/// Result of an [AutoBackupService.runIfDue] attempt.
///
/// Exists so callers can distinguish "nothing to do" from "it broke": the two
/// used to be indistinguishable (both returned null), which made a silently
/// failing daily backup impossible to surface.
sealed class AutoBackupOutcome {
  const AutoBackupOutcome();
}

/// A recent backup already existed, so no new one was taken.
class AutoBackupSkipped extends AutoBackupOutcome {
  const AutoBackupSkipped();
}

/// A backup was written to [path].
class AutoBackupCreated extends AutoBackupOutcome {
  final String path;
  const AutoBackupCreated(this.path);
}

/// The backup was attempted and failed. [message] is English, like all log
/// content in this project; the UI pairs it with a localized title.
class AutoBackupFailure extends AutoBackupOutcome {
  final String message;
  const AutoBackupFailure(this.message);
}
```

Widen the injected function type:

```dart
  final Future<Result<String, BackupException>> Function(
    String destination, {
    void Function(BackupProgress)? onProgress,
  }) _createBackup;
```

and the matching constructor parameter:

```dart
    required Future<Result<String, BackupException>> Function(
      String destination, {
      void Function(BackupProgress)? onProgress,
    }) createBackup,
```

Rewrite `runIfDue`:

```dart
  /// Create a backup if one is due.
  ///
  /// Best-effort by contract: every failure is caught and reported as
  /// [AutoBackupFailure], never thrown, so a backup problem can never block
  /// startup.
  Future<AutoBackupOutcome> runIfDue({
    void Function(BackupProgress)? onProgress,
  }) async {
    try {
      final dirPath = await _backupDirectoryProvider();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final existing = await _listBackupsNewestFirst(dir);
      if (existing.isNotEmpty) {
        final age = _now().difference(await existing.first.lastModified());
        if (age < minInterval) {
          _logging.debug('Auto-backup skipped: recent backup exists', {
            'ageMinutes': age.inMinutes,
            'minIntervalMinutes': minInterval.inMinutes,
          });
          return const AutoBackupSkipped();
        }
      }

      final destination = path.join(dirPath, _generateFilename());
      _logging.info('Starting automatic database backup', {
        'destination': destination,
      });

      final result =
          await _createBackup(destination, onProgress: onProgress);
      if (result.isErr) {
        _logging.warning('Automatic backup failed', {
          'error': result.error.message,
        });
        return AutoBackupFailure(result.error.message);
      }

      _logging.info('Automatic database backup created', {'path': result.value});
      await _pruneOldBackups(dir);
      return AutoBackupCreated(result.value);
    } catch (e) {
      // Best-effort: never let a backup failure surface to the user/startup.
      _logging.warning('Automatic backup failed', {'error': e.toString()});
      return AutoBackupFailure(e.toString());
    }
  }
```

Update the class doc comment: replace the sentence starting `[runIfDue] takes a fresh backup only when...` — keep it, but change the trailing `It is intentionally best-effort: any failure is logged and swallowed so a backup problem can never block startup or the UI.` to:

```
/// It is intentionally best-effort: any failure is logged and reported as
/// [AutoBackupFailure] rather than thrown, so a backup problem can never block
/// startup or the UI.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/services/backup/auto_backup_service_test.dart -r compact`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/auto_backup_service.dart \
        test/unit/services/backup/auto_backup_service_test.dart
git commit -m "feat(backup): return a typed AutoBackupOutcome from runIfDue

Skip and failure both returned null, so a silently failing daily backup could
not be surfaced. runIfDue also forwards onProgress to the backup service."
```

---

### Task 6: The `AutoBackupStatus` provider

**Files:**
- Create: `lib/providers/backup/auto_backup_progress_provider.dart`
- Test: `test/providers/backup/auto_backup_progress_provider_test.dart`

**Interfaces:**
- Consumes: `BackupProgress`, `BackupPhase` (Task 1).
- Produces: `sealed class AutoBackupUiState` with `AutoBackupIdle`, `AutoBackupRunning(BackupProgress progress)`, `AutoBackupDone`, `AutoBackupError(String message)`; notifier `AutoBackupStatus` exposing `report(BackupProgress)`, `succeeded()`, `failed(String)`, `dismiss()`; provider `autoBackupStatusProvider`.

The notifier holds no timer. The "Done" hold is a presentation concern and lives in the widget (Task 7), which keeps this notifier trivially testable and free of pending timers.

- [ ] **Step 1: Write the failing test**

Create `test/providers/backup/auto_backup_progress_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/providers/backup/auto_backup_progress_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  AutoBackupStatus notifier() =>
      container.read(autoBackupStatusProvider.notifier);

  AutoBackupUiState state() => container.read(autoBackupStatusProvider);

  test('starts idle', () {
    expect(state(), isA<AutoBackupIdle>());
  });

  test('report moves to running and carries the progress', () {
    notifier().report(
      const BackupProgress(phase: BackupPhase.compressing, bytesDone: 99),
    );

    final s = state();
    expect(s, isA<AutoBackupRunning>());
    expect((s as AutoBackupRunning).progress.bytesDone, 99);
    expect(s.progress.phase, BackupPhase.compressing);
  });

  test('succeeded moves to done', () {
    notifier().report(
      const BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1),
    );
    notifier().succeeded();

    expect(state(), isA<AutoBackupDone>());
  });

  test('failed moves to error and carries the message', () {
    notifier().failed('disk on fire');

    final s = state();
    expect(s, isA<AutoBackupError>());
    expect((s as AutoBackupError).message, 'disk on fire');
  });

  test('dismiss returns to idle from any state', () {
    notifier().failed('nope');
    notifier().dismiss();
    expect(state(), isA<AutoBackupIdle>());

    notifier().succeeded();
    notifier().dismiss();
    expect(state(), isA<AutoBackupIdle>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/backup/auto_backup_progress_provider_test.dart -r compact`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the provider**

Create `lib/providers/backup/auto_backup_progress_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/backup/backup_progress.dart';

part 'auto_backup_progress_provider.g.dart';

/// What the automatic-backup card should show.
sealed class AutoBackupUiState {
  const AutoBackupUiState();
}

/// Nothing to show.
class AutoBackupIdle extends AutoBackupUiState {
  const AutoBackupIdle();
}

/// A backup is running.
class AutoBackupRunning extends AutoBackupUiState {
  final BackupProgress progress;
  const AutoBackupRunning(this.progress);
}

/// The backup finished. The card holds this briefly, then dismisses itself.
class AutoBackupDone extends AutoBackupUiState {
  const AutoBackupDone();
}

/// The backup failed. [message] is the English service message, shown as
/// diagnostic detail under a localized title. This state is persistent: only
/// the user dismisses it.
class AutoBackupError extends AutoBackupUiState {
  final String message;
  const AutoBackupError(this.message);
}

/// App-global state of the startup auto-backup.
///
/// Kept alive because the backup outlives any single screen, and the card that
/// renders it lives in the app-level overlay stack rather than in a route.
///
/// Holds no timer: the brief "Done" hold before the card fades out is a
/// presentation concern and belongs to the widget.
@Riverpod(keepAlive: true)
class AutoBackupStatus extends _$AutoBackupStatus {
  @override
  AutoBackupUiState build() => const AutoBackupIdle();

  /// Report an observation from a running backup.
  void report(BackupProgress progress) =>
      state = AutoBackupRunning(progress);

  /// The backup completed successfully.
  void succeeded() => state = const AutoBackupDone();

  /// The backup failed with [message] (English, from the service layer).
  void failed(String message) => state = AutoBackupError(message);

  /// Return to idle — the card disappears.
  void dismiss() => state = const AutoBackupIdle();
}
```

- [ ] **Step 4: Run code generation**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `lib/providers/backup/auto_backup_progress_provider.g.dart`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/providers/backup/auto_backup_progress_provider_test.dart -r compact`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/backup/ test/providers/backup/
git commit -m "feat(backup): add the AutoBackupStatus provider"
```

---

### Task 7: The progress card widget and its translations

**Files:**
- Create: `lib/widgets/backup/auto_backup_progress_card.dart`
- Modify: `lib/i18n/en/bootstrap.i18n.json` and the same file under `de`, `es`, `fr`, `ko`, `pt`, `pt-BR`, `ru`, `tr`, `zh` (11 files total)
- Test: `test/widgets/backup/auto_backup_progress_card_test.dart`

**Interfaces:**
- Consumes: `AutoBackupUiState` and `autoBackupStatusProvider` (Task 6), `BackupProgress` (Task 1).
- Produces: `class AutoBackupProgressCard extends ConsumerStatefulWidget` with `const AutoBackupProgressCard({super.key})`. Renders a `Positioned` when visible and `SizedBox.shrink()` when idle, so it can sit directly in the app overlay `Stack`.

The widget owns the ~1.5 s "Done" hold: on entering `AutoBackupDone` it starts a timer that calls `dismiss()`. That keeps the notifier free of pending timers and lets widget tests advance the clock with `tester.pump(...)`.

Deliberately **no tooltip and no selectable text**, so — unlike `LogConsoleOverlay` — this widget needs no nested `Overlay` ancestor.

- [ ] **Step 1: Add the English translation keys**

In `lib/i18n/en/bootstrap.i18n.json`, add a sibling of `modScan` and `validationRescan`:

```json
  "autoBackup": {
    "title": "Automatic backup",
    "snapshotting": "Snapshotting database… $size",
    "compressing": "Compressing… $size written",
    "done": "Backup complete",
    "failedTitle": "Automatic backup failed",
    "dismiss": "Dismiss"
  }
```

- [ ] **Step 2: Add the same block to the other 10 locales**

`lib/i18n/fr/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "Sauvegarde automatique",
    "snapshotting": "Instantané de la base… $size",
    "compressing": "Compression… $size écrits",
    "done": "Sauvegarde terminée",
    "failedTitle": "Échec de la sauvegarde automatique",
    "dismiss": "Fermer"
  }
```

`lib/i18n/de/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "Automatische Sicherung",
    "snapshotting": "Datenbank-Snapshot… $size",
    "compressing": "Komprimierung… $size geschrieben",
    "done": "Sicherung abgeschlossen",
    "failedTitle": "Automatische Sicherung fehlgeschlagen",
    "dismiss": "Schließen"
  }
```

`lib/i18n/es/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "Copia de seguridad automática",
    "snapshotting": "Creando instantánea de la base de datos… $size",
    "compressing": "Comprimiendo… $size escritos",
    "done": "Copia de seguridad completada",
    "failedTitle": "Error en la copia de seguridad automática",
    "dismiss": "Cerrar"
  }
```

`lib/i18n/pt/bootstrap.i18n.json` and `lib/i18n/pt-BR/bootstrap.i18n.json` (identical content):

```json
  "autoBackup": {
    "title": "Backup automático",
    "snapshotting": "Criando snapshot do banco de dados… $size",
    "compressing": "Compactando… $size gravados",
    "done": "Backup concluído",
    "failedTitle": "Falha no backup automático",
    "dismiss": "Fechar"
  }
```

`lib/i18n/ru/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "Автоматическое резервное копирование",
    "snapshotting": "Создание снимка базы данных… $size",
    "compressing": "Сжатие… записано $size",
    "done": "Резервное копирование завершено",
    "failedTitle": "Не удалось создать резервную копию",
    "dismiss": "Закрыть"
  }
```

`lib/i18n/tr/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "Otomatik yedekleme",
    "snapshotting": "Veritabanı anlık görüntüsü alınıyor… $size",
    "compressing": "Sıkıştırılıyor… $size yazıldı",
    "done": "Yedekleme tamamlandı",
    "failedTitle": "Otomatik yedekleme başarısız",
    "dismiss": "Kapat"
  }
```

`lib/i18n/ko/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "자동 백업",
    "snapshotting": "데이터베이스 스냅샷 생성 중… $size",
    "compressing": "압축 중… $size 기록됨",
    "done": "백업 완료",
    "failedTitle": "자동 백업 실패",
    "dismiss": "닫기"
  }
```

`lib/i18n/zh/bootstrap.i18n.json`:

```json
  "autoBackup": {
    "title": "自动备份",
    "snapshotting": "正在创建数据库快照… $size",
    "compressing": "正在压缩… 已写入 $size",
    "done": "备份完成",
    "failedTitle": "自动备份失败",
    "dismiss": "关闭"
  }
```

- [ ] **Step 3: Regenerate the translation bindings**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lib/i18n/strings*.g.dart` regenerated with `t.bootstrap.autoBackup.*`.

- [ ] **Step 4: Write the failing widget test**

Create `test/widgets/backup/auto_backup_progress_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/providers/backup/auto_backup_progress_provider.dart';
// slateTokens lives in tokens/, NOT in twmt_theme_tokens.dart — that file
// declares the TwmtThemeTokens class and the context.tokens extension only.
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/backup/auto_backup_progress_card.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: const Stack(children: [AutoBackupProgressCard()]),
        ),
      ),
    );
  }

  AutoBackupStatus notifier() =>
      container.read(autoBackupStatusProvider.notifier);

  testWidgets('renders nothing when idle', (tester) async {
    await pumpCard(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('backup', findRichText: true), findsNothing);
  });

  testWidgets('shows the snapshot phase with a byte counter', (tester) async {
    notifier().report(
      const BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1536),
    );
    await pumpCard(tester);

    expect(find.textContaining('1.5 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the compressing phase with a byte counter',
      (tester) async {
    notifier().report(
      const BackupProgress(
        phase: BackupPhase.compressing,
        bytesDone: 5 * 1024 * 1024,
      ),
    );
    await pumpCard(tester);

    expect(find.textContaining('5.0 MB'), findsOneWidget);
  });

  testWidgets('the progress bar is always indeterminate', (tester) async {
    notifier().report(
      const BackupProgress(phase: BackupPhase.compressing, bytesDone: 10),
    );
    await pumpCard(tester);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      bar.value,
      isNull,
      reason: 'no honest denominator exists for either phase',
    );
  });

  testWidgets('holds "done" briefly, then dismisses itself', (tester) async {
    notifier().succeeded();
    await pumpCard(tester);
    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);

    // Still visible just before the hold elapses.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);

    // Gone after it elapses (plus the fade).
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(container.read(autoBackupStatusProvider), isA<AutoBackupIdle>());
    expect(find.byKey(const Key('autoBackupCard')), findsNothing);
  });

  testWidgets('the error state persists and is not auto-dismissed',
      (tester) async {
    notifier().failed('disk on fire');
    await pumpCard(tester);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);
    expect(find.textContaining('disk on fire'), findsOneWidget);
    expect(container.read(autoBackupStatusProvider), isA<AutoBackupError>());
  });

  testWidgets('the error state is dismissed by its close button',
      (tester) async {
    notifier().failed('disk on fire');
    await pumpCard(tester);

    await tester.tap(find.byKey(const Key('autoBackupDismiss')));
    await tester.pumpAndSettle();

    expect(container.read(autoBackupStatusProvider), isA<AutoBackupIdle>());
  });
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `flutter test test/widgets/backup/auto_backup_progress_card_test.dart -r compact`
Expected: FAIL — `Target of URI doesn't exist: 'package:twmt/widgets/backup/auto_backup_progress_card.dart'`

- [ ] **Step 6: Implement the card**

Create `lib/widgets/backup/auto_backup_progress_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';

import '../../models/backup/backup_progress.dart';
import '../../providers/backup/auto_backup_progress_provider.dart';
import '../../theme/twmt_theme_tokens.dart';

/// Discreet bottom-right card reporting the startup automatic backup.
///
/// Designed to sit as a direct child of the `MaterialApp.builder` [Stack],
/// beside `LogConsoleOverlay`, so it survives navigation and is not tied to
/// the router shell. It renders a [Positioned] when visible and an empty box
/// otherwise, and it never blocks input: a [Stack] only absorbs pointer events
/// inside its positioned children.
///
/// The backup itself is non-blocking — compression runs in a background
/// isolate — so this card is purely informative. Its job is to explain the
/// disk activity, which users previously experienced as a frozen app.
///
/// Unlike `LogConsoleOverlay` this needs no nested [Overlay]: it hosts no
/// tooltip and no selectable text.
class AutoBackupProgressCard extends ConsumerStatefulWidget {
  const AutoBackupProgressCard({super.key});

  /// How long the "done" confirmation stays before the card fades out. Long
  /// enough to be read, short enough not to linger.
  static const doneHold = Duration(milliseconds: 1500);

  @override
  ConsumerState<AutoBackupProgressCard> createState() =>
      _AutoBackupProgressCardState();
}

class _AutoBackupProgressCardState
    extends ConsumerState<AutoBackupProgressCard> {
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  /// Start the auto-dismiss countdown when the backup completes. The error
  /// state deliberately gets no timer: a failed backup is a data-safety matter
  /// and stays until the user acknowledges it.
  void _scheduleDismissIfDone(AutoBackupUiState state) {
    if (state is! AutoBackupDone) {
      _doneTimer?.cancel();
      _doneTimer = null;
      return;
    }
    if (_doneTimer != null) return;
    _doneTimer = Timer(AutoBackupProgressCard.doneHold, () {
      _doneTimer = null;
      if (mounted) {
        ref.read(autoBackupStatusProvider.notifier).dismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(autoBackupStatusProvider);
    _scheduleDismissIfDone(state);

    if (state is AutoBackupIdle) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _card(context, state),
      ),
    );
  }

  Widget _card(BuildContext context, AutoBackupUiState state) {
    final tokens = context.tokens;
    final isError = state is AutoBackupError;

    return Material(
      key: const Key('autoBackupCard'),
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? tokens.errBg : tokens.panel,
          border: Border.all(color: isError ? tokens.err : tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _body(context, state, tokens),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AutoBackupUiState state,
    TwmtThemeTokens tokens,
  ) {
    switch (state) {
      case AutoBackupIdle():
        return const [];

      case AutoBackupRunning(:final progress):
        return [
          Text(
            t.bootstrap.autoBackup.title,
            style: TextStyle(color: tokens.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            switch (progress.phase) {
              BackupPhase.snapshot => t.bootstrap.autoBackup
                  .snapshotting(size: progress.formattedBytes),
              BackupPhase.compressing => t.bootstrap.autoBackup
                  .compressing(size: progress.formattedBytes),
            },
            style: TextStyle(color: tokens.textMid, fontSize: 12),
          ),
          const SizedBox(height: 10),
          // Always indeterminate: neither phase has an honest denominator.
          const LinearProgressIndicator(),
        ];

      case AutoBackupDone():
        return [
          Text(
            t.bootstrap.autoBackup.done,
            style: TextStyle(color: tokens.ok, fontWeight: FontWeight.w600),
          ),
        ];

      case AutoBackupError(:final message):
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.bootstrap.autoBackup.failedTitle,
                  style: TextStyle(
                    color: tokens.err,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                key: const Key('autoBackupDismiss'),
                onTap: () =>
                    ref.read(autoBackupStatusProvider.notifier).dismiss(),
                child: Icon(Icons.close, size: 16, color: tokens.textMid),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // English by project convention (log content is never localized);
          // shown as diagnostic detail under the localized title above.
          Text(
            message,
            style: TextStyle(color: tokens.textDim, fontSize: 11),
          ),
        ];
    }
  }
}
```

- [ ] **Step 7: Run the widget test to verify it passes**

Run: `flutter test test/widgets/backup/auto_backup_progress_card_test.dart -r compact`
Expected: PASS, 7 tests.

- [ ] **Step 8: Verify the architecture boundary holds**

Run: `flutter test test/architecture/import_boundaries_test.dart -r compact`
Expected: PASS — the card imports models, providers, theme and i18n, never a feature.

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/backup/ lib/i18n/ test/widgets/backup/
git commit -m "feat(backup): add the auto-backup progress card

Indeterminate bar plus a live byte counter -- the counter is what proves the
app is alive, and unlike an estimated percentage it never lies. The error
state persists until the user dismisses it."
```

---

### Task 8: Wire it into startup

**Files:**
- Modify: `lib/main.dart` (the `Stack` at 169-174, and `_runAutoBackup` at 299-314)

**Interfaces:**
- Consumes: everything from Tasks 1, 5, 6, 7.
- Produces: no new API. This is the final wiring.

- [ ] **Step 1: Mount the card in the app overlay stack**

In `lib/main.dart`, add the import:

```dart
import 'widgets/backup/auto_backup_progress_card.dart';
```

and extend the existing `Stack`:

```dart
      builder: (context, child) => _AppStartupTasks(
        child: Stack(
          children: [
            child!,
            const LogConsoleOverlay(),
            const AutoBackupProgressCard(),
          ],
        ),
      ),
```

- [ ] **Step 2: Feed the provider from `_runAutoBackup`**

Add the imports:

```dart
import 'models/backup/backup_progress.dart';
import 'providers/backup/auto_backup_progress_provider.dart';
```

Replace the whole `_runAutoBackup` method with:

```dart
  Future<void> _runAutoBackup() async {
    final status = ref.read(autoBackupStatusProvider.notifier);
    try {
      final backupService = ref.read(databaseBackupServiceProvider);
      final autoBackup = AutoBackupService(
        logging: ServiceLocator.get<ILoggingService>(),
        backupDirectoryProvider: () async => path.join(
          await DatabaseConfig.getAppSupportDirectory(),
          'backups',
        ),
        createBackup: backupService.createBackup,
      );
      final outcome = await autoBackup.runIfDue(
        onProgress: (progress) {
          if (mounted) status.report(progress);
        },
      );
      if (!mounted) return;
      switch (outcome) {
        // Nothing ran, so nothing to show.
        case AutoBackupSkipped():
          break;
        case AutoBackupCreated():
          status.succeeded();
        case AutoBackupFailure(:final message):
          status.failed(message);
      }
    } catch (_) {
      // Best-effort; AutoBackupService logs its own failures internally and
      // returns AutoBackupFailure rather than throwing, so reaching here means
      // the wiring itself broke. Leave the card idle rather than alarm the user
      // about something they cannot act on.
    }
  }
```

Note the comment above `unawaited(_runAutoBackup());` (main.dart:284-285) still says *"AutoBackupService skips when a recent backup already exists and prunes old archives itself"* — that remains accurate; leave it. Change only the line reading `// Runs in the background (fire-and-forget); AutoBackupService skips when a` block if it claims the compression blocks; it does not, so no edit is required.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: No issues. A non-exhaustive `switch` on the sealed `AutoBackupOutcome` would be reported here.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS.

If a `PathExistsException` about a native sqlite3 DLL appears, a stale `flutter_tester` process is holding it — kill leftover `flutter_tester` processes and delete the stale DLL, then re-run. An intermittent off-by-one failure in a token/tiktoken test is a known flake under full-suite parallelism and is unrelated to this work.

- [ ] **Step 5: Verify by hand on the real app**

Run: `flutter run -d windows`

To force a backup instead of waiting a day, temporarily delete the newest `TWMT_AutoBackup_*.zip` from `%APPDATA%\com.github.slavyk82\twmt\backups` before launching.

Confirm:
1. The card appears bottom-right during the backup.
2. **The window stays responsive** — navigate between screens while the byte counter climbs. This is the actual acceptance criterion.
3. The card shows "Backup complete", then disappears on its own.
4. A new `TWMT_AutoBackup_*.zip` exists and is roughly the size of the previous ones.

- [ ] **Step 6: Verify the new archive restores**

In the running app, go to Settings → Backup and restore the archive just produced. It must validate and restore successfully. This is the end-to-end proof that moving the compression into an isolate did not change archive contents.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart
git commit -m "feat(backup): show auto-backup progress at startup

The daily backup no longer freezes the app, and a discreet card explains the
disk activity instead of leaving the user staring at an unresponsive window."
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
| --- | --- |
| Worker relocated verbatim, pure Dart | 2 |
| `Isolate.run` | 3 |
| Progress by filesystem polling, `.deflate` files not the zip | 4 |
| Poll failure tolerated | 4 (poller test 3, service test) |
| Timer cancelled on every path | 4 (`finally`), tested in 4 |
| No percentage, no `bytesTotal` | 1 (model), 7 (bar asserted indeterminate) |
| Optional `onProgress`, manual backup unchanged | 4 (test `works with no onProgress supplied`) |
| `AutoBackupOutcome` | 5 |
| `AutoBackupUiState` provider | 6 |
| Card in the global overlay stack, no `SnackBar` | 7, 8 |
| "Done" hold ~1.5 s then fade | 7 |
| Persistent error card with localized title + English detail | 7 |
| 6 keys × 11 locales | 7 |
| Architecture boundaries stay green | 2, 4, 7 |
| Round-trip / content fidelity | 2 (worker), 8 step 6 (real app) |

**Type consistency**

- `writeBackupArchive` returns `Future<void>` (the returned-warnings channel prescribed in the first draft was unreachable dead code -- `zipOutput = null` is the last statement of the `try`, so the `finally` branch only runs while an exception unwinds past the `return`). Tasks 3 and 4 simply `await` it.
- `BackupProgress({required phase, required bytesDone})` and `formattedBytes` are used identically in Tasks 4, 6, 7.
- `BackupProgressPoller.start({phase, measure, onProgress})` / `stop()` match between Task 4's implementation and its use in `createBackup`.
- Outcome names (`AutoBackupSkipped` / `AutoBackupCreated` / `AutoBackupFailure`, Task 5) are deliberately distinct from UI-state names (`AutoBackupIdle` / `AutoBackupRunning` / `AutoBackupDone` / `AutoBackupError`, Task 6); Task 8 uses both in one file.
- `progressInterval` is the constructor parameter name in Task 4's implementation and in both of its test files.

**Known gap, accepted**

Restore still inflates synchronously on the UI isolate and will still freeze the app. That is an explicit non-goal of the spec, not an oversight.
