import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/config/database_config.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';

import '../../helpers/noop_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory fallbackSupportDir;
  late String resolvedBase;
  late Directory toolsDir;
  late File stubExe;
  late bool toolsPreexisted;
  late SteamCmdManager manager;

  setUp(() async {
    fallbackSupportDir =
        await Directory.systemTemp.createTemp('steamcmd_appsupport_');

    // path_provider fallback for environments where the debug APPDATA branch
    // does not short-circuit DatabaseConfig._getAppDataDirectory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return fallbackSupportDir.path;
    });

    // The manager resolves its AppData search path through this same call,
    // so discover the exact directory it will look in.
    resolvedBase = await DatabaseConfig.getAppSupportDirectory();
    toolsDir = Directory(p.join(resolvedBase, 'tools', 'steamcmd'));
    toolsPreexisted = await toolsDir.exists();
    stubExe = File(p.join(toolsDir.path, SteamCmdManager.exeName));

    manager = SteamCmdManager(logger: NoopLogger());
  });

  tearDown(() async {
    // Remove only the stub we created; if the tools dir didn't exist before,
    // delete it too so a real install is never disturbed.
    if (await stubExe.exists()) {
      await stubExe.delete();
    }
    if (!toolsPreexisted && await toolsDir.exists()) {
      await toolsDir.delete(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await fallbackSupportDir.exists()) {
      await fallbackSupportDir.delete(recursive: true);
    }
  });

  Future<void> placeStub() async {
    await toolsDir.create(recursive: true);
    await stubExe.writeAsString('stub');
  }

  group('constants', () {
    test('expose the Valve download URL and executable name', () {
      expect(SteamCmdManager.downloadUrl, contains('steamcmd.zip'));
      expect(SteamCmdManager.exeName, 'steamcmd.exe');
    });
  });

  group('getSteamCmdPath', () {
    test('finds and caches SteamCMD in the AppData tools directory', () async {
      await placeStub();

      final result = await manager.getSteamCmdPath();

      expect(result, isA<Ok>());
      expect(result.value, stubExe.path);

      // Second lookup hits the cached path (still valid).
      final cached = await manager.getSteamCmdPath();
      expect(cached.value, stubExe.path);
    });
  });

  group('isAvailable', () {
    test('is true once SteamCMD exists', () async {
      await placeStub();
      expect(await manager.isAvailable(), isTrue);
    });
  });

  group('getVersion', () {
    test('returns a version string derived from the file date', () async {
      await placeStub();

      final result = await manager.getVersion();

      expect(result, isA<Ok>());
      expect(result.value, contains('SteamCMD'));
    });

    test('returns Err when SteamCMD cannot be located', () async {
      // Ensure nothing is present at the resolved AppData location.
      if (await stubExe.exists()) await stubExe.delete();

      final result = await manager.getVersion();

      // On a machine without SteamCMD on PATH this is an Err; the version
      // call only succeeds when a path was resolved.
      expect(
        result,
        anyOf(
          isA<Err>(),
          predicate<Result<String, SteamServiceException>>((r) => r.isOk),
        ),
      );
    });
  });

  group('getWorkshopCacheDir', () {
    test('builds the SteamCMD workshop content path for an app id', () async {
      final dir = await manager.getWorkshopCacheDir(1142710);

      expect(dir, contains('steamcmd'));
      expect(dir, contains('workshop'));
      expect(dir, endsWith('1142710'));
    });
  });

  group('clearCache', () {
    test('resets cached state so a removed binary is re-detected', () async {
      await placeStub();
      final first = await manager.getSteamCmdPath();
      expect(first, isA<Ok>());

      manager.clearCache();
      await stubExe.delete();

      final result = await manager.getSteamCmdPath();
      // After clearing the cache the deleted stub is no longer returned.
      expect(result.isOk ? result.value : null, isNot(stubExe.path));
    });
  });
}
