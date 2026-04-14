import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/shared/i_process_launcher.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/vdf_generator.dart';
import 'package:twmt/services/steam/workshop_publish_service_impl.dart';

// --- Mocks --------------------------------------------------------------

class _MockManager extends Mock implements SteamCmdManager {}

class _MockVdfGenerator extends Mock implements VdfGenerator {}

class _MockLauncher extends Mock implements IProcessLauncher {}

class _FakeLogger extends Fake implements ILoggingService {
  @override
  void debug(String m, [dynamic d]) {}
  @override
  void info(String m, [dynamic d]) {}
  @override
  void warning(String m, [dynamic d]) {}
  @override
  void error(String m, [dynamic e, StackTrace? s]) {}
}

// Fake Process exposing only members actually read by the service's
// _runSteamCmd: pid, exitCode, stdout, stderr, stdin (closed), and kill().
class _FakeProcess extends Fake implements Process {
  _FakeProcess({
    required this.pid,
    required Future<int> exitCodeFuture,
    required Stream<List<int>> stdoutStream,
    required Stream<List<int>> stderrStream,
  })  : _exitCode = exitCodeFuture,
        _stdout = stdoutStream,
        _stderr = stderrStream,
        _stdin = _NoopIOSink();

  final Future<int> _exitCode;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final IOSink _stdin;

