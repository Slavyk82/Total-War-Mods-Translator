import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/pack_image_generator_service.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

/// Tests for [PackImageGeneratorService].
///
/// The service composites a language flag (loaded via `rootBundle`) onto a
/// base image (mod image from disk/URL, or the bundled app icon) and writes a
/// `.png` next to the pack. We exercise it against REAL temp dirs and serve
/// the bundled assets (`assets/twmt_icon.png`, `assets/flags/*.png`) from the
/// real files on disk through a mock `flutter/assets` message handler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Repo root: test runs with cwd at the package root.
  final repoRoot = Directory.current.path;

  /// Reads a real asset file from disk so the mock bundle can serve it.
  Uint8List? realAsset(String assetKey) {
    final file = File(path.join(repoRoot, assetKey));
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  /// Installs a mock handler on the `flutter/assets` channel.
  ///
  /// [available] is the set of asset keys that resolve; any other key returns
  /// `null`, which makes `PlatformAssetBundle.load` throw the standard
  /// "Unable to load asset" `FlutterError` that the service catches.
  void installAssetHandler(Set<String> available) {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (!available.contains(key)) return null;
      final bytes = realAsset(key);
      if (bytes == null) return null;
      return ByteData.view(bytes.buffer);
    });
  }

  void clearAssetHandler() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  }

  /// Creates a real temp dir registered for cleanup.
  Directory makeTempDir() {
    final dir = Directory.systemTemp.createTempSync('pack_img_test_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// Writes a small valid PNG to [filePath] and returns it.
  String writePng(String filePath, {int width = 8, int height = 8}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(10, 20, 30, 255));
    File(filePath).writeAsBytesSync(img.encodePng(image));
    return filePath;
  }

  PackImageGeneratorService makeService() =>
      PackImageGeneratorService(logger: NoopLogger());

  const allAssets = {
    'assets/twmt_icon.png',
    'assets/flags/fr.png',
    'assets/flags/ja.png',
    'assets/flags/br.png',
    'assets/flags/en.png',
  };

  setUp(() => installAssetHandler(allAssets));
  tearDown(clearAssetHandler);

  group('ensurePackImage - early returns', () {
    test('returns Ok(null) when generateImage is false', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: false,
      );

      expect(result, isA<Ok<String?, Object>>());
      expect(result.value, isNull);
      // Nothing should be written.
      expect(Directory(dir.path).listSync(), isEmpty);
    });

    test('short-circuits and returns existing image path when present',
        () async {
      final dir = makeTempDir();
      // Pre-create the expected output: mod.pack -> mod.png
      final existing = path.join(dir.path, 'mod.png');
      writePng(existing);

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(existing));
    });
  });

  group('ensurePackImage - filename derivation', () {
    test('replaces .pack extension with .png (case-insensitive)', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'My_Mod.PACK',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(path.basename(result.value!), equals('My_Mod.png'));
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('appends .png when filename has no .pack extension', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'noext',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(path.basename(result.value!), equals('noext.png'));
      expect(File(result.value!).existsSync(), isTrue);
    });
  });

  group('ensurePackImage - useAppIcon', () {
    test('generates a valid 512x512 PNG from the app icon', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      final outPath = result.value!;
      expect(File(outPath).existsSync(), isTrue);

      final decoded = img.decodePng(File(outPath).readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(512));
      expect(decoded.height, equals(512));
    });

    test('returns Ok(null) when app icon asset is missing', () async {
      // Only flags available; no app icon.
      installAssetHandler({'assets/flags/fr.png'});
      final dir = makeTempDir();

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
      expect(Directory(dir.path).listSync(), isEmpty);
    });
  });

  group('ensurePackImage - flag resolution', () {
    test('resolves aliased language code (jp -> ja flag)', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'jp',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('resolves Brazilian Portuguese alias (ptbr -> br flag)', () async {
      final dir = makeTempDir();
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'ptbr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('returns Ok(null) when flag asset is missing for language', () async {
      // App icon available but the requested flag is not.
      installAssetHandler({'assets/twmt_icon.png'});
      final dir = makeTempDir();

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'xx', // unknown -> flag 'xx' which we don't serve
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
      expect(Directory(dir.path).listSync(), isEmpty);
    });
  });

  group('ensurePackImage - source image loading', () {
    test('loads a local mod image via localModImagePath', () async {
      final dir = makeTempDir();
      final modImage = writePng(path.join(dir.path, 'mod_image.png'),
          width: 64, height: 64);

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        localModImagePath: modImage,
        generateImage: true,
      );

      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
      final decoded = img.decodePng(File(result.value!).readAsBytesSync());
      expect(decoded!.width, equals(512));
    });

    test('loads a local mod image via modImageUrl (Windows drive path)',
        () async {
      final dir = makeTempDir();
      final modImage = writePng(path.join(dir.path, 'mod_image.png'));

      // On Windows the temp path has a drive letter (C:\...), which the
      // service treats as a local path. On other platforms it starts with '/'.
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        modImageUrl: modImage,
        generateImage: true,
      );

      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('falls back to app icon when mod image is unavailable', () async {
      final dir = makeTempDir();
      final missing = path.join(dir.path, 'does_not_exist.png');

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        localModImagePath: missing,
        generateImage: true,
        useAppIcon: false,
      );

      // Falls back to app icon, which is available -> image produced.
      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('returns Ok(null) when no source image and app icon also missing',
        () async {
      installAssetHandler({'assets/flags/fr.png'}); // no app icon
      final dir = makeTempDir();
      final missing = path.join(dir.path, 'does_not_exist.png');

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        localModImagePath: missing,
        generateImage: true,
        useAppIcon: false,
      );

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    test('ignores a local file that is not a valid image, falls back to icon',
        () async {
      final dir = makeTempDir();
      final garbage = path.join(dir.path, 'garbage.png');
      File(garbage).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        localModImagePath: garbage,
        generateImage: true,
        useAppIcon: false,
      );

      // Decode fails -> null -> falls back to app icon.
      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('downloads mod image from an HTTP URL that fails gracefully',
        () async {
      // Use an unreachable URL so the http.get throws/returns non-200, the
      // service warns and falls back to the app icon.
      final dir = makeTempDir();

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        modImageUrl: 'http://127.0.0.1:1/nonexistent.png',
        generateImage: true,
        useAppIcon: false,
      );

      // HTTP fetch fails -> falls back to app icon -> image produced.
      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });

    test('exercises the HTTP fetch path against a loopback server', () async {
      // NOTE: `flutter test` installs a mock HttpClient that intercepts ALL
      // real socket traffic and replies with status 400, so the in-service
      // `statusCode == 200` decode branch (lib lines 143-151) is unreachable
      // here. This test still drives `http.get` + the non-200 branch, then the
      // fallback to the app icon. We spin up a real loopback server so the URL
      // is well-formed and the code path is realistic.
      final pngBytes = img.encodePng(
        img.fill(img.Image(width: 32, height: 32, numChannels: 4),
            color: img.ColorRgba8(200, 100, 50, 255)),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest req) {
        req.response
          ..statusCode = 200
          ..add(pngBytes);
        req.response.close();
      });

      final dir = makeTempDir();
      final url = 'http://127.0.0.1:${server.port}/image.png';

      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        modImageUrl: url,
        generateImage: true,
        useAppIcon: false,
      );

      // Either the (sandboxed) fetch yields a usable image or it falls back to
      // the app icon; either way the output is a valid 512x512 PNG.
      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
      final decoded = img.decodePng(File(result.value!).readAsBytesSync());
      expect(decoded!.width, equals(512));
    });
  });

  group('ensurePackImage - error handling', () {
    test('returns Ok(null) when output path is not writable', () async {
      // gameDataPath points at a regular FILE; writing under it must fail and
      // the service swallows the error returning Ok(null) (never fails export).
      final dir = makeTempDir();
      final filePath = path.join(dir.path, 'iam_a_file');
      File(filePath).writeAsStringSync('x');
      // Use the file as the "directory" so the join is <file>/mod.png.
      final result = await makeService().ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: filePath,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('constructor', () {
    test('falls back to ServiceLocator logger when none injected', () async {
      // Registers a fake ILoggingService so the GetIt fallback resolves.
      await TestBootstrap.registerFakes();
      addTearDown(() => installAssetHandler(allAssets));
      // registerFakes re-inits the binding; reinstall the asset handler.
      installAssetHandler(allAssets);

      final service = PackImageGeneratorService();
      final dir = makeTempDir();
      final result = await service.ensurePackImage(
        packFileName: 'mod.pack',
        gameDataPath: dir.path,
        languageCode: 'fr',
        generateImage: true,
        useAppIcon: true,
      );

      expect(result.isOk, isTrue);
      expect(File(result.value!).existsSync(), isTrue);
    });
  });

  group('flagCodeFor', () {
    test('maps known aliases to flag basenames', () {
      expect(PackImageGeneratorService.flagCodeFor('jp'), equals('ja'));
      expect(PackImageGeneratorService.flagCodeFor('ptbr'), equals('br'));
      expect(PackImageGeneratorService.flagCodeFor('cz'), equals('cs'));
      expect(PackImageGeneratorService.flagCodeFor('fr'), equals('fr'));
    });

    test('returns lowercased input for unknown codes', () {
      expect(PackImageGeneratorService.flagCodeFor('XX'), equals('xx'));
    });
  });
}
