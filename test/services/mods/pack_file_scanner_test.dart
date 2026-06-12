import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/services/mods/pack_file_scanner.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';

import '../../helpers/noop_logger.dart';

class MockModScanCacheRepository extends Mock
    implements ModScanCacheRepository {}

class MockRpfmService extends Mock implements IRpfmService {}

ModScanCache _cache({
  required String path,
  int fileLastModified = 1000,
  bool hasLocFiles = true,
}) {
  return ModScanCache(
    id: 'c-$path',
    packFilePath: path,
    fileLastModified: fileLastModified,
    hasLocFiles: hasLocFiles,
    scannedAt: 0,
  );
}

void main() {
  late MockModScanCacheRepository cacheRepo;
  late MockRpfmService rpfm;
  late PackFileScanner scanner;
  late Directory tempRoot;

  setUpAll(() {
    registerFallbackValue(<ModScanCache>[]);
  });

  setUp(() async {
    cacheRepo = MockModScanCacheRepository();
    rpfm = MockRpfmService();
    scanner = PackFileScanner(
      modScanCacheRepository: cacheRepo,
      rpfmService: rpfm,
      logger: NoopLogger(),
    );
    tempRoot = await Directory.systemTemp.createTemp('pack_scan_test_');

    // Sensible defaults: RPFM present, empty cache, upsert succeeds.
    when(() => rpfm.isRpfmAvailable()).thenAnswer((_) async => true);
    when(() => cacheRepo.getByPackFilePaths(any()))
        .thenAnswer((_) async => const Ok(<String, ModScanCache>{}));
    when(() => cacheRepo.upsertBatch(any()))
        .thenAnswer((_) async => const Ok(<ModScanCache>[]));
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// Create a workshop mod dir [name] containing pack files [packNames].
  Directory modDir(String name, List<String> packNames) {
    final dir = Directory('${tempRoot.path}/$name')..createSync();
    for (final p in packNames) {
      File('${dir.path}/$p').writeAsStringSync('PACK');
    }
    return dir;
  }

  /// The exact pack-file path as the scanner sees it (same `list()` source),
  /// avoiding `/` vs `\` separator mismatches on Windows.
  String realPackPath(Directory dir) => dir
      .listSync()
      .firstWhere((e) => e.path.toLowerCase().endsWith('.pack'))
      .path;

  void stubList(List<String> contents) {
    when(() => rpfm.listPackContents(any()))
        .thenAnswer((_) async => Ok(contents));
  }

  group('directory filtering', () {
    test('ignores non-numeric workshop dirs', () async {
      modDir('not_a_number', ['mod.pack']);
      final result = await scanner.collectModData([
        Directory('${tempRoot.path}/not_a_number'),
      ]);
      expect(result, isEmpty);
      verifyNever(() => rpfm.listPackContents(any()));
    });

    test('skips dirs without a .pack file', () async {
      final dir = Directory('${tempRoot.path}/123')..createSync();
      File('${dir.path}/readme.txt').writeAsStringSync('x');
      final result = await scanner.collectModData([dir]);
      expect(result, isEmpty);
    });

    test('skips TWMT-generated packs', () async {
      final dir = modDir('123', ['my_twmt_translation.pack']);
      final result = await scanner.collectModData([dir]);
      expect(result, isEmpty);
      verifyNever(() => rpfm.listPackContents(any()));
    });
  });

  group('scanning and caching', () {
    test('scans on cache miss and includes mods that have .loc files',
        () async {
      final dir = modDir('123', ['mod.pack']);
      stubList(['text/db/foo.loc', 'other/bar.txt']);

      final result = await scanner.collectModData([dir]);

      expect(result, hasLength(1));
      expect(result.single.workshopId, '123');
      expect(result.single.hasLocFiles, isTrue);
      // Cache updated with the scan result.
      final captured =
          verify(() => cacheRepo.upsertBatch(captureAny())).captured.single
              as List<ModScanCache>;
      expect(captured.single.hasLocFiles, isTrue);
      expect(captured.single.packFilePath, realPackPath(dir));
    });

    test('excludes mods without .loc files but still caches the result',
        () async {
      final dir = modDir('123', ['mod.pack']);
      stubList(['text/db/foo.txt']);

      final result = await scanner.collectModData([dir]);

      expect(result, isEmpty);
      final captured =
          verify(() => cacheRepo.upsertBatch(captureAny())).captured.single
              as List<ModScanCache>;
      expect(captured.single.hasLocFiles, isFalse);
    });

    test('treats an RPFM listing error as no loc files', () async {
      final dir = modDir('123', ['mod.pack']);
      when(() => rpfm.listPackContents(any())).thenAnswer(
        (_) async => Err(const RpfmServiceException('cli failed')),
      );

      final result = await scanner.collectModData([dir]);
      expect(result, isEmpty);
    });
  });

  group('cache hits', () {
    test('uses valid cache (with loc) without re-scanning', () async {
      final dir = modDir('123', ['mod.pack']);
      final p = realPackPath(dir);
      final lm = File(p).statSync().modified.millisecondsSinceEpoch ~/ 1000;
      when(() => cacheRepo.getByPackFilePaths(any())).thenAnswer(
        (_) async => Ok({p: _cache(path: p, fileLastModified: lm)}),
      );

      final result = await scanner.collectModData([dir]);

      expect(result, hasLength(1));
      expect(result.single.hasLocFiles, isTrue);
      verifyNever(() => rpfm.listPackContents(any()));
      verifyNever(() => cacheRepo.upsertBatch(any()));
    });

    test('valid cache with no loc files skips the mod', () async {
      final dir = modDir('123', ['mod.pack']);
      final p = realPackPath(dir);
      final lm = File(p).statSync().modified.millisecondsSinceEpoch ~/ 1000;
      when(() => cacheRepo.getByPackFilePaths(any())).thenAnswer(
        (_) async => Ok(
          {p: _cache(path: p, fileLastModified: lm, hasLocFiles: false)},
        ),
      );

      final result = await scanner.collectModData([dir]);
      expect(result, isEmpty);
      verifyNever(() => rpfm.listPackContents(any()));
    });

    test('reuses the existing cache id when re-scanning a stale entry',
        () async {
      final dir = modDir('123', ['mod.pack']);
      final p = realPackPath(dir);
      // Stale cache (different fileLastModified) -> rescan.
      when(() => cacheRepo.getByPackFilePaths(any())).thenAnswer(
        (_) async => Ok({p: _cache(path: p, fileLastModified: 1)}),
      );
      stubList(['x.loc']);

      await scanner.collectModData([dir]);

      final captured =
          verify(() => cacheRepo.upsertBatch(captureAny())).captured.single
              as List<ModScanCache>;
      // Existing cache id is reused rather than a fresh uuid.
      expect(captured.single.id, 'c-$p');
    });
  });

  group('RPFM unavailable', () {
    test('returns empty when RPFM is unavailable and there is no cache',
        () async {
      final dir = modDir('123', ['mod.pack']);
      when(() => rpfm.isRpfmAvailable()).thenAnswer((_) async => false);

      final result = await scanner.collectModData([dir]);
      expect(result, isEmpty);
      verifyNever(() => rpfm.listPackContents(any()));
      verifyNever(() => cacheRepo.upsertBatch(any()));
    });
  });
}
