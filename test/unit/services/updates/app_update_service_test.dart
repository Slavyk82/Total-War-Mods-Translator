// path_provider_platform_interface is a transitive dependency of
// path_provider; it is imported here only to stub the temp directory in tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/services/updates/app_update_service.dart';

class _MockHttpClient extends Mock implements http.Client {}

/// Fake path provider that points the temp directory at a test-owned folder.
///
/// Extends (not implements) PathProviderPlatform so the platform-interface
/// token verification passes.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(http.Request('GET', Uri.parse('https://example.com')));
  });

  group('AppUpdateService.downloadInstaller', () {
    late Directory tempDir;
    late _MockHttpClient httpClient;
    late AppUpdateService service;

    const asset = GitHubAsset(
      name: 'TWMT-Setup.exe',
      browserDownloadUrl: 'https://example.com/TWMT-Setup.exe',
      size: 6,
      contentType: 'application/octet-stream',
      downloadCount: 0,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('twmt_update_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      httpClient = _MockHttpClient();
      service = AppUpdateService(httpClient: httpClient);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    String installerPath() => path.join(tempDir.path, 'TWMT', asset.name);

    test('writes the file and returns its path on success', () async {
      Stream<List<int>> body() async* {
        yield [1, 2, 3];
        yield [4, 5, 6];
      }

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          http.ByteStream(body()),
          200,
          contentLength: 6,
        ),
      );

      final progress = <double>[];
      final result = await service.downloadInstaller(
        asset,
        onProgress: progress.add,
      );

      expect(result.isOk, isTrue);
      expect(result.value, installerPath());
      expect(await File(installerPath()).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test(
        'closes the sink and deletes the partial file when the download '
        'stream fails mid-transfer', () async {
      Stream<List<int>> failingBody() async* {
        yield [1, 2, 3];
        throw const SocketException('connection reset');
      }

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          http.ByteStream(failingBody()),
          200,
          contentLength: 6,
        ),
      );

      final result = await service.downloadInstaller(asset);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Download failed'));
      // The partial file must be gone. On Windows, delete fails while a
      // handle is still open, so this also proves the sink was closed.
      expect(await File(installerPath()).exists(), isFalse);
    });

    test('a retry after a failed download succeeds on the same path',
        () async {
      var calls = 0;
      Stream<List<int>> failingBody() async* {
        yield [9, 9];
        throw const SocketException('connection reset');
      }

      Stream<List<int>> goodBody() async* {
        yield [1, 2, 3, 4, 5, 6];
      }

      when(() => httpClient.send(any())).thenAnswer((_) async {
        calls++;
        return http.StreamedResponse(
          http.ByteStream(calls == 1 ? failingBody() : goodBody()),
          200,
          contentLength: 6,
        );
      });

      final first = await service.downloadInstaller(asset);
      expect(first.isErr, isTrue);

      final second = await service.downloadInstaller(asset);
      expect(second.isOk, isTrue);
      expect(await File(installerPath()).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    });

    test('returns Err without writing anything on non-200 status', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), 404),
      );

      final result = await service.downloadInstaller(asset);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('HTTP 404'));
      expect(await File(installerPath()).exists(), isFalse);
    });
  });
}
