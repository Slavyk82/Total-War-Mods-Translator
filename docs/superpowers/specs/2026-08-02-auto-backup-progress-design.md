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
   with live evidence of progress, that disappears on its own when the backup
   completes.
3. A failed automatic backup stops being silent.

## Non-goals

- Progress UI for the manual backup (Settings) or for restore. Both keep their
  current UI. The manual backup nevertheless **inherits the un-freeze for free**,
  because it calls the same `createBackup()`. Restore is untouched and keeps its
  synchronous inflate; it can be addressed separately.
- Any change to the backup archive format, the retention policy, or the
  once-per-day scheduling.
- A percentage. See "Why no percentage" below.

## Decisions

| Question | Decision |
| --- | --- |
| Block the UI during backup? | No. The backup is fully non-blocking. |
| How visible? | Discreet card, bottom-right, auto-dismissing. |
| On failure? | Persistent error card, dismissed by the user. |
| Scope of progress UI | Automatic backup only. |
| Risk posture | **Conservative.** Compression logic is moved, never rewritten. |

Working during a backup is safe: `VACUUM INTO` produces a transactionally
consistent snapshot while writers continue, and the compression phase works on
that snapshot file — the live database is not touched at all during compression.

## Architecture

The guiding constraint is the risk posture: **not one byte of the compression
logic changes.** The archive-writing code is relocated into a background
isolate verbatim, and progress is derived by observing the filesystem from the
outside. Nothing in the code path that determines archive contents, CRCs, or
zip structure is touched, so the produced archives are bit-for-bit what they are
today.

### 1. The archive writer moves to a background isolate, unchanged

New file `lib/services/backup/backup_archive_worker.dart` — pure Dart,
top-level functions, depending only on `dart:io` and `archive`. No Flutter, no
Riverpod, no sqflite, no GetIt. This keeps
`test/architecture/import_boundaries_test.dart` green and makes the worker
usable under `flutter test`.

The block currently spanning `database_backup_service.dart:213-229` — the
`OutputFileStream` / `ZipEncoder.startEncode` / per-entry
`_addFileToZipStreamed` loop / `endEncode` / `close` sequence — moves into the
worker together with `_addFileToZipStreamed` itself, **with its body
unmodified**: `Deflate.buffer(...)` + `finish()` stay exactly as they are.

`createBackup()` then calls:

```dart
await Isolate.run(() => writeBackupArchive(tempZipPath, sources, workDirPath));
```

`sources` is a `List<(String, String)>` of plain strings and the paths are
strings, so every capture is trivially sendable. `Isolate.run` rethrows a worker
exception in the caller, so the existing `try/catch/finally` in `createBackup`
keeps working unchanged, including its temp-file cleanup and its
`zipOutput.closeSync()` guard — which becomes the worker's responsibility for
the stream it now owns.

What stays on the main isolate: parent-directory creation, the database-exists
check, `workDir` creation, `VACUUM INTO`, the rename over the final name, the
size log, and all cleanup.

### 2. Progress by filesystem observation

No `SendPort`, no cross-isolate messaging. `createBackup` runs a
`Timer.periodic` (500 ms) on the main isolate that stats the temporary files the
worker is writing and reports the byte count through `onProgress`:

| Phase | Polled path(s) |
| --- | --- |
| `snapshot` | the `VACUUM INTO` target in `workDir` |
| `compressing` | `entry-*.deflate` in `workDir`, plus `$destinationPath.tmp` |

The compression phase polls the per-entry deflate temp files rather than the zip
itself, because `ZipEncoder.addFile` only appends an entry *after* its deflate
has fully completed — the zip would sit near zero for the entire compression and
then jump. The `.deflate` files grow continuously, so they are the signal that
actually moves.

Every poll is wrapped in `try/catch` and falls back to the last known value.
Stat-ing a file another isolate holds open can throw on Windows; a failed poll
must degrade the display, never the backup. The timer is cancelled in
`createBackup`'s `finally` block, on every path.

This approach is read-only and entirely outside the backup's own code path: it
cannot corrupt an archive, because it cannot influence one.

