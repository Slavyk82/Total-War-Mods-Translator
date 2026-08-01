# Non-blocking automatic backup with visible progress

**Date:** 2026-08-02
**Status:** Approved (design)
**Area:** `lib/services/backup`, `lib/providers`, `lib/widgets`, `lib/main.dart`

## Problem

When the daily automatic backup runs at startup, the whole application freezes
for tens of seconds. Windows marks the window "Not responding" and the user
reasonably concludes the app has crashed.

The freeze is *not* caused by the backup being awaited — `_runAutoBackup()` is
already fire-and-forget (`main.dart:287`). The real cause is that the archive
compression runs **synchronously on the UI isolate**:

- `DatabaseBackupService._addFileToZipStreamed()` calls
  `Deflate.buffer(input, level: BEST_SPEED, output: deflateOutput)` followed by
  `deflate.finish()` (`database_backup_service.dart:315-320`). This is a
  CPU-bound, fully synchronous Dart loop. Nothing else on the isolate — not a
  single frame — can run until it returns.
- `VACUUM INTO` is **not** a contributor: `sqflite_common_ffi` executes database
  operations on its own background isolate.

Scale, measured on the reporting user's installation:

| Artifact | Size |
| --- | --- |
| `twmt.db` | 1.78 GB |
| `TWMT_AutoBackup_*.zip` | ~362 MB |

Compressing 1.78 GB at `BEST_SPEED` on the UI isolate is the observed multi-tens-of-seconds hang.

### Consequence for the original request

The request was "show a popup with progress during the backup". A popup alone
cannot work: while `Deflate.finish()` holds the isolate, no frame is rendered,
so the dialog would paint once and freeze — no spinner animation, no progress,
and still "Not responding". Moving compression off the UI isolate is a
prerequisite, not an optional extra.

## Goals

1. The application stays fully responsive during an automatic backup.
2. The user sees a discreet, non-blocking indicator explaining the disk activity,
   with real progress, that disappears on its own when the backup completes.
3. A failed automatic backup stops being silent.

## Non-goals

- Progress UI for the manual backup (Settings) or for restore. Both keep their
  current UI. The manual backup nevertheless **inherits the un-freeze for free**,
  because it calls the same `createBackup()`. Restore is untouched and keeps its
  synchronous inflate; it can be addressed separately.
- Any change to the backup archive format, the retention policy, or the
  once-per-day scheduling.

## Decisions

| Question | Decision |
| --- | --- |
| Block the UI during backup? | No. The backup is fully non-blocking. |
| How visible? | Discreet card, bottom-right, auto-dismissing. |
| On failure? | Persistent error card, dismissed by the user. |
| Scope of progress UI | Automatic backup only. |

Working during a backup is safe: `VACUUM INTO` produces a transactionally
consistent snapshot while writers continue, and phase 2 compresses that
snapshot file — the live database is not touched at all during compression.

## Architecture

### 1. Compression moves to a background isolate

New file `lib/services/backup/backup_archive_worker.dart` — pure Dart,
top-level functions, depending only on `dart:io`, `dart:isolate` and `archive`.
No Flutter, no Riverpod, no sqflite, no GetIt. This keeps
`test/architecture/import_boundaries_test.dart` green and makes the worker
usable under `flutter test`.

`DatabaseBackupService.createBackup()` delegates archive writing to
`Isolate.run()`, passing a `SendPort` for progress. `Isolate.run` rethrows a
worker exception in the caller, so the existing `try/catch/finally` in
`createBackup` keeps working unchanged, including its temp-file cleanup.

### 2. Chunked deflate

The monolithic `Deflate.buffer(...).finish()` becomes a loop driven inside the
worker, using the `archive` package's incremental API (`Deflate.addBytes`,
`deflate.dart:57`):

