import 'dart:io';

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
    // Positive precondition first: prove events were actually flowing before
    // `stop()`. Without this, a poller that emits nothing at all would pass
    // the negative assertion below unchanged.
    expect(events, isNotEmpty);
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

  test('floors bytesDone so a decreasing raw measurement never regresses',
      () async {
    // Deterministic counterpart to the filesystem-driven
    // "byte counts never decrease" test in
    // database_backup_service_progress_test.dart, which only reproduces the
    // underlying race about a quarter of the time. This pins the flooring
    // behaviour directly: no filesystem, no timing race, `measure` just
    // hands back a controlled decreasing-then-increasing sequence.
    final events = <BackupProgress>[];
    const sequence = [100, 50, 200];
    var index = 0;
    final poller = BackupProgressPoller(
      interval: const Duration(milliseconds: 5),
    );
    addTearDown(poller.stop);

    poller.start(
      phase: BackupPhase.compressing,
      measure: () async {
        final value = sequence[index < sequence.length ? index : sequence.length - 1];
        if (index < sequence.length) index++;
        return value;
      },
      onProgress: events.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    poller.stop();

    expect(events.length, greaterThanOrEqualTo(3));
    expect(events.first.bytesDone, 100);
    // The raw sequence dips to 50 right after the first sample; that dip
    // must never reach the caller.
    expect(events.any((e) => e.bytesDone == 50), isFalse);
    for (var i = 1; i < events.length; i++) {
      expect(events[i].bytesDone, greaterThanOrEqualTo(events[i - 1].bytesDone));
    }
    expect(events.last.bytesDone, 200);
  });

  test(
      'a sample in flight when the phase changes does not contaminate the '
      'new phase', () async {
    // Reproduces the exact createBackup shape: poller.stop() (or a bare
    // start(), which calls stop() itself) followed immediately by
    // poller.start() for the next phase, with no `await` in between. A
    // measure() from the OLD phase that is still awaiting when that happens
    // must never be allowed to write `_lastValue` or call `onProgress` under
    // the NEW phase — the old phase's sample belongs to a dead generation by
    // the time it resolves.
    final events = <BackupProgress>[];
    final poller = BackupProgressPoller(
      interval: const Duration(milliseconds: 5),
    );
    addTearDown(poller.stop);

    // Snapshot phase: its one measurement resolves slowly, well after the
    // phase has already moved on.
    poller.start(
      phase: BackupPhase.snapshot,
      measure: () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 1000;
      },
      onProgress: events.add,
    );

    // Switch to compressing immediately — no await — exactly like
    // createBackup's poller.stop() followed by poller.start().
    poller.start(
      phase: BackupPhase.compressing,
      measure: () async => 10,
      onProgress: events.add,
    );

    // Outlive both several compressing ticks and the delayed snapshot
    // measurement.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    poller.stop();

    expect(
      events.any((e) => e.phase == BackupPhase.snapshot),
      isFalse,
      reason: 'the stale in-flight snapshot sample must be discarded, not '
          'delivered after the phase changed',
    );
    final compressingValues = events
        .where((e) => e.phase == BackupPhase.compressing)
        .map((e) => e.bytesDone)
        .toList();
    expect(compressingValues, isNotEmpty);
    expect(
      compressingValues.every((v) => v == 10),
      isTrue,
      reason: 'the discarded stale value (1000) must not floor the new '
          'phase, whose real measurements are all 10',
    );
  });
}
