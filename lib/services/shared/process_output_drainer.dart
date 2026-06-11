import 'dart:async';
import 'dart:convert';

/// Drains a process's stdout/stderr to completion so output buffers can be
/// read safely after the process exits.
///
/// `Process.exitCode` completing only means the OS process ended — the Dart
/// pipes may still hold buffered, undelivered data. Reading accumulated
/// output without draining the streams first can silently truncate it
/// (losing error messages, warnings, or the final success line). This helper
/// centralizes the drain idiom previously copy-pasted across
/// [ProcessService], `SteamCmdServiceImpl` and `WorkshopPublishServiceImpl`:
///
/// - subscribes to both streams with the given [encoding],
/// - invokes optional per-chunk callbacks (raw decoded data, in arrival
///   order) and per-line callbacks (complete lines, reassembled across
///   chunk boundaries, `\r\n`/`\r`/`\n` all accepted as line breaks),
/// - flushes a trailing partial line (no final newline) to the line
///   callback when the stream ends,
/// - completes the drain on stream ERROR as well as on done — a stream
///   error must not stall the caller until the grace timeout,
/// - exposes [awaitDrained] to await after `exitCode`, bounded by a grace
///   period: a surviving child process that inherited the pipe can keep it
///   open forever, so after the grace period we proceed with whatever was
///   buffered rather than hang the caller.
///
/// Timeout semantics for the process itself (TimeoutException vs sentinel
/// exit codes) deliberately stay at the call sites — this class only owns
/// stream draining.
class ProcessOutputDrainer {
  ProcessOutputDrainer({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    Encoding encoding = latin1,
    void Function(String chunk)? onStdoutChunk,
    void Function(String chunk)? onStderrChunk,
    void Function(String line)? onStdoutLine,
    void Function(String line)? onStderrLine,
  }) {
    _stdoutSub =
        _subscribe(stdout, encoding, onStdoutChunk, onStdoutLine, _stdoutDone);
    _stderrSub =
        _subscribe(stderr, encoding, onStderrChunk, onStderrLine, _stderrDone);
  }

  /// Matches any single line break. Used with [String.split], which keeps
  /// empty segments — so blank lines are preserved (LineSplitter parity).
  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');

  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();

  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;

  StreamSubscription<String> _subscribe(
    Stream<List<int>> stream,
    Encoding encoding,
    void Function(String chunk)? onChunk,
    void Function(String line)? onLine,
    Completer<void> done,
  ) {
    // Holds the trailing partial line until its line break (or the end of
    // the stream) arrives.
    var buffer = '';

    void emitCompleteLines(String chunk) {
      if (onLine == null) return;
      buffer += chunk;
      // Hold back a trailing '\r': it may be the first half of a '\r\n'
      // pair split across two chunks; splitting now would emit the line and
      // then surface a spurious empty line when the '\n' arrives.
      var heldBack = '';
      if (buffer.endsWith('\r')) {
        heldBack = '\r';
        buffer = buffer.substring(0, buffer.length - 1);
      }
      final segments = buffer.split(_lineBreak);
      buffer = segments.removeLast() + heldBack;
      segments.forEach(onLine);
    }

    void flushPartialLine() {
      if (onLine == null || buffer.isEmpty) return;
      // The buffer may end with a held-back '\r' (a complete line) or be a
      // genuine partial line with no terminator — split handles both.
      final segments = buffer.split(_lineBreak);
      buffer = '';
      final last = segments.removeLast();
      segments.forEach(onLine);
      if (last.isNotEmpty) onLine(last);
    }

    void complete() {
      flushPartialLine();
      if (!done.isCompleted) done.complete();
    }

    return stream.transform(encoding.decoder).listen(
      (chunk) {
        onChunk?.call(chunk);
        emitCompleteLines(chunk);
      },
      onDone: complete,
      // Complete the drain on stream error too: without this the caller
      // would stall on awaitDrained until the grace timeout every time a
      // pipe breaks. Whatever data arrived before the error is still
      // flushed.
      onError: (Object _) => complete(),
    );
  }

  /// Waits until both streams are fully drained (done or error), bounded by
  /// [grace]. Call after `Process.exitCode` completes and before reading
  /// any buffers fed by the callbacks.
  Future<void> awaitDrained({Duration grace = const Duration(seconds: 5)}) {
    return Future.wait([_stdoutDone.future, _stderrDone.future])
        .timeout(grace, onTimeout: () => const [])
        .then((_) {});
  }

  /// Cancels both stream subscriptions. Safe to call multiple times.
  Future<void> cancel() async {
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
  }
}
