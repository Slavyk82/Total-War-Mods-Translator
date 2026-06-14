import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_extraction_mixin.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../helpers/noop_logger.dart';

class _MockCliManager extends Mock implements RpfmCliManager {}

/// Minimal host that satisfies [RpfmExtractionMixin]'s contract so the mixin
/// can be unit-tested in isolation. The CLI manager is mocked so the path /
/// game / schema lookups are deterministic, and the RPFM binary is pointed at
/// a real, harmless executable (or a deliberately missing one) to drive the
/// post-validation branches without a real RPFM install.
class _Host with RpfmExtractionMixin {
  _Host(this._cliManager, this._listResult);

  final RpfmCliManager _cliManager;
  final Result<List<String>, RpfmServiceException> _listResult;

  @override
  RpfmCliManager get cliManager => _cliManager;

  @override
  final ILoggingService logger = NoopLogger();

  @override
  final StreamController<double> progressController =
      StreamController<double>.broadcast();

  @override
  final StreamController<RpfmLogMessage> logController =
      StreamController<RpfmLogMessage>.broadcast();

  @override
  bool isCancelled = false;

  @override
  Process? currentProcess;

  @override
  Future<Result<List<String>, RpfmServiceException>> listPackContents(
    String packFilePath,
  ) async =>
      _listResult;
}

/// Resolves the dart-sdk `dart` executable from the test runner's location.
/// `dart <unknown-flags>` exits fast with a non-zero code, which is exactly
/// what we want to stand in for the RPFM binary's per-file extraction loop
/// (the real RPFM CLI is not available under test). [Platform.resolvedExecutable]
/// is `flutter_tester`, which lives under `<flutter>/bin/cache/...`, so the
/// dart SDK is a sibling at `bin/cache/dart-sdk/bin/dart(.exe)`.
String _dartExe() {
  final exe = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final idx = exe.toLowerCase().indexOf('/bin/cache/');
  if (idx > 0) {
    final flutterRoot = exe.substring(0, idx);
    final dart = p.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart');
    if (File(dart).existsSync()) return dart;
  }
  // Fallback: a path that does not exist forces a fast ProcessException, which
  // still drives the surrounding error handling (just a different branch).
  return Platform.isWindows ? r'C:\__no_such_rpfm__.exe' : '/__no_such_rpfm__';
}

