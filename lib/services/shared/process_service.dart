import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/common/result.dart';
import 'models/process_result.dart' as models;

/// Service for executing external processes
///
/// Provides a high-level interface for running external commands with:
/// - Timeout handling
/// - Real-time output streaming
/// - Cancellation support
/// - Exit code validation
/// - Error handling
///
/// Example:
/// ```dart
/// final service = ProcessService.instance;
///
/// // Simple execution
/// final result = await service.run('git', ['status']);
/// if (result is Ok) {
///   print('Git status: ${result.value.stdout}');
/// }
///
/// // With streaming
/// await service.runWithStreaming(
///   'npm',
///   ['install'],
///   onProgress: (progress) {
///     print('Output: ${progress.currentLine}');
///   },
/// );
/// ```
class ProcessService {
  ProcessService._();

  static final ProcessService _instance = ProcessService._();
  static ProcessService get instance => _instance;

  /// Active processes (for tracking and cancellation)
  final Map<int, Process> _activeProcesses = {};

  /// Run a process and wait for completion
  ///
  /// Parameters:
  /// - [executable]: Path to executable or command name
  /// - [arguments]: Command arguments
  /// - [config]: Process configuration
  ///
  /// Returns:
  /// - [Ok]: ProcessResult with exit code and output
  /// - [Err]: Exception if execution failed
  Future<Result<models.ProcessResult, Exception>> run(
    String executable,
    List<String> arguments, {
    models.ProcessConfig config = const models.ProcessConfig(),
  }) async {
    final startTime = DateTime.now();

    try {
      // Start the process
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        includeParentEnvironment: config.includeParentEnvironment,
        runInShell: config.runInShell,
      );

      _activeProcesses[process.pid] = process;

      // Collect output
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen((data) => stdoutBuffer.write(data));

      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((data) => stderrBuffer.write(data));

      // Wait for process to complete (with optional timeout)
      int exitCode;
      if (config.timeout != null) {
        exitCode = await process.exitCode.timeout(
          config.timeout!,
          onTimeout: () {
            process.kill();
            throw TimeoutException(
              'Process timed out after ${config.timeout!.inSeconds}s',
            );
          },
        );
      } else {
        exitCode = await process.exitCode;
      }

      // Wait for output streams to complete
      await stdoutSub.cancel();
      await stderrSub.cancel();

      _activeProcesses.remove(process.pid);

      final executionTime = DateTime.now().difference(startTime);

      final result = models.ProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        executionTimeMs: executionTime.inMilliseconds,
      );

