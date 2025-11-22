import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';

/// Log message for initialization process
class InitializationLogMessage {
  final String message;
  final InitializationLogLevel level;
  final DateTime timestamp;

  InitializationLogMessage({
    required this.message,
    required this.level,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Log levels for initialization messages
enum InitializationLogLevel {
  info,
  warning,
  error,
}

/// Service interface for initializing new translation projects
///
/// Handles the complete workflow of setting up a project:
/// 1. Extract .loc files from .pack using RPFM
/// 2. Parse extracted .loc files
/// 3. Create translation_units in database
abstract class IProjectInitializationService {
  /// Initialize a project by extracting and importing localization files
  ///
  /// This performs the complete initialization workflow:
  /// 1. Extract .loc files from the source .pack file using RPFM-CLI
  /// 2. Parse each extracted .loc file
  /// 3. Create translation_units in the database for each entry
  ///
  /// [projectId]: ID of the project to initialize
  /// [packFilePath]: Path to the source .pack file
  ///
  /// Returns [Ok(count)] with the number of units imported,
  /// or [Err(ServiceException)] on failure
  Future<Result<int, ServiceException>> initializeProject({
    required String projectId,
    required String packFilePath,
  });

  /// Cancel ongoing initialization
  ///
  /// Stops the current extraction and import operation if any.
  Future<void> cancel();

  /// Progress stream for initialization operations
  ///
  /// Yields progress updates (0.0-1.0) during initialization
  Stream<double> get progressStream;

  /// Log message stream for initialization operations
  ///
  /// Yields detailed log messages during initialization
  Stream<InitializationLogMessage> get logStream;
}
