import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/events/activity_event.dart';
import 'package:twmt/services/shared/i_process_launcher.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/vdf_generator.dart';
import 'package:twmt/services/steam/workshop_publish_service_impl.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/fakes/fake_process.dart';

// --- Mocks --------------------------------------------------------------

class _MockManager extends Mock implements SteamCmdManager {}

class _MockVdfGenerator extends Mock implements VdfGenerator {}

class _MockLauncher extends Mock implements IProcessLauncher {}

/// Records every activity event logged so tests can assert the
/// projectPublished side-effect fires on the success paths.
class _RecordingActivityLogger implements ActivityLogger {
  final List<({ActivityEventType type, Map<String, dynamic> payload})> events =
      [];

  @override
  Future<void> log(
    ActivityEventType type, {
    String? projectId,
    String? gameCode,
    Map<String, dynamic> payload = const {},
  }) async {
    events.add((type: type, payload: payload));
  }
}

// --- Helpers -----------------------------------------------------------

Stream<List<int>> _bytes(String s) => Stream<List<int>>.value(utf8.encode(s));

Stream<List<int>> _empty() => const Stream<List<int>>.empty();

FakeProcess _okProcess({
  int exitCode = 0,
  String stdout = 'PublishFileID : 1234567890\nItem Updated\nSuccess.\n',
  String stderr = '',
}) {
  return FakeProcess(
    pid: 4242,
    exitCodeFuture: Future<int>.value(exitCode),
    stdoutStream: _bytes(stdout),
    stderrStream: stderr.isEmpty ? _empty() : _bytes(stderr),
  );
}

/// Fake process the test drives line-by-line; exit only resolves when the
/// test (or a kill) completes it.
class _ScriptableFakeProcess extends FakeProcess {
  _ScriptableFakeProcess({
    required StreamController<List<int>> stdoutController,
    required Completer<int> exitCompleter,
  })  : _stdoutController = stdoutController,
        _exitCompleter = exitCompleter,
        super(
          pid: 4250,
          exitCodeFuture: exitCompleter.future,
          stdoutStream: stdoutController.stream,
          stderrStream: const Stream<List<int>>.empty(),
        );

  final StreamController<List<int>> _stdoutController;
  final Completer<int> _exitCompleter;
  bool wasKilled = false;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(-1);
    if (!_stdoutController.isClosed) _stdoutController.close();
    return true;
  }
}

WorkshopPublishParams _params({
  required String contentFolder,
  required String previewFile,
  String publishedFileId = '1234567890',
  String title = 'Test Mod',
}) {
  return WorkshopPublishParams(
    appId: '1142710',
    publishedFileId: publishedFileId,
    contentFolder: contentFolder,
    previewFile: previewFile,
    title: title,
    description: 'desc',
    changeNote: 'note',
  );
}