      return Ok(result);
    } on TimeoutException catch (e) {
      return Err(Exception('Process timeout: ${e.message}'));
    } catch (e) {
      return Err(Exception('Process execution failed: ${e.toString()}'));
    }
  }

  /// Run a process with real-time output streaming
  ///
  /// Parameters:
  /// - [executable]: Path to executable or command name
  /// - [arguments]: Command arguments
  /// - [config]: Process configuration
  /// - [onProgress]: Callback for progress updates
  ///
  /// Returns:
  /// - [Ok]: ProcessResult with exit code and output
  /// - [Err]: Exception if execution failed
  Future<Result<models.ProcessResult, Exception>> runWithStreaming(
    String executable,
    List<String> arguments, {
    models.ProcessConfig config = const models.ProcessConfig(),
    void Function(models.ProcessProgress progress)? onProgress,
  }) async {
    final startTime = DateTime.now();

    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        includeParentEnvironment: config.includeParentEnvironment,
        runInShell: config.runInShell,
      );

      _activeProcesses[process.pid] = process;

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      int lineCount = 0;

      // Stream stdout
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuffer.writeln(line);
        lineCount++;

        if (onProgress != null) {
          onProgress(models.ProcessProgress(
            pid: process.pid,
            currentLine: line,
            isError: false,
            totalLines: lineCount,
            timestamp: DateTime.now(),
          ));
        }
      });

      // Stream stderr
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.writeln(line);
        lineCount++;

        if (onProgress != null) {
          onProgress(models.ProcessProgress(
            pid: process.pid,
            currentLine: line,
            isError: true,
            totalLines: lineCount,
            timestamp: DateTime.now(),
          ));
        }
      });

      // Wait for process
      int exitCode;
      if (config.timeout != null) {
        exitCode = await process.exitCode.timeout(
          config.timeout!,
          onTimeout: () {
            process.kill();
            throw TimeoutException(
              'Process timed out after ${config.timeout!.inSeconds}s',
            );
          },
        );
      } else {
        exitCode = await process.exitCode;
      }

      await stdoutSub.cancel();
      await stderrSub.cancel();

      _activeProcesses.remove(process.pid);

      final executionTime = DateTime.now().difference(startTime);

      final result = models.ProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        executionTimeMs: executionTime.inMilliseconds,
      );

      return Ok(result);
    } on TimeoutException catch (e) {
      return Err(Exception('Process timeout: ${e.message}'));
    } catch (e) {
      return Err(Exception('Process execution failed: ${e.toString()}'));
    }
  }

  /// Run a process and return streams for stdout/stderr
  ///
  /// Useful for long-running processes where you want to process
  /// output as it arrives.
  ///
  /// Returns:
  /// - Process object for monitoring and control
  /// - Don't forget to call process.kill() when done
  Future<Result<Process, Exception>> startStreaming(
    String executable,
    List<String> arguments, {
    models.ProcessConfig config = const models.ProcessConfig(),
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        includeParentEnvironment: config.includeParentEnvironment,
        runInShell: config.runInShell,
      );

      _activeProcesses[process.pid] = process;

      return Ok(process);
    } catch (e) {
      return Err(Exception('Failed to start process: ${e.toString()}'));
    }
  }

  /// Cancel a running process
  ///
  /// Parameters:
  /// - [pid]: Process ID to cancel
  /// - [signal]: Signal to send (default: SIGTERM on Unix, CTRL_C on Windows)
  ///
  /// Returns true if process was found and killed
  bool cancel(int pid, {ProcessSignal signal = ProcessSignal.sigterm}) {
    final process = _activeProcesses[pid];
    if (process == null) return false;

    final killed = process.kill(signal);
    if (killed) {
      _activeProcesses.remove(pid);
    }

    return killed;
  }

  /// Cancel all running processes
  ///
  /// Returns number of processes cancelled
  int cancelAll({ProcessSignal signal = ProcessSignal.sigterm}) {
    int count = 0;

    final pids = _activeProcesses.keys.toList();
    for (final pid in pids) {
      if (cancel(pid, signal: signal)) {
        count++;
      }
    }

    return count;
  }

  /// Get list of active process IDs
  List<int> get activeProcessIds => _activeProcesses.keys.toList();

  /// Get number of active processes
  int get activeProcessCount => _activeProcesses.length;

  /// Check if a process is still running
  bool isProcessActive(int pid) => _activeProcesses.containsKey(pid);

  /// Run a simple command and get output as string
  ///
  /// Convenience method for simple use cases.
  /// Throws exception if exit code != 0.
  ///
  /// Example:
  /// ```dart
  /// final gitVersion = await service.runSimple('git', ['--version']);
  /// print(gitVersion); // "git version 2.40.0"
  /// ```
  Future<String> runSimple(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final result = await run(
      executable,
      arguments,
      config: models.ProcessConfig(timeout: timeout),
    );

    if (result is Err) {
      throw result.error;
    }

    final processResult = (result as Ok<models.ProcessResult, Exception>).value;

    if (processResult.exitCode != 0) {
      throw Exception(
        'Process failed with exit code ${processResult.exitCode}: ${processResult.stderr}',
      );
    }

    return processResult.stdout.trim();
  }

  /// Check if an executable exists and is accessible
  ///
  /// Tries to run the executable with --version or --help.
  Future<bool> isExecutableAvailable(String executable) async {
    try {
      final result = await run(
        executable,
        ['--version'],
        config: const models.ProcessConfig(
          timeout: Duration(seconds: 5),
        ),
      );

      return result is Ok;
    } catch (e) {
      return false;
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    // Kill all active processes
    cancelAll();
  }
}
