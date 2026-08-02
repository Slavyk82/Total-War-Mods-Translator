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
