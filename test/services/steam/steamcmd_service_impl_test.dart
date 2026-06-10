import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/steamcmd_service_impl.dart';

import '../../helpers/fakes/fake_logger.dart';

// Regression tests for SteamCmdServiceImpl download cancellation.
//
// `_isCancelled` is an instance-level flag on a singleton service. cancel()
// sets it unconditionally, but it used to be reset only in downloadMod's
// `finally`. A cancel() issued while NO download was in flight (e.g. the user
// cancels during the post-download analysis phases of a mod update) left the
// flag stale, so the NEXT downloadMod ran the full download and then falsely
// discarded it with 'Download cancelled by user'. The flag must be scoped to
// the current operation by resetting it at the start of each downloadMod.

class _MockSteamCmdManager extends Mock implements SteamCmdManager {}

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
}