void main() {
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
  late FakeLogger logger;
  late _RecordingActivityLogger activity;
  late WorkshopPublishServiceImpl service;

  late Directory tempRoot;
  late String steamCmdPath;
  late String packDir;
  late String previewPath;
  late String packPath;

  /// Builds a `<contentFolder>/<name>.pack` + `<name>.png` pair and returns
  /// (packDir, previewPath) for a second batch item.
  ({String packDir, String previewPath}) makeItem(String name) {
    final dir = path.join(tempRoot.path, 'content_$name');
    Directory(dir).createSync();
    final preview = path.join(dir, '$name.png');
    final pack = path.join(dir, '$name.pack');
    File(preview).writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    File(pack).writeAsBytesSync(const [0x50, 0x41, 0x43, 0x4B]);
    return (packDir: dir, previewPath: preview);
  }

  void stubVdf() {
    final vdfPath = path.join(
        tempRoot.path, 'publish_${DateTime.now().microsecondsSinceEpoch}.vdf');
    File(vdfPath).writeAsStringSync('// stub vdf');
    when(() => vdf.generateVdf(any())).thenAnswer((_) async => Ok(vdfPath));
  }

  /// Seeds config/config.vdf so _hasCachedCredentials('user') == true.
  void seedCachedCreds({String username = 'user'}) {
    final configDir = Directory(path.join(path.dirname(steamCmdPath), 'config'));
    if (!configDir.existsSync()) configDir.createSync(recursive: true);
    File(path.join(configDir.path, 'config.vdf')).writeAsStringSync(
      '"InstallConfigStore"\n{\n  "ConnectCache"\n  {\n'
      '    "$username" "deadbeef"\n  }\n}\n',
    );
  }

  setUp(() {
    manager = _MockManager();
    vdf = _MockVdfGenerator();
    launcher = _MockLauncher();
    logger = FakeLogger();
    activity = _RecordingActivityLogger();

    tempRoot = Directory.systemTemp.createTempSync('twmt_publish_cov_');
    final steamCmdDir = Directory(path.join(tempRoot.path, 'steamcmd'))
      ..createSync();
    steamCmdPath = path.join(steamCmdDir.path, 'steamcmd.exe');
    File(steamCmdPath).writeAsStringSync('fake');

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
      activityLogger: activity,
    );

    when(() => manager.getSteamCmdPath())
        .thenAnswer((_) async => Ok(steamCmdPath));
  });

  tearDown(() {
    try {
      service.dispose();
    } catch (_) {}
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  // --- progress / output streams + lifecycle getters -------------------

  test('progressStream and outputStream are broadcast streams', () {
    expect(service.progressStream, isA<Stream<double>>());
    expect(service.outputStream, isA<Stream<String>>());
  });

  test('submitSteamGuardCode is a no-op (stdin closed) — logs and returns',
      () {
    // Covers the warning-only no-op body; must not throw.
    expect(() => service.submitSteamGuardCode('123456'), returnsNormally);
  });

  test('cancel() with no active process is a no-op and sets cancelled flag',
      () async {
    await service.cancel();
    // A second cancel is still safe.
    await service.cancel();
  });

  test('isAvailable() delegates to the manager', () async {
    when(() => manager.isAvailable()).thenAnswer((_) async => true);
    expect(await service.isAvailable(), isTrue);
    verify(() => manager.isAvailable()).called(1);

    when(() => manager.isAvailable()).thenAnswer((_) async => false);
    expect(await service.isAvailable(), isFalse);
  });

  // --- single publish: success side-effects + workshopId fallback ------

  test(
      'happy path logs a projectPublished activity event with title + '
      'workshopId payload', () async {
    stubVdf();
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess());

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    expect(result.isOk, isTrue,
        reason: 'got error: ${result.isErr ? result.error : ''}');
    expect(activity.events, hasLength(1));
    expect(activity.events.single.type, ActivityEventType.projectPublished);
    expect(activity.events.single.payload['workshopId'], '1234567890');
    expect(activity.events.single.payload['projectName'], 'Test Mod');
  });

  test(
      'success WITHOUT a PublishFileID in output falls back to '
      'params.publishedFileId', () async {
    stubVdf();
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              // No PublishFileID line → run.workshopId is null → fallback.
              stdout: 'Item Updated\nSuccess.\n',
            ));

    final result = await service.publish(
      params: _params(
        contentFolder: packDir,
        previewFile: previewPath,
        publishedFileId: '5550001',
      ),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    expect(result.isOk, isTrue,
        reason: 'got error: ${result.isErr ? result.error : ''}');
    expect(result.value.workshopId, '5550001');
  });

  test('stderr output is forwarded to the output stream as [stderr] lines',
      () async {
    stubVdf();
    final outputs = <String>[];
    final sub = service.outputStream.listen(outputs.add);
    addTearDown(sub.cancel);

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              stdout: 'PublishFileID : 42\nSuccess.\n',
              stderr: 'a warning from steamcmd\n',
            ));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    expect(result.isOk, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(outputs.any((o) => o.contains('[stderr]')), isTrue);
  });

  test('progress percentage in output drives the progress stream', () async {
    stubVdf();
    final progresses = <double>[];
    final sub = service.progressStream.listen(progresses.add);
    addTearDown(sub.cancel);

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              stdout: 'Uploading 50%\nPublishFileID : 7\nSuccess.\n',
            ));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    expect(result.isOk, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 0.05 + 0.5 * 0.90 == 0.5 must have been emitted by _tryExtractProgress.
    expect(progresses.any((p) => (p - 0.5).abs() < 1e-9), isTrue);
  });

  // --- re-entrance guards ----------------------------------------------

  test('publish() while a publish is already running → returns Err', () async {
    stubVdf();
    final stdoutController = StreamController<List<int>>();
    final exitCompleter = Completer<int>();
    final blocking = _ScriptableFakeProcess(
      stdoutController: stdoutController,
      exitCompleter: exitCompleter,
    );
    when(() => launcher.start(any(), any(),
        runInShell: any(named: 'runInShell'))).thenAnswer((_) async => blocking);

    // First publish never completes until we resolve the completer.
    final first = service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );
    // Give the first call time to set _isRunning and reach the process await.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final second = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );
    expect(second.isErr, isTrue);
    expect(second.error, isA<WorkshopPublishException>());
    expect(second.error.message, contains('already in progress'));

    // Let the first finish so teardown is clean.
    stdoutController.add(utf8.encode('PublishFileID : 1\nSuccess.\n'));
    await stdoutController.close();
    if (!exitCompleter.isCompleted) exitCompleter.complete(0);
    await first;
  });

  test('publishBatch() while running → throws WorkshopPublishException',
      () async {
    stubVdf();
    final stdoutController = StreamController<List<int>>();
    final exitCompleter = Completer<int>();
    final blocking = _ScriptableFakeProcess(
      stdoutController: stdoutController,
      exitCompleter: exitCompleter,
    );
    when(() => launcher.start(any(), any(),
        runInShell: any(named: 'runInShell'))).thenAnswer((_) async => blocking);

    final first = service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await expectLater(
      service.publishBatch(
        items: [
          (name: 'x', params: _params(contentFolder: packDir, previewFile: previewPath)),
        ],
        username: 'user',
        password: 'pw',
        steamGuardCode: '54321',
      ),
      throwsA(isA<WorkshopPublishException>()),
    );

    stdoutController.add(utf8.encode('PublishFileID : 1\nSuccess.\n'));
    await stdoutController.close();
    if (!exitCompleter.isCompleted) exitCompleter.complete(0);
    await first;
  });

  // --- stale-cache reauth path -----------------------------------------

  test(
      'cached login + Login Failure → stale cache invalidated, '
      'SteamGuardRequiredException, ssfn/config files deleted', () async {
    seedCachedCreds();
    // Drop an ssfn sentry file next to steamcmd so the invalidation loop
    // (best-effort per-file delete) runs over a real file.
    final ssfn = File(path.join(path.dirname(steamCmdPath), 'ssfn123456'));
    ssfn.writeAsStringSync('sentry');
    final configFile =
        File(path.join(path.dirname(steamCmdPath), 'config', 'config.vdf'));
    expect(configFile.existsSync(), isTrue);

    stubVdf();
    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'Logging in user...\nFAILED login with result Login Failure\n',
            ));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: null, // cached path is taken; no code needed
    );

    expect(result.isErr, isTrue);
    expect(result.error, isA<SteamGuardRequiredException>());
    expect(result.error.message, contains('expired'));
    // Invalidation deleted both the config.vdf and the ssfn sentry.
    expect(configFile.existsSync(), isFalse);
    expect(ssfn.existsSync(), isFalse);
  });

  // --- cached-credentials probe branches -------------------------------

  test(
      'config.vdf present but WITHOUT ConnectCache → not cached, Steam Guard '
      'required when no code supplied', () async {
    final configDir =
        Directory(path.join(path.dirname(steamCmdPath), 'config'))
          ..createSync(recursive: true);
    File(path.join(configDir.path, 'config.vdf'))
        .writeAsStringSync('"InstallConfigStore" { "user" "x" }');
    stubVdf();

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
    );

    expect(result.isErr, isTrue);
    expect(result.error, isA<SteamGuardRequiredException>());
  });

  test(
      'config.vdf has ConnectCache but no quoted entry for this user → not '
      'cached, Steam Guard required', () async {
    final configDir =
        Directory(path.join(path.dirname(steamCmdPath), 'config'))
          ..createSync(recursive: true);
    File(path.join(configDir.path, 'config.vdf')).writeAsStringSync(
      '"ConnectCache" { "someoneelse" "deadbeef" }',
    );
    stubVdf();

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
    );

    expect(result.isErr, isTrue);
    expect(result.error, isA<SteamGuardRequiredException>());
  });

  // --- exception-in-try → catch block ----------------------------------

  test('unexpected error inside publish → caught and wrapped', () async {
    // generateVdf throwing (not returning Err) exercises the outer catch.
    when(() => vdf.generateVdf(any())).thenThrow(StateError('boom'));

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: '54321',
    );

    expect(result.isErr, isTrue);
    expect(result.error, isA<WorkshopPublishException>());
    expect(result.error.message, contains('Publish failed'));
  });

  // --- publishBatch pre-flight + preparation branches ------------------

  test('publishBatch: getSteamCmdPath Err → onItemComplete never fires, '
      'no throw escapes (error rethrown is caught? )', () async {
    when(() => manager.getSteamCmdPath()).thenAnswer(
        (_) async => Err(const SteamCmdNotFoundException('missing')));

    await expectLater(
      service.publishBatch(
        items: [
          (name: 'x', params: _params(contentFolder: packDir, previewFile: previewPath)),
        ],
        username: 'user',
        password: 'pw',
        steamGuardCode: '12345',
      ),
      throwsA(isA<SteamCmdNotFoundException>()),
    );
  });

  test('publishBatch: no cached creds and no code → throws Steam Guard',
      () async {
    await expectLater(
      service.publishBatch(
        items: [
          (name: 'x', params: _params(contentFolder: packDir, previewFile: previewPath)),
        ],
        username: 'user',
        password: 'pw',
        steamGuardCode: null,
      ),
      throwsA(isA<SteamGuardRequiredException>()),
    );
  });

  test(
      'publishBatch: missing pack file for an item → that item completes with '
      'WorkshopPublishException and is skipped', () async {
    final results =
        <Result<WorkshopPublishResult, SteamServiceException>>[];
    // Single item whose pack doesn't exist → prepared is empty → early return.
    await service.publishBatch(
      items: [
        (
          name: 'ghost',
          params: _params(
            contentFolder: path.join(tempRoot.path, 'nope'),
            previewFile: previewPath,
          ),
        ),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
      onItemComplete: (i, r) => results.add(r),
    );

    expect(results, hasLength(1));
    expect(results.single.isErr, isTrue);
    expect(results.single.error, isA<WorkshopPublishException>());
    expect(results.single.error.message, contains('Pack file not found'));
  });

  test('publishBatch: VDF generation Err for an item → that item errs',
      () async {
    when(() => vdf.generateVdf(any())).thenAnswer(
        (_) async => Err(const VdfGenerationException('vdf bad')));

    final results =
        <Result<WorkshopPublishResult, SteamServiceException>>[];
    await service.publishBatch(
      items: [
        (name: 'm', params: _params(contentFolder: packDir, previewFile: previewPath)),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
      onItemComplete: (i, r) => results.add(r),
    );

    expect(results, hasLength(1));
    expect(results.single.isErr, isTrue);
    expect(results.single.error, isA<VdfGenerationException>());
  });

  test('publishBatch: preparation throws (preview path with no extension) → '
      'item completes with preparation-failed error', () async {
    // previewFile with no '.' → previewName.lastIndexOf('.') == -1 →
    // substring(0,-1) throws RangeError, caught by the per-item try.
    final badDir = path.join(tempRoot.path, 'badprep');
    Directory(badDir).createSync();
    File(path.join(badDir, 'noextfile')).writeAsBytesSync(const [1, 2]);

    final results =
        <Result<WorkshopPublishResult, SteamServiceException>>[];
    await service.publishBatch(
      items: [
        (
          name: 'NoExt',
          params: _params(
            contentFolder: badDir,
            previewFile: path.join(badDir, 'noextfile'),
          ),
        ),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
      onItemComplete: (i, r) => results.add(r),
    );

    expect(results, hasLength(1));
    expect(results.single.isErr, isTrue);
    expect(results.single.error.message, contains('Preparation failed'));
  });

  // --- publishBatch streaming parser (cached login branch) -------------

  test(
      'publishBatch with cached creds: two items succeed via streaming '
      'parser; +login omits password; activity events logged', () async {
    seedCachedCreds();
    stubVdf();

    final second = makeItem('modtwo');

    final stdoutController = StreamController<List<int>>();
    final exitCompleter = Completer<int>();
    final process = _ScriptableFakeProcess(
      stdoutController: stdoutController,
      exitCompleter: exitCompleter,
    );

    List<String>? capturedArgs;
    when(() => launcher.start(any(), captureAny(),
        runInShell: any(named: 'runInShell'))).thenAnswer((inv) async {
      capturedArgs =
          (inv.positionalArguments[1] as List).cast<String>();
      unawaited(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        stdoutController.add(utf8.encode('Uploading 10%\n'));
        // Item 0: PublishFileID line both records the id AND (because
        // currentWorkshopId is now set) triggers completion for item 0.
        stdoutController.add(utf8.encode('PublishFileID : 111\n'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Item 1: same shape — id recorded then completion fires.
        stdoutController.add(utf8.encode('PublishFileID : 222\n'));
        await stdoutController.close();
        if (!exitCompleter.isCompleted) exitCompleter.complete(0);
      }());
      return process;
    });

    final results =
        <int, Result<WorkshopPublishResult, SteamServiceException>>{};
    final started = <int>[];
    final progress = <int, double>{};
    await service.publishBatch(
      items: [
        (name: 'One', params: _params(contentFolder: packDir, previewFile: previewPath, publishedFileId: '0')),
        (name: 'Two', params: _params(contentFolder: second.packDir, previewFile: second.previewPath, publishedFileId: '0')),
      ],
      username: 'user',
      password: 'shouldNotLeak',
      steamGuardCode: null,
      onItemStart: (i, name) => started.add(i),
      onItemProgress: (i, p) => progress[i] = p,
      onItemComplete: (i, r) => results[i] = r,
    );

    expect(results.length, 2);
    expect(results[0]!.isOk, isTrue);
    expect(results[0]!.value.workshopId, '111');
    expect(results[1]!.isOk, isTrue);
    expect(results[1]!.value.workshopId, '222');
    // onItemStart fired for both items (first up front, second after item 0).
    expect(started, containsAll([0, 1]));
    // Progress callback fired.
    expect(progress.containsKey(0), isTrue);
    // Cached path: password must not be in the args.
    expect(capturedArgs, isNotNull);
    expect(capturedArgs, isNot(contains('shouldNotLeak')));
    // Two activity events recorded.
    expect(activity.events, hasLength(2));
  });

  test(
      'publishBatch: generic "ERROR!" line (no Login, not yet completed) → '
      'item errs with steamcmd error', () async {
    seedCachedCreds();
    stubVdf();

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'Doing work...\nERROR! Something exploded\n',
            ));

    final results =
        <Result<WorkshopPublishResult, SteamServiceException>>[];
    await service.publishBatch(
      items: [
        (name: 'm', params: _params(contentFolder: packDir, previewFile: previewPath)),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
      onItemComplete: (i, r) => results.add(r),
    );

    expect(results, hasLength(1));
    expect(results.single.isErr, isTrue);
    expect(results.single.error, isA<WorkshopPublishException>());
    expect(results.single.error.message, contains('steamcmd error'));
  });

  test('publishBatch: Login Failure → all items fail with auth error',
      () async {
    seedCachedCreds();
    stubVdf();

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'Logging in...\nLogin Failure: Invalid Password\n',
            ));

    final results =
        <Result<WorkshopPublishResult, SteamServiceException>>[];
    await service.publishBatch(
      items: [
        (name: 'm', params: _params(contentFolder: packDir, previewFile: previewPath)),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
      onItemComplete: (i, r) => results.add(r),
    );

    expect(results, hasLength(1));
    expect(results.single.isErr, isTrue);
    expect(results.single.error, isA<SteamAuthenticationException>());
  });

  test('publishBatch: stderr lines are forwarded to the output stream',
      () async {
    seedCachedCreds();
    stubVdf();

    final outputs = <String>[];
    final sub = service.outputStream.listen(outputs.add);
    addTearDown(sub.cancel);

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'PublishFileID : 9\nItem Updated\nSuccess.\n',
              stderr: 'batch stderr warning\n',
            ));

    await service.publishBatch(
      items: [
        (name: 'm', params: _params(contentFolder: packDir, previewFile: previewPath)),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
      onItemComplete: (_, _) {},
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(outputs.any((o) => o.contains('[stderr]')), isTrue);
  });

  test(
      'publishBatch: item 0 fails (update failure) then item 1 succeeds via '
      'a bare Success line → next-item start fires, fallback id used',
      () async {
    seedCachedCreds();
    stubVdf();

    final second = makeItem('modb');

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              // Item 0: update-failure line. Item 1: a bare "Success." with
              // NO PublishFileID → fallback to params.publishedFileId (line 659).
              stdout: 'ERROR! Failed to update workshop item (Timeout).\n'
                  'Success.\n',
            ));

    final results =
        <int, Result<WorkshopPublishResult, SteamServiceException>>{};
    final started = <int>[];
    await service.publishBatch(
      items: [
        (name: 'A', params: _params(contentFolder: packDir, previewFile: previewPath, publishedFileId: '0')),
        (name: 'B', params: _params(contentFolder: second.packDir, previewFile: second.previewPath, publishedFileId: '7654321')),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
      onItemStart: (i, name) => started.add(i),
      onItemComplete: (i, r) => results[i] = r,
    );

    expect(results[0]!.isErr, isTrue);
    expect(results[0]!.error, isA<WorkshopPublishException>());
    expect(results[1]!.isOk, isTrue,
        reason: 'got error: ${results[1]!.isErr ? results[1]!.error : ''}');
    // Bare success fell back to the item's publishedFileId.
    expect(results[1]!.value.workshopId, '7654321');
    // onItemStart fired for the second item after the first failed.
    expect(started, containsAll([0, 1]));
  });

  test(
      'publishBatch: item 0 generic ERROR! then item 1 succeeds → next-item '
      'start after generic error path', () async {
    seedCachedCreds();
    stubVdf();

    final second = makeItem('modc');

    when(() => launcher.start(any(), any(),
            runInShell: any(named: 'runInShell')))
        .thenAnswer((_) async => _okProcess(
              exitCode: 0,
              stdout: 'ERROR! generic failure for item zero\n'
                  'PublishFileID : 999\n',
            ));

    final results =
        <int, Result<WorkshopPublishResult, SteamServiceException>>{};
    final started = <int>[];
    await service.publishBatch(
      items: [
        (name: 'A', params: _params(contentFolder: packDir, previewFile: previewPath, publishedFileId: '0')),
        (name: 'B', params: _params(contentFolder: second.packDir, previewFile: second.previewPath, publishedFileId: '0')),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
      onItemStart: (i, name) => started.add(i),
      onItemComplete: (i, r) => results[i] = r,
    );

    expect(results[0]!.isErr, isTrue);
    expect(results[0]!.error.message, contains('steamcmd error'));
    expect(results[1]!.isOk, isTrue);
    expect(results[1]!.value.workshopId, '999');
    expect(started, containsAll([0, 1]));
  });

  test(
      'cached-credentials probe swallows read errors (config.vdf is a '
      'directory) → falls back to needing Steam Guard', () async {
    // Make config/config.vdf a DIRECTORY so readAsString throws inside the
    // try, hitting the catch that returns false (best-effort probe).
    final cfgDir = Directory(
        path.join(path.dirname(steamCmdPath), 'config', 'config.vdf'))
      ..createSync(recursive: true);
    expect(cfgDir.existsSync(), isTrue);
    stubVdf();

    final result = await service.publish(
      params: _params(contentFolder: packDir, previewFile: previewPath),
      username: 'user',
      password: 'pw',
      steamGuardCode: null,
    );

    expect(result.isErr, isTrue);
    expect(result.error, isA<SteamGuardRequiredException>());
  });

  test('dispose() is idempotent (safe to call twice)', () {
    service.dispose();
    expect(() => service.dispose(), returnsNormally);
  });
}
