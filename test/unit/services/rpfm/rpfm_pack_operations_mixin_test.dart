import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_pack_operations_mixin.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

class _MockCliManager extends Mock implements RpfmCliManager {}

class _FakeLogger implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}

  @override
  void info(String message, [dynamic data]) {}

  @override
  void warning(String message, [dynamic data]) {}

  @override
  void error(String message, [dynamic error, StackTrace? stackTrace]) {}

  @override
  Stream<LogEntry> get logStream => const Stream.empty();

  @override
  List<LogEntry> get recentLogs => const [];

  @override
  String? get logFilePath => null;
}

/// Minimal host class so the mixin can be exercised in isolation.
class _PackOpsHarness with RpfmPackOperationsMixin {
  _PackOpsHarness({required this.cliManager, required this.logger});

  @override
  final RpfmCliManager cliManager;

  @override
  final ILoggingService logger;

  @override
  bool isCancelled = false;

  @override
  Process? currentProcess;
}

/// Fake rpfm_cli where 'pack create' succeeds (and writes the pack file,
/// clobbering any previous pack, like the real CLI) but 'pack add' fails.
const _addFailsBat = '@echo off\r\n'
    'if "%~4"=="create" (\r\n'
    '  echo created> "%~6"\r\n'
    '  exit /b 0\r\n'
    ')\r\n'
    'echo schema mismatch 1>&2\r\n'
    'exit /b 1\r\n';

/// Fake rpfm_cli where 'pack create' writes a partial file then fails.
const _createFailsBat = '@echo off\r\n'
    'echo partial> "%~6"\r\n'
    'echo cannot create pack 1>&2\r\n'
    'exit /b 1\r\n';

/// Fake rpfm_cli where every command succeeds.
const _allOkBat = '@echo off\r\n'
    'if "%~4"=="create" (\r\n'
    '  echo created> "%~6"\r\n'
    ')\r\n'
    'exit /b 0\r\n';

void main() {
  late Directory tempRoot;
  late String inputDir;
  late String outputPackPath;
  late String fakeRpfmPath;
  late _MockCliManager cliManager;
  late _PackOpsHarness packOps;

  setUp(() async {
    tempRoot =
        await Directory.systemTemp.createTemp('twmt_pack_ops_mixin_test_');

    // Input directory with a single TSV file to pack.
    inputDir = path.join(tempRoot.path, 'input');
    final tsvFile = File(
      path.join(inputDir, 'text', 'db', 'translation__.loc.tsv'),
    );
    await tsvFile.create(recursive: true);
    await tsvFile.writeAsString('key\ttext\nfoo\tbar\n');

    // Schema file expected by createPack ('warhammer_3' -> schema_wh3.ron).
    final schemaDir = path.join(tempRoot.path, 'schemas');
    final schemaFile = File(path.join(schemaDir, 'schema_wh3.ron'));
    await schemaFile.create(recursive: true);

    // Output pack inside a simulated game data directory.
    outputPackPath = path.join(tempRoot.path, 'data', 'translation.pack');

    fakeRpfmPath = path.join(tempRoot.path, 'fake_rpfm.bat');

    cliManager = _MockCliManager();
    when(() => cliManager.getRpfmPath())
        .thenAnswer((_) async => Ok(fakeRpfmPath));
    when(() => cliManager.getGameSetting())
        .thenAnswer((_) async => const Ok('warhammer_3'));
    when(() => cliManager.getSchemaPath()).thenAnswer((_) async => schemaDir);

    packOps = _PackOpsHarness(cliManager: cliManager, logger: _FakeLogger());
  });

  tearDown(() async {
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> writeFakeRpfm(String batContent) async {
    await File(fakeRpfmPath).writeAsString(batContent);
  }

  group('createPack partial pack cleanup', () {
    test(
      'deletes the partial pack file when a TSV "pack add" fails',
      () async {
        await writeFakeRpfm(_addFailsBat);

        final result = await packOps.createPack(
          inputDirectory: inputDir,
          languageCode: 'fr',
          outputPackPath: outputPackPath,
        );

        expect(result.isErr, isTrue);
        expect(result.unwrapErr(), isA<RpfmPackingException>());
        expect(
          File(outputPackPath).existsSync(),
          isFalse,
          reason: 'A half-built pack must not be left in the game data '
              'directory when a TSV add fails',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'deletes the partial pack file when "pack create" itself fails',
      () async {
        await writeFakeRpfm(_createFailsBat);

        final result = await packOps.createPack(
          inputDirectory: inputDir,
          languageCode: 'fr',
          outputPackPath: outputPackPath,
        );

        expect(result.isErr, isTrue);
        expect(result.unwrapErr(), isA<RpfmPackingException>());
        expect(
          File(outputPackPath).existsSync(),
          isFalse,
          reason: 'A partially written pack from a failed "pack create" '
              'must be removed',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'deletes the partial pack file when an unexpected exception is '
      'thrown mid-loop (generic catch path)',
      () async {
        await writeFakeRpfm(_addFailsBat
            .replaceAll('exit /b 1', 'exit /b 0')
            .replaceAll('echo schema mismatch 1>&2\r\n', ''));

        // Sabotage the fake rpfm right before the first 'pack add'
        // (onProgress fires before each per-file process is started), so
        // Process.start throws and the generic catch path is exercised.
        final result = await packOps.createPack(
          inputDirectory: inputDir,
          languageCode: 'fr',
          outputPackPath: outputPackPath,
          onProgress: (currentFile, totalFiles, fileName) {
            final fake = File(fakeRpfmPath);
            if (fake.existsSync()) {
              fake.deleteSync();
            }
          },
        );

        expect(result.isErr, isTrue);
        expect(result.unwrapErr(), isA<RpfmPackingException>());
        expect(
          File(outputPackPath).existsSync(),
          isFalse,
          reason: 'The generic catch path must also clean up the partial pack',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'does NOT delete a pre-existing pack when validation fails before '
      '"pack create" runs',
      () async {
        await writeFakeRpfm(_allOkBat);

        // Simulate the previous good export still being in the data folder.
        final previousPack = File(outputPackPath);
        await previousPack.create(recursive: true);
        await previousPack.writeAsString('previous good pack');

        final result = await packOps.createPack(
          inputDirectory: path.join(tempRoot.path, 'does_not_exist'),
          languageCode: 'fr',
          outputPackPath: outputPackPath,
        );

        expect(result.isErr, isTrue);
        expect(
          previousPack.existsSync(),
          isTrue,
          reason: 'Failures before "pack create" must not touch the previous '
              'good pack',
        );
        expect(
          await previousPack.readAsString(),
          'previous good pack',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'returns Ok and keeps the pack file when every step succeeds',
      () async {
        await writeFakeRpfm(_allOkBat);

        final result = await packOps.createPack(
          inputDirectory: inputDir,
          languageCode: 'fr',
          outputPackPath: outputPackPath,
        );

        expect(result.isOk, isTrue, reason: 'Unexpected error: $result');
        expect(result.unwrap(), outputPackPath);
        expect(File(outputPackPath).existsSync(), isTrue);
      },
      skip: !Platform.isWindows,
    );
  });
}
