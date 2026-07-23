// path_provider_platform_interface is a transitive dependency of
// path_provider; it is imported here only to stub the temp directory in tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
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
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('AppUpdateService.checkForUpdate version comparison', () {
    late _MockHttpClient httpClient;
    late AppUpdateService service;

    setUp(() {
      httpClient = _MockHttpClient();
      service = AppUpdateService(httpClient: httpClient);
    });

    void stubLatestRelease(String tagName) {
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': tagName,
            'name': tagName,
            'body': '',
            'draft': false,
            'prerelease': false,
            'published_at': '2026-06-01T00:00:00Z',
            'html_url': 'https://example.com/release',
            'assets': <dynamic>[],
          }),
          200,
        ),
      );
    }

    test('offers v2.0.6-hotfix as an update over 2.0.5', () async {
      stubLatestRelease('v2.0.6-hotfix');

      final result = await service.checkForUpdate('2.0.5');

      expect(result.isOk, isTrue);
      expect(result.value, isNotNull,
          reason: '2.0.6-hotfix has a newer numeric core than 2.0.5');
    });

    test('does not offer v2.0.5-rc1 as an update over 2.0.5', () async {
      stubLatestRelease('v2.0.5-rc1');

      final result = await service.checkForUpdate('2.0.5');

      expect(result.isOk, isTrue);
      expect(result.value, isNull,
          reason: 'a pre-release of the same numeric core is not newer');
    });

    test('offers v2.1.0-rc1 as an update over 2.0.9', () async {
      stubLatestRelease('v2.1.0-rc1');

      final result = await service.checkForUpdate('2.0.9');

      expect(result.isOk, isTrue);
      expect(result.value, isNotNull);
    });

    test('does not offer v2.0.5 as an update over 2.0.5', () async {
      stubLatestRelease('v2.0.5');

      final result = await service.checkForUpdate('2.0.5');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    test('offers v2.0.6 as an update over 2.0.5+10 (build metadata stripped)',
        () async {
      stubLatestRelease('v2.0.6');

      final result = await service.checkForUpdate('2.0.5+10');

      expect(result.isOk, isTrue);
      expect(result.value, isNotNull);
    });

    test('does not offer v2.0.4 as an update over 2.0.5', () async {
      stubLatestRelease('v2.0.4');

      final result = await service.checkForUpdate('2.0.5');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('AppUpdateService request timeout', () {
    test(
        'getLatestRelease resolves to an error instead of hanging when the '
        'server accepts the connection but never responds', () async {
      final httpClient = _MockHttpClient();
      // Half-open connection: the request Future never completes.
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) => Completer<http.Response>().future);

      final service = AppUpdateService(
        httpClient: httpClient,
        requestTimeout: const Duration(milliseconds: 50),
      );

      final result = await service.getLatestRelease();

      expect(result.isErr, isTrue,
          reason: 'a stalled GitHub connection must resolve to an error so the '
              'awaited startup chain (release-notes -> auto-backup) cannot hang');
      expect(result.error.message.toLowerCase(), contains('tim'),
          reason: 'the failure should be reported as a timeout');
    }, timeout: const Timeout(Duration(seconds: 5)));
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
