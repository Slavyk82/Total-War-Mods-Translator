import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/i_process_launcher.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/steamcmd_service_impl.dart';

import '../../helpers/fakes/fake_logger.dart';
import '../../helpers/fakes/fake_process.dart';

// Regression tests for SteamCmdServiceImpl download cancellation and
// output handling.
//
// 1. `_isCancelled` is an instance-level flag on a singleton service. cancel()
// sets it unconditionally, but it used to be reset only in downloadMod's
// `finally`. A cancel() issued while NO download was in flight (e.g. the user
// cancels during the post-download analysis phases of a mod update) left the
// flag stale, so the NEXT downloadMod ran the full download and then falsely
// discarded it with 'Download cancelled by user'. The flag must be scoped to
// the current operation by resetting it at the start of each downloadMod.
//
// 2. cancel() kills the running process; on Windows Process.kill surfaces
// exit code -1 — the same sentinel the 10-minute timeout handler returns.
// The cancellation check must run BEFORE the exitCode == -1 timeout mapping,
// otherwise a deliberate user cancel is reported as 'Download timed out'.
//
// 3. The process can exit while stdout/stderr events are still queued, so
// the buffers must be drained (stream onDone) before being read — otherwise
// the parsed error message and collected warnings can be truncated or lost.

class _MockSteamCmdManager extends Mock implements SteamCmdManager {}

class _MockProcessLauncher extends Mock implements IProcessLauncher {}

/// Fake process that stays "running" until [kill] is invoked, then surfaces
/// exit code -1 — mirroring Windows TerminateProcess(handle, -1), which is
/// what a real `Process.kill()` produces for a cancelled steamcmd download.
class _KillableFakeProcess extends FakeProcess {
  _KillableFakeProcess(Completer<int> exitCompleter)
      : _exitCompleter = exitCompleter,
        super(
          pid: 4243,
          exitCodeFuture: exitCompleter.future,
          stdoutStream: const Stream<List<int>>.empty(),
          stderrStream: const Stream<List<int>>.empty(),
        );

  final Completer<int> _exitCompleter;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(-1);
    }
    return true;
  }
}