```dart
final deflate = Deflate.buffer(
  InputStream(Uint8List(0)),
  level: Deflate.BEST_SPEED,
  flush: Deflate.NO_FLUSH,
  output: deflateOutput,
);
while (!input.isEOS) {
  final chunk = input.readBytes(chunkSize).toUint8List();
  if (chunk.isEmpty) break;
  deflate.addBytes(chunk, flush: Deflate.NO_FLUSH);
  bytesDone += chunk.length;            // progress point
}
deflate.addBytes(const <int>[], flush: Deflate.FINISH);
deflate.finish();
crc32 = deflate.crc32;
```

Chunk size 4 MB. Progress events throttled to ~200 ms so the port is not
flooded (1.78 GB / 4 MB ≈ 440 raw events).

**Why this stays byte-compatible.** `Deflate.crc32` accumulates across
successive `addBytes` calls — `crc32 = getCrc32(bytes, crc32)` in `_readBuf`
(`deflate.dart:1218`) — and is reset only in `_init`, which the constructor
calls once. `NO_FLUSH` is the standard zlib "keep compressing" mode and injects
no flush markers. `BEST_SPEED` is preserved, so archives remain readable by the
existing `validateBackup` / `restoreBackup` paths. This is the single riskiest
change in the design and is pinned by the round-trip test below.

### 3. Two phases, honestly reported

| Phase | Work | Display |
| --- | --- | --- |
| `snapshot` | `VACUUM INTO` (sqflite isolate) | Indeterminate bar + bytes written |
| `compressing` | worker isolate | Exact percentage + `done / total` |

Phase 1 is deliberately **indeterminate**. `VACUUM INTO` exposes no progress
hook, so `createBackup` polls `File(snapshotPath).length()` on a ~500 ms timer
while awaiting the statement, and reports that count as `bytesDone` with
`bytesTotal = 0`.

The byte count is shown, but **not** turned into a percentage: `VACUUM INTO`
defragments, so the snapshot ends up *smaller* than the source database. A
fraction computed against the source size would climb, reach 100%, and then
stall — visibly wrong. A byte counter with an indeterminate bar reports exactly
what is known and nothing more.

### 4. Progress transport

`createBackup()` gains an **optional** parameter:

```dart
Future<Result<String, BackupException>> createBackup(
  String destinationPath, {
  void Function(BackupProgress)? onProgress,
})
```

`createBackup` owns the `ReceivePort`: it listens for the worker's progress
messages and invokes `onProgress` from that listener. `onProgress` therefore
always fires on the **main isolate**, and callers may touch Riverpod state
directly from it without any cross-isolate concern. The port is closed in
`createBackup`'s `finally` block, on every path.

Consequences:

- `lib/services/**` stays pure Dart with the dependency injected through the
  call site — consistent with the enforced architecture rules and with how
  `AutoBackupService` already takes function types.
- `lib/features/settings/providers/backup_providers.dart:109` needs **no
  change** and still gets the responsive UI.

New model `lib/models/backup/backup_progress.dart`:

```dart
enum BackupPhase { snapshot, compressing }

class BackupProgress {
  final BackupPhase phase;
  final int bytesDone;
  final int bytesTotal;          // 0 when unknown
  double? get fraction => bytesTotal > 0 ? bytesDone / bytesTotal : null;
}
```

New provider `lib/providers/backup/auto_backup_progress_provider.dart`
(`@riverpod`, requires `build_runner`) holding:

```
AutoBackupUiState = idle | running(BackupProgress) | done | failed(String message)
```

`_runAutoBackup()` in `main.dart` feeds it.

### 5. `runIfDue` must distinguish skip from failure

`AutoBackupService.runIfDue()` currently returns `null` both when the run is
skipped because a recent backup exists (`auto_backup_service.dart:71`) and when
the backup failed (`:85`). The provider cannot tell them apart, so the error
card is not expressible. The return type becomes:

```dart
sealed class AutoBackupOutcome {}      // skipped | created(String path) | failed(String message)
```

This is a signature change; `test/unit/services/backup/auto_backup_service_test.dart`
is updated accordingly. The best-effort contract is unchanged: a failure is
still caught, logged, and never propagated into startup.

