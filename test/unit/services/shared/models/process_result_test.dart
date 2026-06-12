import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/models/process_result.dart';

void main() {
  group('ProcessResult', () {
    ProcessResult res(int code) => ProcessResult(
          exitCode: code,
          stdout: 'out',
          stderr: 'err',
          executionTimeMs: 50,
        );

    test('isSuccess / isFailure reflect the exit code', () {
      expect(res(0).isSuccess, isTrue);
      expect(res(0).isFailure, isFalse);
      expect(res(1).isSuccess, isFalse);
      expect(res(1).isFailure, isTrue);
    });

    test('copyWith + equality (code/stdout/stderr) + json round-trip', () {
      expect(res(0).copyWith(exitCode: 2).exitCode, 2);
      expect(res(0), equals(res(0)));
      expect(res(0).hashCode, res(0).hashCode);

      final restored = ProcessResult.fromJson(res(0).toJson());
      expect(restored.stdout, 'out');
      expect(restored.executionTimeMs, 50);
    });
  });

  group('ProcessProgress', () {
    test('json round-trip', () {
      final p = ProcessProgress(
        pid: 1234,
        currentLine: 'building...',
        isError: false,
        totalLines: 5,
        timestamp: DateTime(2026, 1, 1),
      );
      final restored = ProcessProgress.fromJson(p.toJson());
      expect(restored.pid, 1234);
      expect(restored.currentLine, 'building...');
      expect(restored.totalLines, 5);
    });
  });

  group('ProcessConfig', () {
    test('applies defaults', () {
      const c = ProcessConfig();
      expect(c.includeParentEnvironment, isTrue);
      expect(c.runInShell, isFalse);
      expect(c.streamOutput, isFalse);
      expect(c.timeout, isNull);
    });

    test('copyWith overrides only the targeted field', () {
      const c = ProcessConfig(workingDirectory: '/a');
      final updated = c.copyWith(runInShell: true);
      expect(updated.runInShell, isTrue);
      expect(updated.workingDirectory, '/a');
    });
  });
}
