import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/rpfm/mixins/rpfm_extraction_mixin.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import '../../helpers/noop_logger.dart';

/// Minimal host that satisfies [RpfmExtractionMixin]'s contract so the mixin
/// can be unit-tested in isolation.
class _Host with RpfmExtractionMixin {
  _Host(this._listResult);

  final Result<List<String>, RpfmServiceException> _listResult;

  @override
  final RpfmCliManager cliManager = RpfmCliManager(logger: NoopLogger());

  @override
  final ILoggingService logger = NoopLogger();

  @override
  final StreamController<double> progressController =
      StreamController<double>.broadcast();

  @override
  final StreamController<RpfmLogMessage> logController =
      StreamController<RpfmLogMessage>.broadcast();

  @override
  bool isCancelled = false;

  @override
  Process? currentProcess;

  @override
  Future<Result<List<String>, RpfmServiceException>> listPackContents(
    String packFilePath,
  ) async =>
      _listResult;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rpfm_extract_mixin_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String missingPack() => '${tempDir.path}/does_not_exist.pack';

  group('extractLocalizationFiles', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(const Ok([]));

      final result =
          await host.extractLocalizationFiles(missingPack());

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('finally block emits final progress and resets cancellation',
        () async {
      final host = _Host(const Ok([]));
      host.isCancelled = true;
      final progress = <double>[];
      host.progressController.stream.listen(progress.add);

      await host.extractLocalizationFiles(missingPack());
      await Future<void>.delayed(Duration.zero);

      expect(progress, contains(1.0));
      expect(host.isCancelled, isFalse);
    });
  });

  group('extractLocalizationFilesAsTsv', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(const Ok([]));

      final result =
          await host.extractLocalizationFilesAsTsv(missingPack());

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });
  });

  group('extractAllFiles', () {
    test('returns RpfmInvalidPackException when the pack is missing', () async {
      final host = _Host(const Ok([]));

      final result = await host.extractAllFiles(
        missingPack(),
        '${tempDir.path}/out',
      );

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('clears currentProcess and cancellation in its finally block',
        () async {
      final host = _Host(const Ok([]));
      host.isCancelled = true;

      await host.extractAllFiles(missingPack(), '${tempDir.path}/out');

      expect(host.currentProcess, isNull);
      expect(host.isCancelled, isFalse);
    });
  });
}
