import 'package:json_annotation/json_annotation.dart';

part 'process_result.g.dart';

/// Result of an external process execution
@JsonSerializable()
class ProcessResult {
  /// Exit code (0 = success)
  final int exitCode;

  /// Standard output
  final String stdout;

  /// Standard error
  final String stderr;

  /// Process execution time in milliseconds
  final int executionTimeMs;

  /// Whether the process succeeded (exitCode == 0)
  bool get isSuccess => exitCode == 0;

  /// Whether the process failed (exitCode != 0)
  bool get isFailure => exitCode != 0;

  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.executionTimeMs,
  });

  factory ProcessResult.fromJson(Map<String, dynamic> json) =>
      _$ProcessResultFromJson(json);

  Map<String, dynamic> toJson() => _$ProcessResultToJson(this);

  ProcessResult copyWith({
    int? exitCode,
    String? stdout,
    String? stderr,
    int? executionTimeMs,
  }) {
    return ProcessResult(
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      executionTimeMs: executionTimeMs ?? this.executionTimeMs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProcessResult &&
        other.exitCode == exitCode &&
        other.stdout == stdout &&
        other.stderr == stderr;
  }

  @override
  int get hashCode => Object.hash(exitCode, stdout, stderr);

  @override
  String toString() {
    return 'ProcessResult(exitCode: $exitCode, executionTime: ${executionTimeMs}ms, stdout: ${stdout.length} chars, stderr: ${stderr.length} chars)';
  }
}

/// Progress update from a running process
@JsonSerializable()
class ProcessProgress {
  /// Process ID
  final int pid;

  /// Current output line (stdout or stderr)
  final String? currentLine;

  /// Whether this is from stderr
  final bool isError;

  /// Total lines received so far
  final int totalLines;

  /// Timestamp
  final DateTime timestamp;

  const ProcessProgress({
    required this.pid,
    this.currentLine,
    required this.isError,
    required this.totalLines,
    required this.timestamp,
  });

  factory ProcessProgress.fromJson(Map<String, dynamic> json) =>
      _$ProcessProgressFromJson(json);

  Map<String, dynamic> toJson() => _$ProcessProgressToJson(this);

  @override
  String toString() {
    return 'ProcessProgress(pid: $pid, line: $currentLine, isError: $isError)';
  }
}

/// Configuration for process execution
class ProcessConfig {
  /// Working directory for the process
  final String? workingDirectory;

  /// Environment variables
  final Map<String, String>? environment;

  /// Whether to include parent environment variables
  final bool includeParentEnvironment;

  /// Maximum execution time (null = no timeout)
  final Duration? timeout;

  /// Whether to run in shell mode
  final bool runInShell;

  /// Stream stdout/stderr in real-time
  final bool streamOutput;

  const ProcessConfig({
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.timeout,
    this.runInShell = false,
    this.streamOutput = false,
  });

  ProcessConfig copyWith({
    String? workingDirectory,
    Map<String, String>? environment,
    bool? includeParentEnvironment,
    Duration? timeout,
    bool? runInShell,
    bool? streamOutput,
  }) {
    return ProcessConfig(
      workingDirectory: workingDirectory ?? this.workingDirectory,
      environment: environment ?? this.environment,
      includeParentEnvironment: includeParentEnvironment ?? this.includeParentEnvironment,
      timeout: timeout ?? this.timeout,
      runInShell: runInShell ?? this.runInShell,
      streamOutput: streamOutput ?? this.streamOutput,
    );
  }
}
