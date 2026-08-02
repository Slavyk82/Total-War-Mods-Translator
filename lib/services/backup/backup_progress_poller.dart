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

  /// Bumped by every [start] and [stop]. A [sample] closure captures the
  /// generation active when it was scheduled; if that generation is stale by
  /// the time its `measure()` resolves, the result is discarded outright.
  ///
  /// Without this, a slow `measure()` call from a phase that has already
  /// ended (e.g. `createBackup` calls `poller.stop()` then immediately
  /// `poller.start()` for the next phase, with no `await` in between) can
  /// resolve *after* the switch and deliver a stale [BackupPhase] — and,
  /// combined with the floor below, permanently pin `_lastValue` at a value
  /// that belongs to a different, unrelated phase.
  int _generation = 0;

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
    final generation = _generation;

    Future<void> sample() async {
      int? measured;
      try {
        measured = await measure();
      } catch (_) {
        // Keep the last known value. Stat-ing a file another isolate holds
        // open can throw on Windows; a poll failure must never affect the
        // backup or the caller.
      }

      // Discard a sample whose generation has already been superseded by a
      // later start()/stop() call. This must happen before touching
      // `_lastValue` or calling `onProgress` — both belong to whichever
      // phase is current, not to the one this sample was measuring.
      if (generation != _generation) return;

      // Clamp to a floor of the last known value rather than assigning
      // outright. The raw measurement is not perfectly monotonic: e.g. the
      // compressing-phase measure sums a zip file plus in-flight `.deflate`
      // scratch files, and there is a brief window, after an entry's bytes
      // have been copied into the zip but before its now-redundant
      // `.deflate` file is deleted, where the two would otherwise be
      // double-counted and then drop back down. [BackupProgress.bytesDone]
      // is documented as monotonically non-decreasing within a phase, so
      // that guarantee is enforced here, once, for every measurement this
      // poller is ever given — instead of requiring each `measure` callback
      // to defend against its own underlying races.
      if (measured != null && measured > _lastValue) _lastValue = measured;
      onProgress(BackupProgress(phase: phase, bytesDone: _lastValue));
    }

    unawaited(sample());
    _timer = Timer.periodic(interval, (_) => unawaited(sample()));
  }

  /// Stop reporting. Safe to call when not started, and repeatedly.
  void stop() {
    _timer?.cancel();
    _timer = null;
    // Invalidate the current generation too: a sample already in flight
    // (mid-`measure()`) when stop() is called must be discarded when it
    // resolves, even if start() is never called again.
    _generation++;
  }
}