`AutoBackupService` also has to *carry* the progress callback, since it wraps
`createBackup` behind an injected function type
(`auto_backup_service.dart:23-24`). Its injected type widens to accept the
optional callback, and `runIfDue` gains a matching optional parameter that it
forwards:

```dart
final Future<Result<String, BackupException>> Function(
  String destination, {
  void Function(BackupProgress)? onProgress,
}) _createBackup;

Future<AutoBackupOutcome> runIfDue({void Function(BackupProgress)? onProgress});
```

This keeps the wiring in `main.dart` a one-liner (`createBackup:
backupService.createBackup`) and leaves `AutoBackupService` free of any Flutter
or Riverpod dependency.

## UI

New widget `lib/widgets/backup/auto_backup_progress_card.dart`, mounted in the
existing global overlay `Stack` in `MaterialApp.builder` (`main.dart:169`),
next to `LogConsoleOverlay`. That `Stack` sits above **all** routes, so the card
survives navigation and does not depend on the router shell.

A plain `Positioned(bottom: 16, right: 16)` is enough — unlike
`LogConsoleOverlay`, this card needs no nested `Overlay`, because it hosts no
tooltip and no selectable text. Deliberately **no `SnackBar`**: the app shell is
`FluentScaffold`, not a Material `Scaffold`, so `ScaffoldMessenger` throws.

Width ~320 px, fade in/out.

| State | Rendering |
| --- | --- |
| `idle` | `SizedBox.shrink()` |
| `running(snapshot)` | "Snapshotting database… 1.2 GB", indeterminate bar |
| `running(compressing)` | "Compressing… 45%", determinate bar, "812 MB / 1.78 GB" |
| `done` | "Done" held ~1.5 s, then fades out |
| `failed` | Red card, persistent, close button |

The short "Done" hold prevents the card from vanishing without the user
understanding what happened.

### Error presentation

The card shows a **localized title** plus the raw technical message underneath
in a smaller, muted style. `BackupException.message` is English by project
convention (log content is always English; only UI chrome is localized), so it
is presented as diagnostic detail rather than as the primary message.

### Localization

~6 new keys under `bootstrap.autoBackup` in `bootstrap.i18n.json`, filled for
all 11 locales (en, fr, de, es, ko, pt, pt-BR, ru, tr, zh).

## Testing

| # | Test | Why |
| --- | --- | --- |
| 1 | **Round-trip**: create an archive via the chunked deflate → `validateBackup` succeeds → `restoreBackup` → data identical | The critical test. Proves the chunked deflate stays byte-compatible with the existing read paths. |
| 2 | Source larger than `chunkSize` (multiple `addBytes` calls) | Verifies CRC-32 accumulates correctly across chunks. |
| 3 | Zero-byte source (TRUNCATE-checkpointed WAL) | The loop must exit cleanly and still emit a valid empty entry. |
| 4 | Progress callback | Monotonically increasing, final event equals total, phases in order. |
| 5 | `AutoBackupOutcome` | `skipped` / `created` / `failed` are distinguishable. |
| 6 | Widget test for the card | Each state renders; the error state persists until the close button is tapped. |
| 7 | `test/architecture/import_boundaries_test.dart` | Must stay green — the worker is pure Dart. |

Existing repo test conventions apply (mocktail repos, `NoopLogger`, real temp
directories, theme-token extension for widget tests).

## Risks

- **Archive compatibility** (highest). Mitigated by test 1, which exercises the
  full create → validate → restore cycle rather than just asserting the file
  exists.
- **`Deflate.buffer` with an empty initial input and `flush: NO_FLUSH`** must be
  a no-op. Covered by tests 1-3; if it misbehaves, the fallback is to construct
  the deflater from the first chunk instead of an empty buffer.
- **Isolate memory**: the worker holds one 4 MB chunk plus deflate window
  buffers. Peak memory stays bounded, matching the existing streaming design.

## Out of scope, noted

A zero-byte `TWMT_Backup_2026-07-25_184028.zip.tmp` was found in the user's
`backups` directory — the residue of a manual backup whose process was killed
before `createBackup`'s `finally` cleanup ran. Harmless; not addressed here.
