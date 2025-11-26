import 'dart:async';
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_extraction_mixin.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_pack_operations_mixin.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of RPFM service
///
/// Uses mixins to separate extraction and pack operation concerns:
/// - [RpfmExtractionMixin]: Handles extractLocalizationFiles, extractLocalizationFilesAsTsv, extractAllFiles
/// - [RpfmPackOperationsMixin]: Handles createPack, getPackInfo, listPackContents
class RpfmServiceImpl
    with RpfmExtractionMixin, RpfmPackOperationsMixin
    implements IRpfmService {
  final RpfmCliManager _cliManager = RpfmCliManager();
  final LoggingService _logger = LoggingService.instance;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<RpfmLogMessage> _logController =
      StreamController<RpfmLogMessage>.broadcast();

  Process? _currentProcess;
  bool _isCancelled = false;

  // Expose internal state to mixins
  @override
  RpfmCliManager get cliManager => _cliManager;

  @override
  LoggingService get logger => _logger;

  @override
  StreamController<double> get progressController => _progressController;

  @override
  StreamController<RpfmLogMessage> get logController => _logController;

  @override
  bool get isCancelled => _isCancelled;

  @override
  set isCancelled(bool value) => _isCancelled = value;

  @override
  Process? get currentProcess => _currentProcess;

  @override
  set currentProcess(Process? value) => _currentProcess = value;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  Stream<RpfmLogMessage> get logStream => _logController.stream;

  // Extraction methods are provided by RpfmExtractionMixin:
  // - extractLocalizationFiles
  // - extractLocalizationFilesAsTsv
  // - extractAllFiles

  // Pack operation methods are provided by RpfmPackOperationsMixin:
  // - createPack
  // - getPackInfo
  // - listPackContents

  @override
  Future<bool> isRpfmAvailable() async {
    return await _cliManager.isAvailable();
  }

  @override
  Future<Result<String, RpfmServiceException>> getRpfmVersion() async {
    return await _cliManager.getVersion();
  }

  @override
  Future<Result<String, RpfmServiceException>> downloadRpfm({
    bool force = false,
  }) async {
    return await _cliManager.downloadAndInstall(
      onProgress: (progress) => _progressController.add(progress),
    );
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentProcess?.kill();
    _currentProcess = null;
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _logController.close();
    _currentProcess?.kill();
  }
}