void main() {
  const workshopId = '123456789';
  const appId = 1142710;

  late _MockSteamCmdManager manager;
  late SteamCmdServiceImpl service;
  late Directory outputDir;

  // A real executable that exits quickly no matter which SteamCMD arguments
  // it receives. where.exe treats each argument as a file pattern, finds
  // nothing and exits with code 1 — which downloadMod maps to
  // WorkshopDownloadException, clearly distinct from DOWNLOAD_CANCELLED.
  final fakeSteamCmdExe = p.join(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    'System32',
    'where.exe',
  );

  setUp(() async {
    manager = _MockSteamCmdManager();
    outputDir = await Directory.systemTemp.createTemp('twmt_steamcmd_test');

    when(() => manager.getSteamCmdPath())
        .thenAnswer((_) async => Ok(fakeSteamCmdExe));
    when(() => manager.initialize()).thenAnswer((_) async => const Ok(null));

    service = SteamCmdServiceImpl(logger: FakeLogger(), manager: manager);
  });

  tearDown(() async {
    service.dispose();
    await outputDir.delete(recursive: true);
  });

  group('SteamCmdServiceImpl cancellation scoping', () {
    test(
        'downloadMod after a cancel() issued with no download in flight '
        'proceeds instead of falsely reporting DOWNLOAD_CANCELLED', () async {
      // User cancels while nothing is downloading (e.g. during the
      // post-download detectingChanges/updatingDatabase phases of a mod
      // update): the flag is set with no in-flight download to consume it.
      await service.cancel();

      // The next (retried) download must run normally. The fake executable
      // makes it fail with WorkshopDownloadException — what matters is that
      // the result reflects the actual run, not the stale cancellation.
      final result = await service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );

      expect(result.isErr, isTrue,
          reason: 'the fake steamcmd executable cannot really download');
      final error = result.unwrapErr();
      expect(error.code, isNot('DOWNLOAD_CANCELLED'),
          reason: 'a stale cancel from a previous operation must not be '
              'applied to a new download');
      expect(error, isA<WorkshopDownloadException>(),
          reason: 'the download must run to its real outcome (non-zero exit '
              'from the fake executable)');
    });

    test('every new downloadMod starts with a fresh cancellation scope',
        () async {
      // Two stale cancels in a row: each subsequent download must still run.
      await service.cancel();

      final first = await service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );
      expect(first.unwrapErr().code, isNot('DOWNLOAD_CANCELLED'));

      await service.cancel();

      final second = await service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );
      expect(second.unwrapErr().code, isNot('DOWNLOAD_CANCELLED'));
    });
  });

  group('SteamCmdServiceImpl cancel vs timeout (exit code -1)', () {
    setUpAll(() {
      registerFallbackValue(<String>[]);
    });

    late _MockProcessLauncher launcher;

    setUp(() {
      launcher = _MockProcessLauncher();
      service.dispose();
      service = SteamCmdServiceImpl(
        logger: FakeLogger(),
        manager: manager,
        processLauncher: launcher,
      );
    });

    test(
        'cancel() during a download reports DOWNLOAD_CANCELLED, not the '
        '10-minute timeout, even though the kill surfaces exit code -1',
        () async {
      final exitCompleter = Completer<int>();
      final process = _KillableFakeProcess(exitCompleter);
      final processStarted = Completer<void>();

      when(() => launcher.start(any(), any(),
          runInShell: any(named: 'runInShell'))).thenAnswer((_) async {
        processStarted.complete();
        return process;
      });

      final pending = service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );

      await processStarted.future;
      // Let downloadMod's `_currentProcess = await launcher.start(...)`
      // assignment land before cancelling, so cancel() kills the process.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.cancel();

      final result = await pending;
      expect(result.isErr, isTrue);
      final error = result.unwrapErr();
      expect(error, isNot(isA<SteamCmdTimeoutException>()),
          reason: 'a user cancel must not be reported as a download timeout '
              'just because the killed process exits with the -1 sentinel');
      expect(error.code, 'DOWNLOAD_CANCELLED');
    });
  });

  group('SteamCmdServiceImpl output draining', () {
    setUpAll(() {
      registerFallbackValue(<String>[]);
    });

    late _MockProcessLauncher launcher;

    setUp(() {
      launcher = _MockProcessLauncher();
      service.dispose();
      service = SteamCmdServiceImpl(
        logger: FakeLogger(),
        manager: manager,
        processLauncher: launcher,
      );
    });

    test(
        'stderr delivered after the process exit code resolves is still '
        'parsed into the error message (not "Unknown error")', () async {
      final stderrController = StreamController<List<int>>();
      final process = FakeProcess(
        pid: 4244,
        // Exit code resolves immediately — before any stderr is delivered.
        exitCodeFuture: Future<int>.value(1),
        stdoutStream: const Stream<List<int>>.empty(),
        stderrStream: stderrController.stream,
      );

      when(() => launcher.start(any(), any(),
          runInShell: any(named: 'runInShell'))).thenAnswer((_) async {
        // Model the real race: data events are still queued when exitCode
        // completes. Without draining the streams the buffer is read empty.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () {
          stderrController
              .add(utf8.encode('ERROR! Connection to Steam servers lost.\n'));
          stderrController.close();
        }));
        return process;
      });

      final result = await service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );

      expect(result.isErr, isTrue);
      final error = result.unwrapErr();
      expect(error, isA<WorkshopDownloadException>());
      expect(error.message, 'ERROR! Connection to Steam servers lost.',
          reason: 'stderr queued after process exit must be drained before '
              'the error message is parsed');
    });

    test(
        'stdout warnings delivered after the process exit code resolves are '
        'still collected on the download result', () async {
      // The success path verifies the mod directory exists.
      final modDir = Directory(p.join(outputDir.path, workshopId))
        ..createSync(recursive: true);
      File(p.join(modDir.path, 'mod.pack')).writeAsStringSync('pack-data');

      final stdoutController = StreamController<List<int>>();
      final process = FakeProcess(
        pid: 4245,
        exitCodeFuture: Future<int>.value(0),
        stdoutStream: stdoutController.stream,
        stderrStream: const Stream<List<int>>.empty(),
      );

      when(() => launcher.start(any(), any(),
          runInShell: any(named: 'runInShell'))).thenAnswer((_) async {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () {
          stdoutController
              .add(utf8.encode('Warning: depot download quota low\n'));
          stdoutController.close();
        }));
        return process;
      });

      final result = await service.downloadMod(
        workshopId: workshopId,
        appId: appId,
        outputDirectory: outputDir.path,
      );

      expect(result.isOk, isTrue);
      final download = result.unwrap();
      expect(download.warnings, isNotNull,
          reason: 'stdout queued after process exit must be drained before '
              'warnings are attached to the result');
      expect(download.warnings, contains('Warning: depot download quota low'));
    });
  });
}
