import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/process_output_drainer.dart';

// Unit tests for ProcessOutputDrainer — the shared stdout/stderr drain
// helper used by ProcessService, SteamCmdServiceImpl and
// WorkshopPublishServiceImpl. Covers the behaviors the previous five
// hand-rolled copies diverged on:
//   - drain completes on stream ERROR (the steam copies had no onError and
//     hung until the grace timeout),
//   - a trailing partial line (no final newline) is flushed to the line
//     callback,
//   - awaitDrained gives up after the grace period when a stream never
//     closes (inherited pipe kept open by a surviving child process).

void main() {
  group('ProcessOutputDrainer', () {
    test('chunk callbacks receive decoded chunks; awaitDrained completes '
        'once both streams are done', () async {
      final stdoutChunks = <String>[];
      final stderrChunks = <String>[];

      final drainer = ProcessOutputDrainer(
        stdout: Stream<List<int>>.fromIterable([
          utf8.encode('hello '),
          utf8.encode('world'),
        ]),
        stderr: Stream<List<int>>.value(utf8.encode('oops')),
        encoding: utf8,
        onStdoutChunk: stdoutChunks.add,
        onStderrChunk: stderrChunks.add,
      );

      await drainer.awaitDrained();

      expect(stdoutChunks.join(), 'hello world');
      expect(stderrChunks.join(), 'oops');
    });

    test('lines split across chunks are reassembled and the trailing '
        'partial line is flushed on done', () async {
      final lines = <String>[];
      final controller = StreamController<List<int>>();

      final drainer = ProcessOutputDrainer(
        stdout: controller.stream,
        stderr: const Stream<List<int>>.empty(),
        onStdoutLine: lines.add,
      );

      controller.add(latin1.encode('first li'));
      controller.add(latin1.encode('ne\nsecond line\npartial tr'));
      controller.add(latin1.encode('ailer'));
      await controller.close();

      await drainer.awaitDrained();

      expect(lines, ['first line', 'second line', 'partial trailer']);
    });

    test(r'a \r\n pair split across chunks does not produce a spurious '
        'empty line', () async {
      final lines = <String>[];
      final controller = StreamController<List<int>>();

      final drainer = ProcessOutputDrainer(
        stdout: controller.stream,
        stderr: const Stream<List<int>>.empty(),
        onStdoutLine: lines.add,
      );

      controller.add(latin1.encode('line one\r'));
      controller.add(latin1.encode('\nline two\r\n'));
      await controller.close();

      await drainer.awaitDrained();

      expect(lines, ['line one', 'line two']);
    });

    test('empty lines between line breaks are preserved (LineSplitter '
        'parity for ProcessService.runWithStreaming)', () async {
      final lines = <String>[];

      final drainer = ProcessOutputDrainer(
        stdout: Stream<List<int>>.value(latin1.encode('a\n\nb\n')),
        stderr: const Stream<List<int>>.empty(),
        onStdoutLine: lines.add,
      );

      await drainer.awaitDrained();

      expect(lines, ['a', '', 'b']);
    });

    test('stream error completes the drain instead of hanging until the '
        'grace timeout, and flushes the buffered partial line', () async {
      final lines = <String>[];
      final controller = StreamController<List<int>>();

      final drainer = ProcessOutputDrainer(
        stdout: controller.stream,
        stderr: const Stream<List<int>>.empty(),
        onStdoutLine: lines.add,
      );

      controller.add(latin1.encode('before the error'));
      controller.addError(Exception('pipe broke'));
      await controller.close();

      final sw = Stopwatch()..start();
      await drainer.awaitDrained(grace: const Duration(seconds: 5));
      sw.stop();

      expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'a stream error must complete the drain immediately, '
              'not stall it until the grace timeout');
      expect(lines, ['before the error'],
          reason: 'data received before the error must still be flushed');
    });

    test('awaitDrained gives up after the grace period when a stream '
        'never closes', () async {
      // Never-closing controller models a surviving child process keeping
      // the inherited stdout pipe open after the parent exited.
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);

      final drainer = ProcessOutputDrainer(
        stdout: controller.stream,
        stderr: const Stream<List<int>>.empty(),
      );

      final sw = Stopwatch()..start();
      await drainer.awaitDrained(grace: const Duration(milliseconds: 100));
      sw.stop();

      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('cancel() stops delivery and is safe to call twice', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      final chunks = <String>[];

      final drainer = ProcessOutputDrainer(
        stdout: controller.stream,
        stderr: const Stream<List<int>>.empty(),
        onStdoutChunk: chunks.add,
      );

      controller.add(latin1.encode('first'));
      await Future<void>.delayed(Duration.zero);
      await drainer.cancel();
      controller.add(latin1.encode('second'));
      await Future<void>.delayed(Duration.zero);
      await drainer.cancel();

      expect(chunks, ['first']);
    });
  });
}
