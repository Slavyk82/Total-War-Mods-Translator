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
        final measured = await measure();
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
        if (measured > _lastValue) _lastValue = measured;
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
