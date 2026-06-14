// path_provider_platform_interface is a transitive dependency of
// path_provider; it is imported here only to stub directories in tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:twmt/services/file/file_watch_service.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Fake path provider exposing test-owned cache and temp directories.
///
/// Extends (not implements) PathProviderPlatform so the platform-interface
/// token verification passes.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.cachePath,
    required this.tempPath,
  });

  final String cachePath;
  final String tempPath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileWatchService service;
  late Directory tempDir;

  setUp(() async {
    service = FileWatchService();
    tempDir = await Directory.systemTemp.createTemp('file_watch_service_test_');
  });

  tearDown(() async {
    // The service is a process-wide singleton; clear any watchers/tracked
    // temp files it accumulated so tests stay isolated.
    await service.disposeAll();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String pathIn(String name) => p.join(tempDir.path, name);

  group('construction', () {
    test('factory returns the shared singleton', () {
      expect(identical(FileWatchService(), service), isTrue);
    });
  });

  group('watchFile registration', () {
    test('throws FileWatchException for a non-existent path', () {
      expect(
        () => service.watchFile(path: pathIn('does_not_exist')).first,
        throwsA(isA<FileWatchException>()),
      );
    });

    test('registers a directory watcher and emits a create event', () async {
      final stream = service.watchFile(path: tempDir.path);

      // Subscribe and give the watcher time to reach its ready state before
      // mutating the filesystem.
      final events = <FileChangeEvent>[];
      final sub = stream.listen(events.add);
      addTearDown(sub.cancel);
      await _settle();

      final created = File(pathIn('created.txt'));
      await created.writeAsString('hello');

      await _waitFor(() => events.any(
            (e) => e.type == FileChangeType.created &&
                p.equals(e.path, created.path),
          ));

      final match = events.firstWhere(
        (e) => p.equals(e.path, created.path),
      );
      expect(match.type, FileChangeType.created);
      expect(match.timestamp, isA<DateTime>());
    });

    test('emits a modify event when a watched file changes', () async {
      final target = File(pathIn('mod.txt'));
      await target.writeAsString('one');

      final events = <FileChangeEvent>[];
      final sub = service.watchFile(path: tempDir.path).listen(events.add);
      addTearDown(sub.cancel);
      await _settle();

      await target.writeAsString('two');

      await _waitFor(() => events.any(
            (e) => e.type == FileChangeType.modified &&
                p.equals(e.path, target.path),
          ));
    });

    test('emits a delete event when a watched file is removed', () async {
      final target = File(pathIn('del.txt'));
      await target.writeAsString('bye');

      final events = <FileChangeEvent>[];
      final sub = service.watchFile(path: tempDir.path).listen(events.add);
      addTearDown(sub.cancel);
      await _settle();

      await target.delete();

      await _waitFor(() => events.any(
            (e) => e.type == FileChangeType.deleted &&
                p.equals(e.path, target.path),
          ));
    });

    test('a second watchFile on the same path reuses the existing stream',
        () async {
      final eventsA = <FileChangeEvent>[];
      final subA = service.watchFile(path: tempDir.path).listen(eventsA.add);
      addTearDown(subA.cancel);
      await _settle();

      final eventsB = <FileChangeEvent>[];
      final subB = service.watchFile(path: tempDir.path).listen(eventsB.add);
      addTearDown(subB.cancel);
      await _settle();

      await File(pathIn('shared.txt')).writeAsString('x');

      await _waitFor(() => eventsA.isNotEmpty && eventsB.isNotEmpty);
    });

    test('watching a single file filters out events for sibling files',
        () async {
      final watched = File(pathIn('watched.txt'));
      await watched.writeAsString('w');
      final other = File(pathIn('other.txt'));
      await other.writeAsString('o');

      final events = <FileChangeEvent>[];
      final sub = service.watchFile(path: watched.path).listen(events.add);
      addTearDown(sub.cancel);
      await _settle();

      // Mutating the sibling should produce no events for the watched file.
      await other.writeAsString('o-changed');
      // Mutating the watched file should produce an event.
      await watched.writeAsString('w-changed');

      await _waitFor(
        () => events.any((e) => p.equals(e.path, watched.path)),
      );
      expect(
        events.every((e) => p.equals(e.path, watched.path)),
        isTrue,
        reason: 'sibling events must be filtered out',
      );
    });
  });

  group('stopWatching / disposeAll', () {
    test('stopWatching on an unwatched path is a no-op', () async {
      await service.stopWatching(path: pathIn('never_watched'));
    });

    test('stopWatching closes an active watcher', () async {
      final sub = service.watchFile(path: tempDir.path).listen((_) {});
      addTearDown(sub.cancel);
      await _settle();

      await service.stopWatching(path: tempDir.path);

      // Stopping again is harmless (already removed from the map).
      await service.stopWatching(path: tempDir.path);
    });

    test('cancelling the only listener triggers onCancel cleanup', () async {
      final sub = service.watchFile(path: tempDir.path).listen((_) {});
      await _settle();

      await sub.cancel();
      // Allow the broadcast controller onCancel callback to run.
      await _settle();

      // A fresh watch should succeed (i.e. the prior watcher was cleaned up).
      final sub2 = service.watchFile(path: tempDir.path).listen((_) {});
      addTearDown(sub2.cancel);
      await _settle();
    });

    test('disposeAll stops every watcher and deletes tracked temp files',
        () async {
      final sub = service.watchFile(path: tempDir.path).listen((_) {});
      addTearDown(sub.cancel);
      await _settle();

      final created = await service.createTempFile(autoDelete: true);
      final tempPath = created.value;
      expect(await File(tempPath).exists(), isTrue);

      await service.disposeAll();

      // Tracked temp file is removed and watchers are torn down.
      expect(await File(tempPath).exists(), isFalse);
      // disposeAll again is safe with nothing tracked.
      await service.disposeAll();
    });
  });

  group('createTempFile', () {
    test('creates a temp file without tracking when autoDelete is false',
        () async {
      final result = await service.createTempFile();
      expect(result.isOk, isTrue);

      final path = result.value;
      expect(await File(path).exists(), isTrue);
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });

      // Not tracked -> disposeAll must not delete it.
      await service.disposeAll();
      expect(await File(path).exists(), isTrue);
    });

    test('honours prefix and suffix', () async {
      final result = await service.createTempFile(
        prefix: 'twmt_temp',
        suffix: '.temp',
        autoDelete: true,
      );
      final path = result.value;
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });

      final name = p.basename(path);
      expect(name.startsWith('twmt_temp_'), isTrue);
      expect(name.endsWith('.temp'), isTrue);
    });
  });

  group('cleanupTempFiles', () {
    test('returns Ok(0) when the target directory does not exist', () async {
      final missing = p.join(tempDir.path, 'nope');
      final result = await service.cleanupTempFiles(tempDirectory: missing);
      expect(result.isOk, isTrue);
      expect(result.value, 0);
    });

    test('deletes old temp-pattern files and skips fresh / non-temp ones',
        () async {
      final old = DateTime.now().subtract(const Duration(days: 30));

      // Old temp file (matches pattern, old enough) -> deleted.
      final oldTemp = File(pathIn('tmp_old.tmp'));
      await oldTemp.writeAsString('x');
      await oldTemp.setLastModified(old);

      // Old non-temp file -> not deleted (pattern mismatch).
      final oldOther = File(pathIn('keep_old.txt'));
      await oldOther.writeAsString('x');
      await oldOther.setLastModified(old);

      // Fresh temp file -> not deleted (too recent).
      final freshTemp = File(pathIn('tmp_fresh.tmp'));
      await freshTemp.writeAsString('x');

      final result = await service.cleanupTempFiles(
        olderThan: const Duration(days: 7),
        tempDirectory: tempDir.path,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 1);
      expect(await oldTemp.exists(), isFalse);
      expect(await oldOther.exists(), isTrue);
      expect(await freshTemp.exists(), isTrue);
    });

    test('matches the *.temp and twmt_temp_ patterns too', () async {
      final old = DateTime.now().subtract(const Duration(days: 30));

      final dotTemp = File(pathIn('archive.temp'));
      await dotTemp.writeAsString('x');
      await dotTemp.setLastModified(old);

      final twmtTemp = File(pathIn('twmt_temp_data.bin'));
      await twmtTemp.writeAsString('x');
      await twmtTemp.setLastModified(old);

      final result = await service.cleanupTempFiles(
        olderThan: const Duration(days: 7),
        tempDirectory: tempDir.path,
      );

      expect(result.value, 2);
      expect(await dotTemp.exists(), isFalse);
      expect(await twmtTemp.exists(), isFalse);
    });

    test('treats a non-existent file path as an empty directory', () async {
      // Directory(filePath).exists() is false for a regular file, so cleanup
      // short-circuits to Ok(0) without listing.
      final file = File(pathIn('not_a_dir.txt'));
      await file.writeAsString('x');

      final result = await service.cleanupTempFiles(tempDirectory: file.path);
      expect(result.isOk, isTrue);
      expect(result.value, 0);
    });
  });

  group('compareFiles', () {
    test('reports identical content', () async {
      final a = File(pathIn('a.bin'));
      final b = File(pathIn('b.bin'));
      await a.writeAsBytes([1, 2, 3]);
      await b.writeAsBytes([1, 2, 3]);

      final result =
          await service.compareFiles(filePath1: a.path, filePath2: b.path);
      expect(result.value, isTrue);
    });

    test('reports differing content of equal length', () async {
      final a = File(pathIn('a.bin'));
      final b = File(pathIn('b.bin'));
      await a.writeAsBytes([1, 2, 3]);
      await b.writeAsBytes([1, 2, 4]);

      final result =
          await service.compareFiles(filePath1: a.path, filePath2: b.path);
      expect(result.value, isFalse);
    });

    test('reports differing length as not equal', () async {
      final a = File(pathIn('a.bin'));
      final b = File(pathIn('b.bin'));
      await a.writeAsBytes([1, 2, 3]);
      await b.writeAsBytes([1, 2]);

      final result =
          await service.compareFiles(filePath1: a.path, filePath2: b.path);
      expect(result.value, isFalse);
    });

    test('metadata-only comparison uses size and modified time', () async {
      final a = File(pathIn('a.bin'));
      final b = File(pathIn('b.bin'));
      await a.writeAsBytes([1, 2, 3]);
      await b.writeAsBytes([9, 9, 9]);
      final ts = DateTime.now().subtract(const Duration(minutes: 5));
      await a.setLastModified(ts);
      await b.setLastModified(ts);

      final result = await service.compareFiles(
        filePath1: a.path,
        filePath2: b.path,
        compareContent: false,
      );
      // Same size and modified time => considered identical by metadata.
      expect(result.value, isTrue);
    });

    test('returns FileNotFoundException when the first file is missing',
        () async {
      final b = File(pathIn('b.bin'));
      await b.writeAsBytes([1]);

      final result = await service.compareFiles(
        filePath1: pathIn('missing_a.bin'),
        filePath2: b.path,
      );
      expect(result.error, isA<FileNotFoundException>());
    });

    test('returns FileNotFoundException when the second file is missing',
        () async {
      final a = File(pathIn('a.bin'));
      await a.writeAsBytes([1]);

      final result = await service.compareFiles(
        filePath1: a.path,
        filePath2: pathIn('missing_b.bin'),
      );
      expect(result.error, isA<FileNotFoundException>());
    });
  });

  group('directory getters (path_provider backed)', () {
    late Directory root;
    late String cacheBase;
    late String redirectedTemp;
    late PathProviderPlatform original;

    setUp(() async {
      original = PathProviderPlatform.instance;
      root = await Directory.systemTemp.createTemp('file_watch_paths_test_');
      cacheBase = p.join(root.path, 'AppCache');
      redirectedTemp = p.join(root.path, 'RedirectedTemp');
      await Directory(cacheBase).create(recursive: true);
      await Directory(redirectedTemp).create(recursive: true);

      PathProviderPlatform.instance = _FakePathProviderPlatform(
        cachePath: cacheBase,
        tempPath: redirectedTemp,
      );
    });

    tearDown(() async {
      PathProviderPlatform.instance = original;
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('getLogsDirectory creates and returns the logs dir', () async {
      final logsDir = await service.getLogsDirectory();
      expect(logsDir, p.join(cacheBase, 'logs'));
      expect(await Directory(logsDir).exists(), isTrue);
    });

    test('getCacheDirectory creates and returns the cache dir', () async {
      final cacheDir = await service.getCacheDirectory();
      expect(cacheDir, p.join(cacheBase, 'cache'));
      expect(await Directory(cacheDir).exists(), isTrue);
    });

    test('getTempDirectory returns an existing directory', () async {
      final temp = await service.getTempDirectory();
      expect(await Directory(temp).exists(), isTrue);
    });
  });
}

/// Lets the platform file watcher reach its ready/poll state and lets pending
/// microtasks/timers flush.
Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

/// Polls [condition] until it is true or a timeout elapses. File watcher
/// delivery is asynchronous and (on some platforms) poll-based, so this avoids
/// hard-coding a single sleep duration.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(step);
  }
}
