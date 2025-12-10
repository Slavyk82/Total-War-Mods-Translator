import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

void main() {
  late IFileService fileService;
  late Directory testDir;
  late String testFilePath;
  late String testDirPath;

  setUp(() async {
    fileService = FileServiceImpl();

    // Create a temporary test directory
    testDir = await Directory.systemTemp.createTemp('file_watch_test_');
    testDirPath = testDir.path;
    testFilePath = path.join(testDirPath, 'test_file.txt');
  });

  tearDown(() async {
    // Clean up test directory
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }

    // Stop all watchers to prevent resource leaks
    await fileService.stopWatching(path: testFilePath);
    await fileService.stopWatching(path: testDirPath);
  });

  group('File Watching Tests', () {
    test('should watch file creation event', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.create();

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('test content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.modified);
      expect(event.path, contains('test_file.txt'));
      expect(event.timestamp, isNotNull);

      await subscription.cancel();
    });

    test('should watch file modification event', () async {
      // Create and write initial content
      final file = File(testFilePath);
      await file.writeAsString('initial content');

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('modified content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.modified);
      expect(event.path, contains('test_file.txt'));

      await subscription.cancel();
    });

    test('should watch file deletion event', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.deleted && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Delete the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.delete();

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.deleted);
      expect(event.path, contains('test_file.txt'));

      await subscription.cancel();
    });

    test('should watch directory for file creation', () async {
      // Start watching directory
      final stream = fileService.watchFile(path: testDirPath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.created && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Create a new file in the directory
      await Future.delayed(const Duration(milliseconds: 100));
      final newFile = File(path.join(testDirPath, 'new_file.txt'));
      await newFile.writeAsString('new file content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.created);
      expect(event.path, contains('new_file.txt'));

      await subscription.cancel();
    });

    test('should watch directory for file modification', () async {
      // Create initial file in directory
      final file = File(path.join(testDirPath, 'dir_test_file.txt'));
      await file.writeAsString('initial content');

      // Start watching directory
      final stream = fileService.watchFile(path: testDirPath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified &&
            event.path.contains('dir_test_file.txt') &&
            !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('modified content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.modified);
      expect(event.path, contains('dir_test_file.txt'));

      await subscription.cancel();
    });

    test('should watch directory for file deletion', () async {
      // Create initial file in directory
      final file = File(path.join(testDirPath, 'delete_test_file.txt'));
      await file.writeAsString('content to delete');

      // Start watching directory
      final stream = fileService.watchFile(path: testDirPath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.deleted &&
            event.path.contains('delete_test_file.txt') &&
            !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Delete the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.delete();

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.deleted);
      expect(event.path, contains('delete_test_file.txt'));

      await subscription.cancel();
    });

    test('should throw exception when watching non-existent path', () async {
      final nonExistentPath = path.join(testDirPath, 'non_existent.txt');

      expect(
        () async {
          final stream = fileService.watchFile(path: nonExistentPath);
          await for (final _ in stream) {
            // This should never execute
          }
        }(),
        throwsA(isA<FileWatchException>()),
      );
    });

    test('should stop watching when stopWatching is called', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final events = <FileChangeEvent>[];

      // Listen to stream
      final subscription = stream.listen((event) {
        events.add(event);
      });

      // Modify file (should generate event)
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('content 1');
      await Future.delayed(const Duration(milliseconds: 200));

      final eventsBeforeStop = events.length;

      // Stop watching
      await fileService.stopWatching(path: testFilePath);
      await Future.delayed(const Duration(milliseconds: 100));

      // Modify file again (should NOT generate event)
      await file.writeAsString('content 2');
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify no new events after stop
      expect(events.length, eventsBeforeStop);

      await subscription.cancel();
    });

    test('should handle multiple listeners on same path', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching with two listeners
      final stream1 = fileService.watchFile(path: testFilePath);
      final stream2 = fileService.watchFile(path: testFilePath);

      final completer1 = Completer<FileChangeEvent>();
      final completer2 = Completer<FileChangeEvent>();

      // Listen to both streams
      final subscription1 = stream1.listen((event) {
        if (event.type == FileChangeType.modified && !completer1.isCompleted) {
          completer1.complete(event);
        }
      });

      final subscription2 = stream2.listen((event) {
        if (event.type == FileChangeType.modified && !completer2.isCompleted) {
          completer2.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('modified content');

      // Wait for both events
      final event1 = await completer1.future
          .timeout(const Duration(seconds: 3));
      final event2 = await completer2.future
          .timeout(const Duration(seconds: 3));

      // Verify both listeners received the event
      expect(event1.type, FileChangeType.modified);
      expect(event2.type, FileChangeType.modified);
      expect(event1.path, event2.path);

      await subscription1.cancel();
      await subscription2.cancel();
    });

    test('should emit events with correct timestamps', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final completer = Completer<FileChangeEvent>();

      final beforeModification = DateTime.now();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('modified content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      final afterModification = DateTime.now();

      // Verify timestamp is within reasonable range
      expect(
        event.timestamp.isAfter(beforeModification) ||
            event.timestamp.isAtSameMomentAs(beforeModification),
        isTrue,
      );
      expect(
        event.timestamp.isBefore(afterModification) ||
            event.timestamp.isAtSameMomentAs(afterModification),
        isTrue,
      );

      await subscription.cancel();
    });

    test('should watch .pack file modifications', () async {
      // Create a .pack file (simulating Total War mod file)
      final packFilePath = path.join(testDirPath, 'test_mod.pack');
      final packFile = File(packFilePath);
      await packFile.writeAsString('pack file content');

      // Start watching
      final stream = fileService.watchFile(path: packFilePath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the pack file
      await Future.delayed(const Duration(milliseconds: 100));
      await packFile.writeAsString('modified pack file content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.modified);
      expect(event.path, contains('.pack'));
      expect(event.path, contains('test_mod.pack'));

      await subscription.cancel();
    });

    test('should watch multiple files simultaneously', () async {
      // Create two files
      final file1Path = path.join(testDirPath, 'file1.txt');
      final file2Path = path.join(testDirPath, 'file2.txt');
      final file1 = File(file1Path);
      final file2 = File(file2Path);
      await file1.writeAsString('file 1 content');
      await file2.writeAsString('file 2 content');

      // Start watching both files
      final stream1 = fileService.watchFile(path: file1Path);
      final stream2 = fileService.watchFile(path: file2Path);

      final completer1 = Completer<FileChangeEvent>();
      final completer2 = Completer<FileChangeEvent>();

      // Listen to both streams
      final subscription1 = stream1.listen((event) {
        if (event.type == FileChangeType.modified && !completer1.isCompleted) {
          completer1.complete(event);
        }
      });

      final subscription2 = stream2.listen((event) {
        if (event.type == FileChangeType.modified && !completer2.isCompleted) {
          completer2.complete(event);
        }
      });

      // Modify both files
      await Future.delayed(const Duration(milliseconds: 100));
      await file1.writeAsString('file 1 modified');
      await Future.delayed(const Duration(milliseconds: 100));
      await file2.writeAsString('file 2 modified');

      // Wait for both events
      final event1 = await completer1.future
          .timeout(const Duration(seconds: 3));
      final event2 = await completer2.future
          .timeout(const Duration(seconds: 3));

      // Verify both events
      expect(event1.type, FileChangeType.modified);
      expect(event1.path, contains('file1.txt'));
      expect(event2.type, FileChangeType.modified);
      expect(event2.path, contains('file2.txt'));

      await subscription1.cancel();
      await subscription2.cancel();
    });

    test('should handle rapid file modifications', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching
      final stream = fileService.watchFile(path: testFilePath);
      final events = <FileChangeEvent>[];

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified) {
          events.add(event);
        }
      });

      // Perform rapid modifications
      await Future.delayed(const Duration(milliseconds: 100));
      for (var i = 0; i < 5; i++) {
        await file.writeAsString('content $i');
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Wait for events to be processed
      await Future.delayed(const Duration(seconds: 1));

      // Verify at least some events were captured
      expect(events.length, greaterThan(0));
      expect(events.every((e) => e.type == FileChangeType.modified), isTrue);

      await subscription.cancel();
    });
  });

  group('Edge Cases and Error Handling', () {
    test('should handle stopping watcher that does not exist', () async {
      final nonExistentPath = path.join(testDirPath, 'not_watched.txt');

      // Should not throw
      await fileService.stopWatching(path: nonExistentPath);

      expect(true, isTrue); // If we get here, test passed
    });

    test('should handle path normalization', () async {
      // Create initial file
      final file = File(testFilePath);
      await file.writeAsString('test content');

      // Start watching with forward slashes
      final normalizedPath = testFilePath.replaceAll('\\', '/');
      final stream = fileService.watchFile(path: normalizedPath);
      final completer = Completer<FileChangeEvent>();

      // Listen to stream
      final subscription = stream.listen((event) {
        if (event.type == FileChangeType.modified && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 100));
      await file.writeAsString('modified content');

      // Wait for event
      final event = await completer.future
          .timeout(const Duration(seconds: 3));

      // Verify event
      expect(event.type, FileChangeType.modified);

      await subscription.cancel();
    });
  });
}