### 3. Why no percentage

Neither phase can produce an honest fraction:

- `VACUUM INTO` exposes no progress hook, and it defragments — the snapshot ends
  up *smaller* than the source database. A fraction against the source size
  would climb, hit 100%, and stall.
- Compression progress is only observable as *compressed bytes written*, whose
  total is unknown until the archive is finished (~362 MB from 1.78 GB here, but
  the ratio drifts with content).

Estimating a denominator from the previous backup's size was considered and
rejected: it produces a bar that can reach 100% and freeze, or finish at 80%,
which is precisely the "is it stuck?" impression this work exists to remove.

The card therefore shows an **indeterminate bar plus a live byte counter**. The
counter is what proves the app is alive — the actual goal — and it never lies.

### 4. Progress transport

`createBackup()` gains an **optional** parameter:

```dart
Future<Result<String, BackupException>> createBackup(
  String destinationPath, {
  void Function(BackupProgress)? onProgress,
})
```

`onProgress` is invoked from the polling timer, so it always fires on the
**main isolate**; callers may touch Riverpod state directly from it.

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
}
```

No `bytesTotal`, no `fraction` — per section 3, there is no honest denominator,
and modelling one would invite a caller to render it.

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

These are signature changes;
`test/unit/services/backup/auto_backup_service_test.dart` is updated
accordingly. The best-effort contract is unchanged: a failure is still caught,
logged, and never propagated into startup.

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
| `running(compressing)` | "Compressing… 180 MB written", indeterminate bar |
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
| 1 | **Round-trip**: `createBackup` → `validateBackup` succeeds → `restoreBackup` → data identical | Guards the isolate relocation end to end. |
| 2 | Content fidelity: SHA-256 of every file restored from a worker-built archive equals the source's, for both an incompressible (random) and a highly compressible input of several MB | Literal zip byte-identity is impossible — `ArchiveFile.lastModTime` defaults to `DateTime.now()` (`archive_file.dart:24`), so the header bytes differ every run. Content fidelity is the property that actually matters and it is verifiable. |
| 3 | Zero-byte source (TRUNCATE-checkpointed WAL) | Exercises the legacy multi-entry path, which the single-entry `VACUUM INTO` path does not cover. |
| 4 | Progress callback | Fires with `snapshot` then `compressing`, byte counts non-decreasing, timer cancelled after completion and after failure. |
| 5 | Poll failure tolerated | A stat that throws must leave the backup successful and the last value displayed. |
| 6 | `AutoBackupOutcome` | `skipped` / `created` / `failed` are distinguishable. |
| 7 | Widget test for the card | Each state renders; the error state persists until the close button is tapped. |
| 8 | `test/architecture/import_boundaries_test.dart` | Must stay green — the worker is pure Dart. |

Existing repo test conventions apply (mocktail repos, `NoopLogger`, real temp
directories, theme-token extension for widget tests).

## Risks

Deliberately low, by construction.

- **Isolate relocation** is the only behavioural change to the backup path.
  Mitigated by tests 1-3. Because the compression code moves verbatim, identical
  archive content is guaranteed by construction; the tests are there to catch a
  botched relocation (a stream closed on the wrong side, an entry dropped), not
  a compression regression.
- **Windows file locking during polling**: stat-ing a file the worker holds open
  may throw. Contained by the `try/catch` fallback (test 5); a poll failure
  degrades the counter, never the backup.
- **Isolate memory**: the worker holds the same stream buffers the current code
  does. Peak memory is unchanged, matching the existing streaming design.

Explicitly *not* taken: rewriting `Deflate.buffer(...).finish()` into a chunked
`addBytes` loop. That would have yielded an exact percentage, but it changes the
code that determines archive bytes and CRCs, and a mistake there produces
archives that fail to restore — the one failure mode a backup feature must never
have.

## Out of scope, noted

A zero-byte `TWMT_Backup_2026-07-25_184028.zip.tmp` was found in the user's
`backups` directory — the residue of a manual backup whose process was killed
before `createBackup`'s `finally` cleanup ran. Harmless; not addressed here.