  @override
  final int pid;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  IOSink get stdin => _stdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

// Minimal IOSink stub — the service only calls stdin.close().
class _NoopIOSink extends Fake implements IOSink {
  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();
}

// --- Helpers -----------------------------------------------------------

Stream<List<int>> _bytes(String s) => Stream<List<int>>.value(utf8.encode(s));

Stream<List<int>> _empty() => const Stream<List<int>>.empty();

_FakeProcess _okProcess({
  int exitCode = 0,
  String stdout = 'PublishFileID : 1234567890\nItem Updated\nSuccess.\n',
  String stderr = '',
}) {
  return _FakeProcess(
    pid: 4242,
    exitCodeFuture: Future<int>.value(exitCode),
    stdoutStream: _bytes(stdout),
    stderrStream: stderr.isEmpty ? _empty() : _bytes(stderr),
  );
}

WorkshopPublishParams _params({
  required String contentFolder,
  required String previewFile,
  String publishedFileId = '1234567890',
}) {
  return WorkshopPublishParams(
    appId: '1142710',
    publishedFileId: publishedFileId,
    contentFolder: contentFolder,
    previewFile: previewFile,
    title: 'Test Mod',
    description: 'desc',
    changeNote: 'note',
  );
}

void main() {
  // Required for mocktail `any()` on non-primitive matchers that appear in
  // argument positions.
  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(ProcessStartMode.normal);
    registerFallbackValue(const WorkshopPublishParams(
      appId: '0',
      publishedFileId: '0',
      contentFolder: '',
      previewFile: '',
      title: '',
      description: '',
    ));
  });

  late _MockManager manager;
  late _MockVdfGenerator vdf;
  late _MockLauncher launcher;
  late _FakeLogger logger;
  late WorkshopPublishServiceImpl service;

  // Real temp dir containing pack/preview files so the service's file I/O
  // succeeds. steamCmdDir inside this root has no config.vdf, so
  // _hasCachedCredentials returns false — this keeps the auth branch
  // deterministic (we always supply steamGuardCode in happy-path tests).
  late Directory tempRoot;
  late String steamCmdPath;
  late String packDir;
  late String previewPath;
  late String packPath;

  setUp(() {
    manager = _MockManager();
    vdf = _MockVdfGenerator();
    launcher = _MockLauncher();
    logger = _FakeLogger();

    tempRoot = Directory.systemTemp.createTempSync('twmt_publish_test_');
    // Simulated steamcmd install dir (no config/config.vdf → cached = false).
    final steamCmdDir = Directory(path.join(tempRoot.path, 'steamcmd'))
      ..createSync();
    steamCmdPath = path.join(steamCmdDir.path, 'steamcmd.exe');
    File(steamCmdPath).writeAsStringSync('fake');

    // Content folder with pack + preview. Preview name drives pack name:
    // "modname.png" → "modname.pack".
    packDir = path.join(tempRoot.path, 'content');
    Directory(packDir).createSync();
    previewPath = path.join(packDir, 'modname.png');
    packPath = path.join(packDir, 'modname.pack');
    File(previewPath).writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    File(packPath).writeAsBytesSync(const [0x50, 0x41, 0x43, 0x4B]);

    service = WorkshopPublishServiceImpl(
      manager: manager,
      vdfGenerator: vdf,
      processLauncher: launcher,
      logger: logger,
    );

    // Default manager stub: steamcmd path resolved.
    when(() => manager.getSteamCmdPath())
        .thenAnswer((_) async => Ok(steamCmdPath));
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  // --- Tests -----------------------------------------------------------

  test(
      'missing pack file → WorkshopPublishException returned before any '
      'steamcmd invocation', () async {
    // Arrange: point at a non-existent pack folder (no "modname.pack").
    final bogusDir = path.join(tempRoot.path, 'does_not_exist');

    // Act
    final result = await service.publish(
      params: _params(contentFolder: bogusDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );

    // Assert
    expect(result.isErr, true);
    expect(result.error, isA<WorkshopPublishException>());
    expect(result.error.message, contains('Pack file not found'));
    verifyNever(() => launcher.start(any(), any(),
        runInShell: any(named: 'runInShell')));
    verifyNever(() => vdf.generateVdf(any()));
  });

  test(
      'no cached credentials and no Steam Guard code → '
      'SteamGuardRequiredException, launcher never called', () async {
    // VDF generator is not stubbed because the service should return before
    // reaching it — but copyPack/previewFile paths DO need to succeed.
    // (Service generates VDF BEFORE the cached-creds check; so we must stub.)
    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));

    // Act
    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
    );

    // Assert
    expect(result.isErr, true);
    expect(result.error, isA<SteamGuardRequiredException>());
    verifyNever(() => launcher.start(any(), any(),
        runInShell: any(named: 'runInShell')));
    verify(() => vdf.generateVdf(any())).called(1);
  });

  test(
      'happy path (update with Steam Guard code) → publishes VDF, invokes '
      'steamcmd with expected args, returns Ok', () async {
    // Arrange
    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess());

    // Act
    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    // Assert
    expect(result.isOk, true, reason: 'got error: ${result.isErr ? result.error : ''}');
    expect(result.value, isA<WorkshopPublishResult>());
    expect(result.value.workshopId, '1234567890');
    expect(result.value.wasUpdate, isTrue);

    verify(() => vdf.generateVdf(any())).called(1);

    // Verify process launch: executable is steamCmdPath, args contain +login,
    // full-auth creds (user/pw/totp), +workshop_build_item <vdfPath>, +quit.
    final launchCapture = verify(() => launcher.start(
          captureAny(),
          captureAny(),
          runInShell: any(named: 'runInShell'),
        )).captured;
    expect(launchCapture, hasLength(2));
    expect(launchCapture[0], steamCmdPath);
    final args = launchCapture[1] as List<String>;
    expect(args.first, '+login');
    expect(args, contains('user'));
    expect(args, contains('pw'));
    expect(args, contains('54321'));
    expect(args, containsAllInOrder(
        ['+workshop_build_item', vdfPath, '+quit']));
  });

  test(
      'steamcmd output "Login Failure" → SteamAuthenticationException',
      () async {
    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'Logging in user...\nLogin Failure: Invalid Password\n',
            ));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );

    expect(result.isErr, true);
    expect(result.error, isA<SteamAuthenticationException>());
  });

  test(
      'steamcmd output "Failed to update workshop item" → '
      'WorkshopItemNotFoundException with workshopId', () async {
    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'Uploading content...\n'
                  'Failed to update workshop item (Item no longer exists).\n',
            ));

    final result = await service.publish(
      params: _params(
        contentFolder: packDir,
        previewFile: previewPath,
        publishedFileId: '9998887',
      ),
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );

    expect(result.isErr, true);
    expect(result.error, isA<WorkshopItemNotFoundException>());
    expect((result.error as WorkshopItemNotFoundException).workshopId,
        '9998887');
  });

  test('bad steamcmd exit code (not 0/6/7) → WorkshopPublishException',
      () async {
    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 3,
              // No recognized success/failure substrings — we want the
              // exit-code branch, not the auth or item-not-found branches.
              stdout: 'Some generic steamcmd output\n',
            ));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );

    expect(result.isErr, true);
    expect(result.error, isA<WorkshopPublishException>());
    expect(result.error.message, contains('exit'));
    expect(result.error.message, contains('3'));
  });

  test(
      'missing preview file → publish still proceeds (pack-only temp dir)',
      () async {
    // Delete the preview so previewFile.exists() == false at runtime, but
    // leave the pack in place (service derives pack name from preview path).
    File(previewPath).deleteSync();

    final vdfPath = path.join(tempRoot.path, 'publish.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any()))
        .thenAnswer((_) async => Ok(vdfPath));
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess());

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );

    expect(result.isOk, true,
        reason: 'got error: ${result.isErr ? result.error : ''}');
    // Launcher WAS called — the missing preview is silently skipped.
    verify(() => launcher.start(any(), any(),
        runInShell: any(named: 'runInShell'))).called(1);
  });
}
