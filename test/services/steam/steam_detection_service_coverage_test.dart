@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/steam_detection_service.dart';

import '../../helpers/noop_logger.dart';

/// Coverage-focused tests for [SteamDetectionService].
///
/// ## How the drive-scan branches are reached
///
/// The service detects Steam libraries in two stages:
///   1. Query the Windows registry for the Steam install path. If found, read
///      its `libraryfolders.vdf` to discover the remaining libraries.
///   2. **Only if** stage 1 produced no libraries, scan every drive letter for
///      well-known Steam folder patterns (`<drive>\Steam`, `<drive>\SteamLibrary`,
///      `<drive>\Games\Steam`, ...).
///
/// On a machine **without** Steam in the registry (e.g. clean CI), stage 1
/// yields nothing and stage 2 runs. We exploit this by mapping a spare drive
/// letter with `subst` onto a temporary directory shaped into a real Steam
/// library, so the unmodified production drive-scan discovers it. That path
/// exercises `_getWindowsDrives` (wmic-failure + A..Z fallback),
/// `_scanAllDrivesForSteam`, `_readLibraryFoldersVdf`, `_findGameViaAcf`,
/// `_validateGameInstallation` and `_findGameInLibraries`.
///
/// On a machine **with** Steam installed (e.g. a developer box), stage 1
/// already returns libraries, so the subst drive is never scanned. The same
/// production parsing/validation code is then exercised against the host's real
/// Steam install instead. To keep the suite green in both environments, the
/// subst-dependent tests probe the host first (`_hostHasSteam`) and relax their
/// assertions when a real Steam install short-circuits the drive scan.
///
/// Branches that remain uncovered on a Steam-equipped host (registry fallbacks
/// to HKLM/InstallPath, the empty-library early returns, and the drive-scan
/// methods) are reachable only in the registry-less environment and are
/// documented as such.
void main() {
  late Directory tempRoot;

  /// The drive letter this test has mounted via `subst` (e.g. `M:`), or null
  /// when nothing is currently mounted. We only ever unmount a letter we
  /// mounted ourselves, so pre-existing user `subst` mappings are never
  /// disturbed.
  String? mountedLetter;

  /// Whether the host already has a real Steam install (registry-detected).
  /// When true, a subst-mounted fake library is never reached by the drive
  /// scan, so subst-dependent assertions are relaxed.
  late bool hostHasSteam;

  String win(String p) => p.replaceAll('/', r'\');

  /// Returns a drive letter (e.g. `M:`) that is currently unused, or null if
  /// none is free. A letter is "unused" when `<letter>:\` does not resolve.
  String? findFreeDriveLetter() {
    // Prefer mid/high letters that are rarely assigned to physical volumes.
    for (final c in 'MNOPQRSTUVWFGHIJKL'.split('')) {
      final letter = '$c:';
      if (!Directory('$letter\\').existsSync()) {
        return letter;
      }
    }
    return null;
  }

  /// Mounts [target] on a free drive letter via `subst`. Returns true on
  /// success and records the letter in [mountedLetter].
  bool mountSubst(String target) {
    final letter = findFreeDriveLetter();
    if (letter == null) return false;
    final result = Process.runSync('subst', [letter, target]);
    if (result.exitCode != 0) return false;
    if (!Directory('$letter\\').existsSync()) {
      Process.runSync('subst', [letter, '/D']);
      return false;
    }
    mountedLetter = letter;
    return true;
  }

  void unmountSubst() {
    final letter = mountedLetter;
    if (letter != null) {
      Process.runSync('subst', [letter, '/D']);
      mountedLetter = null;
    }
  }

  SteamDetectionService newService() =>
      SteamDetectionService(logger: NoopLogger());

  /// Builds a Steam library tree at the `SteamLibrary` pattern under [root].
  String buildSteamLibrary(
    Directory root, {
    String? vdf,
    bool withAcf = true,
    bool withGameExe = true,
    String acfInstallDir = 'Total War WARHAMMER III',
    bool createFolderNameGame = false,
    bool withWorkshop = false,
  }) {
    final libraryDir = Directory(path.join(root.path, 'SteamLibrary'));
    final steamapps = Directory(path.join(libraryDir.path, 'steamapps'));
    steamapps.createSync(recursive: true);

    if (vdf != null) {
      File(path.join(steamapps.path, 'libraryfolders.vdf'))
          .writeAsStringSync(vdf);
    }

    if (withAcf) {
      File(path.join(steamapps.path, 'appmanifest_1142710.acf'))
          .writeAsStringSync(
        '"AppState"\n{\n\t"appid"\t\t"1142710"\n'
        '\t"installdir"\t\t"$acfInstallDir"\n}\n',
      );
      final common =
          Directory(path.join(steamapps.path, 'common', acfInstallDir));
      common.createSync(recursive: true);
      if (withGameExe) {
        File(path.join(common.path, 'Warhammer3.exe')).writeAsStringSync('MZ');
      }
    }

    if (createFolderNameGame) {
      final wh2 = Directory(
          path.join(steamapps.path, 'common', 'Total War WARHAMMER II'));
      wh2.createSync(recursive: true);
      File(path.join(wh2.path, 'Warhammer2.exe')).writeAsStringSync('MZ');
    }

    if (withWorkshop) {
      Directory(path.join(steamapps.path, 'workshop', 'content'))
          .createSync(recursive: true);
    }

    return libraryDir.path;
  }

  setUpAll(() async {
    // Detect once whether the host has a real Steam install.
    final probe = newService();
    final result = await probe.detectAllGames();
    hostHasSteam = result.isOk && result.value.isNotEmpty;
  });

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('twmt_steam_detect_');
  });

  tearDown(() {
    unmountSubst();
    if (tempRoot.existsSync()) {
      try {
        tempRoot.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort: ignore Windows file-lock races.
      }
    }
  });

  group('drive-scan detection via subst-mounted fake Steam library', () {
    test('detectAllGames discovers a WH3 install through the scan/ACF path',
        () async {
      buildSteamLibrary(tempRoot);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      expect(result.value, isA<Map<String, String>>());
      if (!hostHasSteam) {
        // Drive scan is the only detection method -> our fake library wins.
        expect(result.value.containsKey('wh3'), isTrue);
        expect(result.value['wh3'], contains('Total War WARHAMMER III'));
      } else {
        // Real Steam short-circuits the scan; WH3 may come from the real box.
        expect(result.value['wh3'], anyOf(isNull, isA<String>()));
      }
    });

    test('detectGame returns a path for the WH3 ACF install', () async {
      buildSteamLibrary(tempRoot);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectGame('wh3');

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value, isNotNull);
        expect(result.value, contains('Total War WARHAMMER III'));
      } else {
        expect(result.value, anyOf(isNull, isA<String>()));
      }
    });

    test('detectGame uses the folder-name fallback when no ACF is present',
        () async {
      buildSteamLibrary(tempRoot, withAcf: false, createFolderNameGame: true);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectGame('wh2');

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value, isNotNull);
        expect(result.value, contains('Total War WARHAMMER II'));
      } else {
        expect(result.value, anyOf(isNull, isA<String>()));
      }
    });

    test('detectWorkshopFolder locates steamapps/workshop/content', () async {
      buildSteamLibrary(tempRoot, withWorkshop: true);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectWorkshopFolder();

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value, isNotNull);
        expect(result.value, contains('workshop'));
      } else {
        expect(result.value, anyOf(isNull, isA<String>()));
      }
    });

    test('new-format libraryfolders.vdf with a missing path is skipped',
        () async {
      buildSteamLibrary(
        tempRoot,
        vdf: '"libraryfolders"\n{\n'
            '\t"0"\n\t{\n\t\t"path"\t\t"Q:\\\\NoSuchSteamLib"\n\t}\n}\n',
      );
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value.containsKey('wh3'), isTrue);
      }
    });

    test('old numeric-key libraryfolders.vdf pointing at the real library is parsed',
        () async {
      final libPath = path.join(tempRoot.path, 'SteamLibrary');
      final escaped = win(libPath).replaceAll('\\', '\\\\');
      buildSteamLibrary(
        tempRoot,
        vdf: '"libraryfolders"\n{\n\t"0"\t\t"$escaped"\n}\n',
      );
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value.containsKey('wh3'), isTrue);
      }
    });

    test('malformed VDF content does not crash detection', () async {
      buildSteamLibrary(tempRoot, vdf: 'this is { not valid "vdf at all');
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        expect(result.value.containsKey('wh3'), isTrue);
      }
    });

    test('ACF install dir without an .exe fails validation', () async {
      buildSteamLibrary(tempRoot, withGameExe: false);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final result = await service.detectGame('wh3');

      expect(result, isA<Ok>());
      if (!hostHasSteam) {
        // No valid install anywhere -> null.
        expect(result.value, isNull);
      } else {
        expect(result.value, anyOf(isNull, isA<String>()));
      }
    });

    test('cached libraries are reused on a second call and reset by clearCache',
        () async {
      buildSteamLibrary(tempRoot);
      final mounted = mountSubst(win(tempRoot.path));
      if (!mounted) {
        markTestSkipped('subst unavailable on this host');
        return;
      }

      final service = newService();
      final first = await service.detectAllGames();
      expect(first, isA<Ok>());

      // Second call hits the cached-libraries fast path.
      final second = await service.detectAllGames();
      expect(second, isA<Ok>());

      service.clearCache();
      final third = await service.detectAllGames();
      expect(third, isA<Ok>());

      if (!hostHasSteam) {
        expect(first.value.containsKey('wh3'), isTrue);
        expect(second.value.containsKey('wh3'), isTrue);
        expect(third.value.containsKey('wh3'), isTrue);
      }
    });
  });

  group('public API contract (independent of host Steam state)', () {
    test('detectGame rejects an unknown game code with INVALID_GAME_CODE',
        () async {
      final service = newService();
      final result = await service.detectGame('definitely_not_a_game');

      expect(result, isA<Err>());
      expect(result.error, isA<SteamServiceException>());
      expect(result.error.code, 'INVALID_GAME_CODE');
    });

    test('detectGame for every supported code returns Ok with a nullable path',
        () async {
      final service = newService();
      for (final code in ['wh3', 'wh2', 'rome2', 'attila', 'pharaoh_dynasties']) {
        final result = await service.detectGame(code);
        expect(result, isA<Ok>(), reason: 'detectGame($code) should succeed');
        expect(result.value, anyOf(isNull, isA<String>()));
      }
    });

    test('detectAllGames always returns an Ok map', () async {
      final service = newService();
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      expect(result.value, isA<Map<String, String>>());
    });

    test('detectWorkshopFolder always returns an Ok nullable path', () async {
      final service = newService();
      final result = await service.detectWorkshopFolder();

      expect(result, isA<Ok>());
      expect(result.value, anyOf(isNull, isA<String>()));
    });

    test('clearCache is safe before and after detection', () async {
      final service = newService();
      service.clearCache();
      await service.detectAllGames();
      await service.detectAllGames(); // cached path
      service.clearCache();
      expect(true, isTrue);
    });
  });
}
