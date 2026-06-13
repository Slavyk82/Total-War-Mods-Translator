import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/process_service.dart';
import 'package:twmt/services/shared/models/process_result.dart' as models;

/// A command guaranteed to exist on the host that prints a line and exits 0.
({String exe, List<String> ok, List<String> fail}) _commands() {
  if (Platform.isWindows) {
    return (
      exe: 'cmd',
      ok: ['/c', 'echo', 'hello'],
      fail: ['/c', 'exit', '3'],
    );
  }
  return (
    exe: 'sh',
    ok: ['-c', 'echo hello'],
    fail: ['-c', 'exit 3'],
  );
}

void main() {
  final service = ProcessService.instance;
  final cmd = _commands();

  tearDown(() {
    // Defensive: ensure no leaked active processes between tests.
    service.cancelAll();
  });

  group('run', () {
    test('captures stdout and a zero exit code', () async {
      final result = await service.run(cmd.exe, cmd.ok);

      expect(result, isA<Ok>());
      final pr = result.value;
      expect(pr.exitCode, 0);
      expect(pr.stdout.trim(), 'hello');
      expect(pr.isSuccess, isTrue);
      expect(pr.executionTimeMs, greaterThanOrEqualTo(0));
    });

    test('reports a non-zero exit code without erroring', () async {
      final result = await service.run(cmd.exe, cmd.fail);

      expect(result, isA<Ok>());
      expect(result.value.exitCode, 3);
      expect(result.value.isFailure, isTrue);
    });

    test('returns Err when the executable does not exist', () async {
      final result = await service.run('definitely_not_a_real_exe_zzz', []);

      expect(result, isA<Err>());
      expect(result.error, isA<Exception>());
    });

    test('times out a long-running process', () async {
      final sleeper = Platform.isWindows
          ? (exe: 'cmd', args: ['/c', 'ping', '127.0.0.1', '-n', '5'])
          : (exe: 'sh', args: ['-c', 'sleep 5']);

      final result = await service.run(
        sleeper.exe,
        sleeper.args,
        config: const models.ProcessConfig(
          timeout: Duration(milliseconds: 200),
        ),
      );

      expect(result, isA<Err>());
      expect(result.error.toString(), contains('timeout'));
    });
  });

  group('runWithStreaming', () {
    test('streams progress lines and collects output', () async {
      final progresses = <models.ProcessProgress>[];

      final result = await service.runWithStreaming(
        cmd.exe,
        cmd.ok,
        onProgress: progresses.add,
      );

      expect(result, isA<Ok>());
      expect(result.value.stdout.trim(), 'hello');
      expect(progresses, isNotEmpty);
      expect(progresses.first.currentLine, isNotNull);
      expect(progresses.any((p) => !p.isError), isTrue);
    });

    test('returns Err for a missing executable', () async {
      final result =
          await service.runWithStreaming('missing_exe_zzz', const []);

      expect(result, isA<Err>());
    });
  });

  group('startStreaming', () {
    test('returns a live process and tracks it as active', () async {
      final sleeper = Platform.isWindows
          ? (exe: 'cmd', args: ['/c', 'ping', '127.0.0.1', '-n', '10'])
          : (exe: 'sh', args: ['-c', 'sleep 10']);

      final result = await service.startStreaming(sleeper.exe, sleeper.args);

      expect(result, isA<Ok>());
      final process = result.value;
      expect(service.isProcessActive(process.pid), isTrue);
      expect(service.activeProcessIds, contains(process.pid));

      // Kill while alive so the tracking map drops it (kill returns true).
      service.cancel(process.pid);
      expect(service.isProcessActive(process.pid), isFalse);
      await process.exitCode;
    });

    test('returns Err for a missing executable', () async {
      final result = await service.startStreaming('missing_exe_zzz', const []);

      expect(result, isA<Err>());
    });
  });

  group('cancel / cancelAll', () {
    test('cancel returns false for an unknown pid', () {
      expect(service.cancel(-999999), isFalse);
    });

    test('cancel kills a tracked process', () async {
      final sleeper = Platform.isWindows
          ? (exe: 'cmd', args: ['/c', 'ping', '127.0.0.1', '-n', '10'])
          : (exe: 'sh', args: ['-c', 'sleep 10']);

      final started = await service.startStreaming(sleeper.exe, sleeper.args);
      final process = started.value;

      final killed = service.cancel(process.pid);

      expect(killed, isTrue);
      expect(service.isProcessActive(process.pid), isFalse);
      await process.exitCode;
    });

    test('cancelAll kills every tracked process', () async {
      final sleeper = Platform.isWindows
          ? (exe: 'cmd', args: ['/c', 'ping', '127.0.0.1', '-n', '10'])
          : (exe: 'sh', args: ['-c', 'sleep 10']);

      final a = await service.startStreaming(sleeper.exe, sleeper.args);
      final b = await service.startStreaming(sleeper.exe, sleeper.args);

      final count = service.cancelAll();

      expect(count, greaterThanOrEqualTo(2));
      expect(service.isProcessActive(a.value.pid), isFalse);
      expect(service.isProcessActive(b.value.pid), isFalse);
      await a.value.exitCode;
      await b.value.exitCode;
    });
  });

  group('runSimple', () {
    test('returns trimmed stdout for a successful command', () async {
      final out = await service.runSimple(cmd.exe, cmd.ok);

      expect(out, 'hello');
    });

    test('throws when the exit code is non-zero', () async {
      expect(
        () => service.runSimple(cmd.exe, cmd.fail),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the executable is missing', () async {
      expect(
        () => service.runSimple('missing_exe_zzz', const []),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('isExecutableAvailable', () {
    test('is false for a non-existent executable', () async {
      expect(await service.isExecutableAvailable('missing_exe_zzz'), isFalse);
    });
  });

  group('active process accessors', () {
    test('isProcessActive is false for an untracked pid', () {
      expect(service.isProcessActive(1234567), isFalse);
      expect(service.activeProcessCount, greaterThanOrEqualTo(0));
      expect(service.activeProcessIds, isA<List<int>>());
    });
  });

  test('dispose cancels everything without throwing', () async {
    await service.dispose();
  });
}
