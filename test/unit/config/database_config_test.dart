// path_provider_platform_interface is a transitive dependency of
// path_provider; it is imported here only to stub directories in tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:twmt/config/database_config.dart';

/// Fake path provider with separate, test-owned cache and temp directories.
///
/// Extends (not implements) PathProviderPlatform so the platform-interface
/// token verification passes.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.cachePath,
    required this.tempPath,
  });

  final String cachePath;
  final String tempPath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;

  /// Simulates a redirected TMP/TEMP (e.g. TMP=C:\Temp): the temp directory
  /// is NOT under the application cache base, so any code deriving paths
  /// from getTemporaryDirectory().parent would land somewhere arbitrary.
  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseConfig logs/cache directories', () {
    late Directory root;
    late String cacheBase;
    late String redirectedTemp;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('twmt_dbconfig_test_');
      cacheBase = path.join(root.path, 'AppCache');
      redirectedTemp = path.join(root.path, 'RedirectedTemp');
      await Directory(cacheBase).create(recursive: true);
      await Directory(redirectedTemp).create(recursive: true);

      PathProviderPlatform.instance = _FakePathProviderPlatform(
        cachePath: cacheBase,
        tempPath: redirectedTemp,
      );
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('getLogsDirectory uses the application cache base, not temp.parent',
        () async {
      final logsDir = await DatabaseConfig.getLogsDirectory();

      expect(logsDir, path.join(cacheBase, 'logs'));
      expect(await Directory(logsDir).exists(), isTrue);
      // Must not be derived from the (redirected) temp directory.
      expect(path.isWithin(redirectedTemp, logsDir), isFalse);
    });

    test('getCacheDirectory uses the application cache base, not temp.parent',
        () async {
      final cacheDir = await DatabaseConfig.getCacheDirectory();

      expect(cacheDir, path.join(cacheBase, 'cache'));
      expect(await Directory(cacheDir).exists(), isTrue);
      expect(path.isWithin(redirectedTemp, cacheDir), isFalse);
    });
  });
}
