import 'dart:async';
import 'dart:io';

import 'package:mocktail/mocktail.dart';

/// Reusable `Process` fake exposing only members read by services under
/// test (`pid`, `exitCode`, `stdout`, `stderr`, `stdin`, `kill`). Real
/// `Process` instantiation is impossible in tests, and a full mocktail
/// mock would need noisy stubs for every no-op call.
///
/// Use [FakeProcess.ok] for happy-path fixtures — or instantiate directly
/// when you need custom exit codes / stream contents.
class FakeProcess extends Fake implements Process {
  FakeProcess({
    required this.pid,
    required Future<int> exitCodeFuture,
    required Stream<List<int>> stdoutStream,
    required Stream<List<int>> stderrStream,
  })  : _exitCode = exitCodeFuture,
        _stdout = stdoutStream,
        _stderr = stderrStream,
        _stdin = _NoopIOSink();

  final Future<int> _exitCode;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final IOSink _stdin;

  @override
  final int pid;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  IOSink get stdin => _stdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

/// Minimal [IOSink] stub — production callers only invoke `close()`.
class _NoopIOSink extends Fake implements IOSink {
  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();
}
