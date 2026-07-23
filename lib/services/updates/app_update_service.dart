import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../models/domain/github_release.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';

/// Service for checking and downloading application updates from GitHub.
class AppUpdateService {
  static const String _owner = 'Slavyk82';
  static const String _repo = 'Total-War-Mods-Translator';
  static const String _apiBaseUrl = 'https://api.github.com';

  final http.Client _httpClient;

  /// Per-request deadline for every GitHub HTTP call. package:http applies no
  /// default request timeout, so without this a connection that is accepted
  /// but never answered (captive portal, transparent proxy, half-open socket)
  /// leaves the Future pending forever — which at startup hangs the awaited
  /// release-notes check and silently skips the daily database backup.
  final Duration _requestTimeout;

  AppUpdateService({
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout;

  /// Get the latest release from GitHub.
  Future<Result<GitHubRelease, ServiceException>> getLatestRelease() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$_apiBaseUrl/repos/$_owner/$_repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'TWMT-App',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Ok(GitHubRelease.fromJson(json));
      } else if (response.statusCode == 404) {
        return Err(const ServiceException('No releases found'));
      } else {
        return Err(ServiceException(
          'Failed to fetch release: HTTP ${response.statusCode}',
        ));
      }
    } on TimeoutException {
      return Err(ServiceException(
        'Request timed out after ${_requestTimeout.inSeconds}s',
      ));
    } catch (e) {
      return Err(ServiceException('Network error: $e'));
    }
  }

  /// Get all releases from GitHub.
  Future<Result<List<GitHubRelease>, ServiceException>> getAllReleases() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$_apiBaseUrl/repos/$_owner/$_repo/releases'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'TWMT-App',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final jsonList = jsonDecode(response.body) as List<dynamic>;
        final releases = jsonList
            .map((e) => GitHubRelease.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(releases);
      } else {
        return Err(ServiceException(
          'Failed to fetch releases: HTTP ${response.statusCode}',
        ));
      }
    } on TimeoutException {
      return Err(ServiceException(
        'Request timed out after ${_requestTimeout.inSeconds}s',
      ));
    } catch (e) {
      return Err(ServiceException('Network error: $e'));
    }
  }

  /// Check if an update is available.
  ///
  /// Returns the new release if available, null otherwise.
  Future<Result<GitHubRelease?, ServiceException>> checkForUpdate(
    String currentVersion,
  ) async {
    final result = await getLatestRelease();

    return result.when(
      ok: (release) {
        if (release.isDraft || release.isPrerelease) {
          return const Ok(null);
        }

        final latestVersion = release.version;
        if (_isNewerVersion(latestVersion, currentVersion)) {
          return Ok(release);
        }
        return const Ok(null);
      },
      err: (error) => Err(error),
    );
  }

  /// Compare two semantic versions.
  ///
  /// Returns true if [newVersion] is newer than [currentVersion].
  ///
  /// Comparison uses the numeric core only: build metadata ("+build") and
  /// pre-release/suffix segments ("-rc1", "-hotfix") are stripped before the
  /// dot-split, so "2.0.6-hotfix" compares as 2.0.6. A pre-release of the
  /// SAME numeric core (e.g. "2.0.5-rc1" vs "2.0.5") is deliberately NOT
  /// considered newer — equal cores compare as not newer, the safe default.
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      // Reduce to the numeric core: drop "+build" metadata and "-suffix"
      // pre-release segments (e.g. "2.0.6-hotfix+1" -> "2.0.6").
      String numericCore(String version) =>
          version.split('+').first.split('-').first;

      final newParts = numericCore(newVersion).split('.');
      final currentParts = numericCore(currentVersion).split('.');

      for (var i = 0; i < 3; i++) {
        final newPart = i < newParts.length ? int.tryParse(newParts[i]) ?? 0 : 0;
        final currentPart =
            i < currentParts.length ? int.tryParse(currentParts[i]) ?? 0 : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Download the installer to a temporary location.
  ///
  /// Returns the path to the downloaded file.
  Future<Result<String, ServiceException>> downloadInstaller(
    GitHubAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    if (asset.isEmpty) {
      return Err(const ServiceException('No installer asset available'));
    }

    try {
      final request = http.Request('GET', Uri.parse(asset.browserDownloadUrl));
      request.headers['User-Agent'] = 'TWMT-App';

      final response = await _httpClient.send(request).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return Err(ServiceException(
          'Failed to download: HTTP ${response.statusCode}',
        ));
      }

      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(tempDir.path, 'TWMT', asset.name);

      // Create directory if needed
      await Directory(path.dirname(filePath)).create(recursive: true);

      // Download with progress
      final file = File(filePath);
      final sink = file.openWrite();

      final totalBytes = response.contentLength ?? asset.size;
      var downloadedBytes = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          if (onProgress != null && totalBytes > 0) {
            onProgress(downloadedBytes / totalBytes);
          }
        }

        await sink.close();
      } catch (e) {
        // Close the sink on failure so the OS file handle is released.
        try {
          await sink.close();
        } catch (_) {
          // Ignore close errors; the original failure is reported below.
        }
        // Remove the partial installer so a stale file is never launched.
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Best effort: leftovers are removed by cleanupOldInstallers().
        }
        rethrow;
      }

      return Ok(filePath);
    } on TimeoutException {
      return Err(ServiceException(
        'Download timed out after ${_requestTimeout.inSeconds}s',
      ));
    } catch (e) {
      return Err(ServiceException('Download failed: $e'));
    }
  }

  /// Launch the downloaded installer and exit the app.
  Future<Result<void, ServiceException>> launchInstaller(
    String installerPath,
  ) async {
    try {
      final file = File(installerPath);
      if (!await file.exists()) {
        return Err(const ServiceException('Installer file not found'));
      }

      final extension = path.extension(installerPath).toLowerCase();

      // Handle different installer types
      if (extension == '.zip') {
        // For zip files, open the containing folder
        final directory = path.dirname(installerPath);
        await Process.start(
          'explorer.exe',
          [directory],
          mode: ProcessStartMode.detached,
        );
      } else {
        // For .exe, .msi, .msix - launch directly
        await Process.start(
          installerPath,
          [],
          mode: ProcessStartMode.detached,
        );
      }

      return const Ok(null);
    } catch (e) {
      return Err(ServiceException('Failed to launch installer: $e'));
    }
  }

  /// Clean up old installer files from the temp directory.
  ///
  /// Removes files older than [maxAge] (default: 7 days).
  Future<void> cleanupOldInstallers({Duration? maxAge}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final twmtTempDir = Directory(path.join(tempDir.path, 'TWMT'));

      if (!await twmtTempDir.exists()) {
        return;
      }

      final cutoffDate = DateTime.now().subtract(maxAge ?? const Duration(days: 7));

      await for (final entity in twmtTempDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            try {
              await entity.delete();
            } catch (_) {
              // Ignore errors deleting individual files
            }
          }
        }
      }
    } catch (_) {
      // Silently ignore cleanup errors
    }
  }

  /// Get the temp directory path for installers.
  Future<String> getInstallerTempPath() async {
    final tempDir = await getTemporaryDirectory();
    return path.join(tempDir.path, 'TWMT');
  }

  void dispose() {
    _httpClient.close();
  }
}