void main() {
  late Directory tempDir;
  late _MockCliManager cli;

  /// A real executable that exits non-zero (fast) for RPFM's argument list —
  /// used to exercise the per-file extraction loop without a real RPFM binary.
  final fakeRpfm = _dartExe();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rpfm_extract_mixin_');
    cli = _MockCliManager();
    // Default happy-path stubs; individual tests override as needed.
    when(() => cli.getRpfmPath()).thenAnswer((_) async => Ok(fakeRpfm));
    when(() => cli.getGameSetting())
        .thenAnswer((_) async => const Ok('warhammer_3'));
    when(() => cli.getSchemaPath()).thenAnswer((_) async => tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Creates a real .pack file on disk so `File(packFilePath).exists()` passes.
  Future<String> realPack() async {
    final f = File(p.join(tempDir.path, 'mod.pack'));
    await f.writeAsString('PACK');
    return f.path;
  }

  String missingPack() => p.join(tempDir.path, 'does_not_exist.pack');

  group('extractLocalizationFiles', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFiles(missingPack());

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('propagates getRpfmPath failure', () async {
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no rpfm')),
      );
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmServiceException>());
    });

    test('propagates listPackContents failure', () async {
      final host = _Host(
        cli,
        Err(const RpfmServiceException('list failed')),
      );

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error.message, 'list failed');
    });

    test('returns an empty result when no localization files are present',
        () async {
      final host = _Host(cli, const Ok(['db/units_tables/data.bin']));

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Ok>());
      final value = (result as Ok).value as RpfmExtractResult;
      expect(value.localizationFileCount, 0);
      expect(value.extractedFiles, isEmpty);
    });

    test('propagates getGameSetting failure once loc files are found',
        () async {
      when(() => cli.getGameSetting()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no game')),
      );
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error.message, 'no game');
    });

    test('returns RpfmCancelledException when cancelled mid-batch', () async {
      final host = _Host(cli, const Ok(['text/db/foo.loc']))
        ..isCancelled = true;

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmCancelledException>());
    });

    test('continues past a non-zero RPFM exit and returns an Ok result',
        () async {
      // realExe exits non-zero for RPFM's argument list, so the per-file
      // extraction loop runs its error branch and continues.
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Ok>());
      final value = (result as Ok).value as RpfmExtractResult;
      // No file was actually extracted by the dummy executable.
      expect(value.extractedFiles, isEmpty);
    });

    test('wraps process spawn failures in RpfmExtractionException', () async {
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Ok(p.join(tempDir.path, 'missing_rpfm.exe')),
      );
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFiles(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmExtractionException>());
    });

    test('finally block emits final progress and resets cancellation',
        () async {
      final host = _Host(cli, const Ok([]));
      host.isCancelled = true;
      final progress = <double>[];
      host.progressController.stream.listen(progress.add);

      await host.extractLocalizationFiles(missingPack());
      await Future<void>.delayed(Duration.zero);

      expect(progress, contains(1.0));
      expect(host.isCancelled, isFalse);
    });
  });

  group('extractLocalizationFilesAsTsv', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFilesAsTsv(missingPack());

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('propagates getRpfmPath failure', () async {
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no rpfm')),
      );
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
    });

    test('errors when the schema path is not configured', () async {
      when(() => cli.getSchemaPath()).thenAnswer((_) async => null);
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error.message, contains('schema path not configured'));
    });

    test('errors when the schema directory does not exist', () async {
      final host = _Host(cli, const Ok([]));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: p.join(tempDir.path, 'no_such_schema_dir'),
      );

      expect(result, isA<Err>());
      expect(result.error.message, contains('schema directory not found'));
    });

    test('returns an empty result when no localization files are present',
        () async {
      final host = _Host(cli, const Ok(['db/units_tables/data.bin']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: tempDir.path,
      );

      expect(result, isA<Ok>());
      expect(((result as Ok).value as RpfmExtractResult).localizationFileCount,
          0);
    });

    test('errors when the schema file for the game is missing', () async {
      // schemaPath exists (tempDir) but contains no schema_*.ron file.
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: tempDir.path,
      );

      expect(result, isA<Err>());
      expect(result.error.message, contains('schema file not found'));
    });

    test('continues past a non-zero RPFM exit once the schema file exists',
        () async {
      // Create the schema file the mixin expects for warhammer_3 so it gets
      // past the schema-file guard into the extraction loop.
      final schemaDir = await Directory(p.join(tempDir.path, 'schema'))
          .create(recursive: true);
      // Match RpfmGameSchema.getSchemaFilePath for any game by creating every
      // plausible schema file name in the dir; the loop is what we want to hit.
      for (final name in ['wh3', 'warhammer_3', 'warhammer3']) {
        await File(p.join(schemaDir.path, 'schema_$name.ron'))
            .writeAsString('()');
      }
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: schemaDir.path,
      );

      // The schema file exists, so the loop runs; the dummy binary exits
      // non-zero, the loop continues and an Ok (empty) result is returned.
      expect(result, isA<Ok>());
    });

    test('propagates listPackContents failure', () async {
      final host = _Host(cli, Err(const RpfmServiceException('list failed')));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: tempDir.path,
      );

      expect(result, isA<Err>());
      expect(result.error.message, 'list failed');
    });

    test('propagates getGameSetting failure once loc files are found',
        () async {
      when(() => cli.getGameSetting()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no game')),
      );
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: tempDir.path,
      );

      expect(result, isA<Err>());
      expect(result.error.message, 'no game');
    });

    test('returns RpfmCancelledException when cancelled mid-batch', () async {
      final schemaDir = await Directory(p.join(tempDir.path, 'schema_cancel'))
          .create(recursive: true);
      await File(p.join(schemaDir.path, 'schema_wh3.ron')).writeAsString('()');
      final host = _Host(cli, const Ok(['text/db/foo.loc']))
        ..isCancelled = true;

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: schemaDir.path,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmCancelledException>());
    });

    test('wraps process spawn failures in RpfmExtractionException', () async {
      final schemaDir = await Directory(p.join(tempDir.path, 'schema_spawn'))
          .create(recursive: true);
      await File(p.join(schemaDir.path, 'schema_wh3.ron')).writeAsString('()');
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Ok(p.join(tempDir.path, 'missing_rpfm.exe')),
      );
      final host = _Host(cli, const Ok(['text/db/foo.loc']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out'),
        schemaPath: schemaDir.path,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmExtractionException>());
    });

    test('logs to the log controller during TSV extraction', () async {
      final schemaDir = await Directory(p.join(tempDir.path, 'schema2'))
          .create(recursive: true);
      for (final name in ['wh3', 'warhammer_3', 'warhammer3']) {
        await File(p.join(schemaDir.path, 'schema_$name.ron'))
            .writeAsString('()');
      }
      final logs = <RpfmLogMessage>[];
      final host = _Host(cli, const Ok(['text/db/foo.loc']));
      host.logController.stream.listen(logs.add);

      await host.extractLocalizationFilesAsTsv(
        await realPack(),
        outputDirectory: p.join(tempDir.path, 'out2'),
        schemaPath: schemaDir.path,
      );
      await Future<void>.delayed(Duration.zero);

      // The loop is entered (schema file exists), so _addLog fires at least
      // once for the "Extracting as TSV" message.
      expect(logs, isNotEmpty);
    });
  });

  group('extractAllFiles', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(cli, const Ok([]));

      final result = await host.extractAllFiles(
        missingPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('propagates getRpfmPath failure', () async {
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no rpfm')),
      );
      final host = _Host(cli, const Ok([]));

      final result = await host.extractAllFiles(
        await realPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
    });

    test('propagates getGameSetting failure', () async {
      when(() => cli.getGameSetting()).thenAnswer(
        (_) async => Err(const RpfmServiceException('no game')),
      );
      final host = _Host(cli, const Ok([]));

      final result = await host.extractAllFiles(
        await realPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error.message, 'no game');
    });

    test('returns an extraction error when RPFM exits non-zero', () async {
      // realExe starts, exits non-zero for the RPFM argument list; the streams
      // are drained and the stderr is parsed into an RpfmExtractionException.
      final host = _Host(cli, const Ok([]));

      final result = await host.extractAllFiles(
        await realPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmExtractionException>());
    });

    test('wraps process spawn failures in RpfmExtractionException', () async {
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => Ok(p.join(tempDir.path, 'missing_rpfm.exe')),
      );
      final host = _Host(cli, const Ok([]));

      final result = await host.extractAllFiles(
        await realPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmExtractionException>());
    });

    test('clears currentProcess and cancellation in its finally block',
        () async {
      final host = _Host(cli, const Ok([]))..isCancelled = true;

      await host.extractAllFiles(
        await realPack(),
        p.join(tempDir.path, 'out'),
      );

      expect(host.currentProcess, isNull);
      expect(host.isCancelled, isFalse);
    });
  });

  group('_createTempDirectory (no explicit output directory)', () {
    setUp(() {
      // Mock path_provider so getTemporaryDirectory() resolves to our temp dir.
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    test('extractLocalizationFiles creates a temp dir when none is given',
        () async {
      final host = _Host(cli, const Ok(['db/data.bin']));

      final result = await host.extractLocalizationFiles(await realPack());

      // No loc files -> empty result, but the temp directory was created.
      expect(result, isA<Ok>());
    });

    test('extractLocalizationFilesAsTsv creates a temp dir when none is given',
        () async {
      final host = _Host(cli, const Ok(['db/data.bin']));

      final result = await host.extractLocalizationFilesAsTsv(
        await realPack(),
        schemaPath: tempDir.path,
      );

      expect(result, isA<Ok>());
    });
  });
}
