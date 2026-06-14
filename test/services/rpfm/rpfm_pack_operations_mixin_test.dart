import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_pack_operations_mixin.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../helpers/noop_logger.dart';

class _MockRpfmCliManager extends Mock implements RpfmCliManager {}

/// Minimal host that satisfies [RpfmPackOperationsMixin]'s contract so the
/// mixin can be unit-tested in isolation against a mocked [RpfmCliManager].
class _Host with RpfmPackOperationsMixin {
  _Host(this.cliManager);

  @override
  final RpfmCliManager cliManager;

  @override
  final ILoggingService logger = NoopLogger();

  @override
  bool isCancelled = false;

  @override
  Process? currentProcess;
}

/// Strongly typed Ok/Err helpers so the `as Ok`/`is Err` casts inside the
/// mixin operate on the exact generic types it expects.
Result<String, RpfmServiceException> _okStr(String v) =>
    Ok<String, RpfmServiceException>(v);
Result<String, RpfmServiceException> _errStr(RpfmServiceException e) =>
    Err<String, RpfmServiceException>(e);

/// Source of a tiny native stub that impersonates rpfm_cli.exe well enough to
/// drive the success / add-loop / list-parsing branches:
///   * `pack create` writes a non-empty file at `--pack-path` and exits 0;
///   * `pack add`    appends a byte to `--pack-path` and exits 0;
///   * `pack list`   prints two file paths and exits 0.
const _okStubSource = r'''
import 'dart:io';

String? _argAfter(List<String> a, String flag) {
  final i = a.indexOf(flag);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

void main(List<String> a) {
  final packPath = _argAfter(a, '--pack-path');
  if (a.contains('create')) {
    if (packPath != null) File(packPath).writeAsStringSync('PACKDATA');
    exit(0);
  }
  if (a.contains('add')) {
    if (packPath != null) {
      final f = File(packPath);
      f.writeAsStringSync('${f.existsSync() ? f.readAsStringSync() : ''}+');
    }
    exit(0);
  }
  if (a.contains('list')) {
    stdout.writeln('text/db/foo.loc');
    stdout.writeln('text/db/bar.loc');
    exit(0);
  }
  exit(0);
}
''';

/// Source of a stub that always fails: prints an RPFM-shaped error to stderr
/// and exits non-zero. Drives the non-zero-exit branches deterministically
/// without hanging (unlike handing RPFM args to cmd.exe).
const _failStubSource = r'''
import 'dart:io';
void main(List<String> a) {
  stderr.writeln('Error: stub forced failure');
  exit(1);
}
''';

/// Source of a stub where `pack create` succeeds (writes the file) but every
/// `pack add` fails with a non-zero exit. Drives the per-file add-failure
/// branches (cleanup + Err) for both the TSV and .loc loops.
const _addFailStubSource = r'''
import 'dart:io';

String? _argAfter(List<String> a, String flag) {
  final i = a.indexOf(flag);
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : null;
}

void main(List<String> a) {
  final packPath = _argAfter(a, '--pack-path');
  if (a.contains('create')) {
    if (packPath != null) File(packPath).writeAsStringSync('PACKDATA');
    exit(0);
  }
  if (a.contains('add')) {
    stderr.writeln('Error: stub add failure');
    exit(1);
  }
  exit(0);
}
''';

/// Resolve a usable `dart` executable, compile [source] to a native exe at
/// [outPath], and return it on success or null on failure. Compilation is
/// best-effort: the dependent tests skip themselves when it returns null.
String? _compileStub(String dartDir, String source, String outPath) {
  final src = File('$outPath.dart')..writeAsStringSync(source);
  final vmDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>{
    if (dartDir.isNotEmpty) '$dartDir/dart.exe',
    '$vmDir/dart.exe',
    '$vmDir/dart',
    'dart',
  };
  // Under `flutter test`, the VM is flutter_tester.exe under the engine
  // artifacts dir; the bundled Dart SDK sits at
  // <flutterRoot>/bin/cache/dart-sdk/bin/dart.exe. Walk up to find it.
  var dir = Directory(vmDir);
  for (var i = 0; i < 10 && dir.parent.path != dir.path; i++) {
    final dartExe = File('${dir.path}/bin/cache/dart-sdk/bin/dart.exe');
    if (dartExe.existsSync()) {
      candidates.add(dartExe.path);
      break;
    }
    dir = dir.parent;
  }
  for (final dart in candidates) {
    try {
      final compile = Process.runSync(
        dart,
        ['compile', 'exe', src.path, '-o', outPath],
      );
      if (compile.exitCode == 0 && File(outPath).existsSync()) {
        return outPath;
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  return null;
}

// Stub executables compiled once, synchronously, before tests are registered
// so `skip:` conditions see the real outcome.
final Directory _stubDir =
    Directory.systemTemp.createTempSync('rpfm_pack_stub_');
final String? _okStub =
    _compileStub('', _okStubSource, '${_stubDir.path}/ok_stub.exe');
final String? _failStub =
    _compileStub('', _failStubSource, '${_stubDir.path}/fail_stub.exe');
final String? _addFailStub =
    _compileStub('', _addFailStubSource, '${_stubDir.path}/addfail_stub.exe');

void main() {
  late Directory tempDir;
  late _MockRpfmCliManager cli;
  late _Host host;

  // Trigger the lazy stub compilation up front so timing is attributed to
  // setup rather than the first dependent test.
  setUpAll(() {
    _okStub;
    _failStub;
    _addFailStub;
  });

  tearDownAll(() async {
    if (await _stubDir.exists()) {
      await _stubDir.delete(recursive: true);
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rpfm_pack_mixin_');
    cli = _MockRpfmCliManager();
    host = _Host(cli);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---- shared mock wiring helpers ----------------------------------------

  /// Wire the cliManager so [createPack] reaches the schema validation stage.
  void wireRpfmAndGame({
    String? rpfmPath,
    String game = 'warhammer_3',
  }) {
    when(() => cli.getRpfmPath())
        .thenAnswer((_) async => _okStr(rpfmPath ?? '${tempDir.path}/rpfm.exe'));
    when(() => cli.getGameSetting())
        .thenAnswer((_) async => _okStr(game));
  }

  /// Create a valid schema file for warhammer_3 so createPack proceeds past
  /// all validation and into the actual `pack create` invocation.
  Future<String> writeSchema() async {
    final schemaDir = await Directory('${tempDir.path}/schemas').create();
    await File('${schemaDir.path}/schema_wh3.ron').writeAsString('// schema');
    return schemaDir.path;
  }

  group('hasPackableLocalizationFiles', () {
    test('detects .tsv and .loc files case-insensitively', () {
      expect(hasPackableLocalizationFiles(['a/b/text.TSV']), isTrue);
      expect(hasPackableLocalizationFiles(['x/y/data.loc']), isTrue);
      expect(hasPackableLocalizationFiles(['mod.pack', 'readme.txt']), isFalse);
      expect(hasPackableLocalizationFiles(const []), isFalse);
    });
  });

  group('createPack — pre-CLI validation guards', () {
    test('missing input directory -> RpfmPackingException', () async {
      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/does_not_exist',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmPackingException>());
      verifyNever(() => cli.getRpfmPath());
    });

    test('resets isCancelled at the start of the operation', () async {
      host.isCancelled = true;

      await host.createPack(
        inputDirectory: '${tempDir.path}/does_not_exist',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(host.isCancelled, isFalse);
    });

    test('getRpfmPath error is propagated', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => _errStr(const RpfmNotFoundException('no rpfm')),
      );

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmNotFoundException>());
    });

    test('getGameSetting error is propagated', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      when(() => cli.getRpfmPath())
          .thenAnswer((_) async => _okStr('${tempDir.path}/rpfm.exe'));
      when(() => cli.getGameSetting()).thenAnswer(
        (_) async => _errStr(const RpfmServiceException('bad game')),
      );

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmServiceException>());
    });

    test('null schema path -> RpfmServiceException', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      wireRpfmAndGame();
      when(() => cli.getSchemaPath()).thenAnswer((_) async => null);

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmServiceException>());
      expect(result.error.message, contains('schema path not configured'));
    });

    test('empty schema path -> RpfmServiceException', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      wireRpfmAndGame();
      when(() => cli.getSchemaPath()).thenAnswer((_) async => '');

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmServiceException>());
    });

    test('missing schema file -> RpfmServiceException', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      // schemaDir exists but the per-game schema file inside it does not.
      final schemaDir = await Directory('${tempDir.path}/schemas').create();
      wireRpfmAndGame();
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir.path);

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmServiceException>());
      expect(result.error.message, contains('schema file not found'));
    });
  });

  group('createPack — reaches Process.run (CLI spawn failure)', () {
    test('spawn failure routes through the catch block without wiping a '
        'pre-existing pack (packFileTouched=false)', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      await File('${inputDir.path}/text.tsv').writeAsString('key\tvalue');
      final schemaDir = await writeSchema();

      // Point rpfmPath at a non-existent executable so Process.run throws a
      // ProcessException, exercising the outer catch. The pack was never
      // touched, so a (hypothetical) prior pack must be preserved.
      final outDir = await Directory('${tempDir.path}/out').create();
      final priorPack = File('${outDir.path}/mod.pack');
      await priorPack.writeAsString('previous good pack');

      wireRpfmAndGame(rpfmPath: '${tempDir.path}/nonexistent_rpfm.exe');
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: priorPack.path,
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('Packing failed'));
      // packFileTouched was false at the throw, so the prior pack survives.
      expect(await priorPack.exists(), isTrue);
    });

    test('non-zero exit from a real executable triggers cleanup of the '
        'partial pack (parseErrorMessage + _cleanupPartialPack)', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      await File('${inputDir.path}/text.tsv').writeAsString('key\tvalue');
      final schemaDir = await writeSchema();

      // Use a real, runnable executable that ignores the RPFM args and exits
      // non-zero, so `pack create` returns exitCode != 0 (rather than throwing).
      // This drives lines 110-117 (parse error + cleanup + Err) and the
      // _cleanupPartialPack helper. A pre-existing file at the output path is
      // removed because packFileTouched is now true.
      final outDir = await Directory('${tempDir.path}/out').create();
      final partialPack = File('${outDir.path}/mod.pack');
      await partialPack.writeAsString('partial');

      wireRpfmAndGame(rpfmPath: _failStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: partialPack.path,
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('Failed to create empty pack'));
      // packFileTouched was true, so the partial pack is cleaned up.
      expect(await partialPack.exists(), isFalse);
    }, skip: _failStub == null ? 'fail stub not compiled' : false);
  });

  group('getPackInfo', () {
    test('missing pack file -> RpfmInvalidPackException', () async {
      final result = await host.getPackInfo('${tempDir.path}/missing.pack');

      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('propagates Err from listPackContents for an existing pack',
        () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');

      // listPackContents fails early because getRpfmPath returns Err.
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => _errStr(const RpfmNotFoundException('no rpfm')),
      );

      final result = await host.getPackInfo(pack.path);

      expect(result.error, isA<RpfmServiceException>());
    });
  });

  group('listPackContents', () {
    test('missing pack file -> RpfmInvalidPackException', () async {
      final result =
          await host.listPackContents('${tempDir.path}/missing.pack');

      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('getRpfmPath error is propagated', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => _errStr(const RpfmNotFoundException('no rpfm')),
      );

      final result = await host.listPackContents(pack.path);

      expect(result.error, isA<RpfmNotFoundException>());
    });

    test('getGameSetting error is propagated', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');
      when(() => cli.getRpfmPath())
          .thenAnswer((_) async => _okStr('${tempDir.path}/rpfm.exe'));
      when(() => cli.getGameSetting()).thenAnswer(
        (_) async => _errStr(const RpfmServiceException('bad game')),
      );

      final result = await host.listPackContents(pack.path);

      expect(result.error, isA<RpfmServiceException>());
    });

    test('spawn failure is caught and reported as a LIST error', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');
      when(() => cli.getRpfmPath()).thenAnswer(
        (_) async => _okStr('${tempDir.path}/nonexistent_rpfm.exe'),
      );
      when(() => cli.getGameSetting())
          .thenAnswer((_) async => _okStr('warhammer_3'));

      final result = await host.listPackContents(pack.path);

      expect(result.error, isA<RpfmServiceException>());
      expect(result.error.message, contains('Failed to list pack contents'));
    });
  });

  // ---- Stub-driven happy paths -------------------------------------------
  // These exercise the branches that follow a *successful* `pack create`
  // (the add-loops, success verification, list parsing) using a compiled
  // native stub that impersonates rpfm_cli.exe. Skipped if the stub failed
  // to compile (e.g. no Dart toolchain in the runner).
  group('createPack — stub-driven success and add-loops', () {
    test('adds TSV files and returns Ok with the output pack path', () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/a.tsv').writeAsString('key\tvalue');
      await File('${inputDir.path}/b.tsv').writeAsString('key\tvalue');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _okStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final progress = <int>[];
      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
        onProgress: (cur, total, name) => progress.add(cur),
      );

      expect(result, isA<Ok>());
      expect(result.value, '${tempDir.path}/out/mod.pack');
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isTrue);
      expect(host.currentProcess, isNull);
      // Per-file + final progress callbacks fired.
      expect(progress, isNotEmpty);
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('cancellation before the add-loop cleans up and returns cancelled',
        () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/a.tsv').writeAsString('key\tvalue');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _okStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      // Cancel via the first onProgress callback (emitted at loop entry,
      // before the add process is started for that file).
      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
        onProgress: (cur, total, name) => host.isCancelled = true,
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('cancelled'));
      // Partial pack cleaned up on the cancel path.
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isFalse);
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('no .tsv/.loc files -> RpfmPackingException after empty pack', () async {
      final inputDir = await Directory('${tempDir.path}/in').create();
      await File('${inputDir.path}/readme.txt').writeAsString('hello');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _okStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final result = await host.createPack(
        inputDirectory: inputDir.path,
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('No localization files'));
      // Empty pack from step 1 is cleaned up.
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isFalse);
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('falls back to .loc files when no TSV present', () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/x.loc').writeAsString('locdata');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _okStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final progress = <int>[];
      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
        onProgress: (cur, total, name) => progress.add(cur),
      );

      expect(result, isA<Ok>());
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isTrue);
      expect(progress, isNotEmpty);
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('TSV add failure cleans up and returns RpfmPackingException',
        () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/a.tsv').writeAsString('key\tvalue');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _addFailStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('Failed to add TSV file'));
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isFalse);
    }, skip: _addFailStub == null ? 'addfail stub not compiled' : false);

    test('cancellation during a .loc add cleans up and returns cancelled',
        () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/x.loc').writeAsString('locdata');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _okStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      // onProgress fires at the top of the loc iteration (before the add
      // process completes); flagging cancellation here exercises the
      // post-process cancellation branch in the .loc loop.
      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
        onProgress: (cur, total, name) => host.isCancelled = true,
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('cancelled'));
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isFalse);
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('all .loc files failing -> RpfmPackingException and cleanup',
        () async {
      final inputDir = await Directory('${tempDir.path}/in/text').create(
        recursive: true,
      );
      await File('${inputDir.path}/x.loc').writeAsString('locdata');
      final schemaDir = await writeSchema();

      wireRpfmAndGame(rpfmPath: _addFailStub!);
      when(() => cli.getSchemaPath()).thenAnswer((_) async => schemaDir);

      final result = await host.createPack(
        inputDirectory: '${tempDir.path}/in',
        languageCode: 'fr',
        outputPackPath: '${tempDir.path}/out/mod.pack',
      );

      expect(result.error, isA<RpfmPackingException>());
      expect(result.error.message, contains('Failed to add any .loc file'));
      expect(await File('${tempDir.path}/out/mod.pack').exists(), isFalse);
    }, skip: _addFailStub == null ? 'addfail stub not compiled' : false);
  });

  group('getPackInfo / listPackContents — stub-driven success', () {
    test('listPackContents parses the stub file list', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');
      wireRpfmAndGame(rpfmPath: _okStub!);

      final result = await host.listPackContents(pack.path);

      expect(result, isA<Ok>());
      expect(result.value, containsAll(<String>[
        'text/db/foo.loc',
        'text/db/bar.loc',
      ]));
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('getPackInfo returns metadata with localization counts', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACKDATA');
      wireRpfmAndGame(rpfmPath: _okStub!);

      final result = await host.getPackInfo(pack.path);

      expect(result, isA<Ok>());
      final info = result.value;
      expect(info.fileCount, 2);
      expect(info.localizationFileCount, 2);
      expect(info.fileName, 'real.pack');
    }, skip: _okStub == null ? 'ok stub not compiled' : false);

    test('listPackContents reports a LIST_ERROR on non-zero exit', () async {
      final pack = File('${tempDir.path}/real.pack');
      await pack.writeAsString('PACK');
      // _failStub exits 1 for the `pack list` command, exercising the
      // exitCode != 0 branch (parse error + Err) rather than the catch path.
      wireRpfmAndGame(rpfmPath: _failStub!);

      final result = await host.listPackContents(pack.path);

      expect(result.error, isA<RpfmServiceException>());
      expect(result.error.message, contains('Failed to list pack contents'));
    }, skip: _failStub == null ? 'fail stub not compiled' : false);
  });
}
