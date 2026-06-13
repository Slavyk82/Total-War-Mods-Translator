import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/rpfm_service_impl.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory supportDir;
  late RpfmServiceImpl service;

  setUp(() async {
    // The shared RpfmCliManager singleton resolves a logger from ServiceLocator.
    await TestBootstrap.registerFakes();

    supportDir = await Directory.systemTemp.createTemp('rpfm_impl_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return supportDir.path;
    });

    service = RpfmServiceImpl(logger: NoopLogger());
  });

  tearDown(() async {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  group('streams', () {
    test('progress and log streams are broadcast', () {
      expect(service.progressStream.isBroadcast, isTrue);
      expect(service.logStream.isBroadcast, isTrue);
    });
  });

  group('cancel', () {
    test('flags cancellation and clears the current process', () async {
      expect(service.isCancelled, isFalse);

      await service.cancel();

      expect(service.isCancelled, isTrue);
      expect(service.currentProcess, isNull);
    });
  });

  group('extraction entry validation (via mixin)', () {
    test('extractLocalizationFiles rejects a missing pack', () async {
      final result = await service
          .extractLocalizationFiles('${supportDir.path}/missing.pack');

      expect(result, isA<Err>());
      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('extractLocalizationFilesAsTsv rejects a missing pack', () async {
      final result = await service
          .extractLocalizationFilesAsTsv('${supportDir.path}/missing.pack');

      expect(result.error, isA<RpfmInvalidPackException>());
    });

    test('extractAllFiles rejects a missing pack', () async {
      final result = await service.extractAllFiles(
        '${supportDir.path}/missing.pack',
        '${supportDir.path}/out',
      );

      expect(result.error, isA<RpfmInvalidPackException>());
    });
  });

  group('availability (RPFM not provisioned in tests)', () {
    test('isRpfmAvailable resolves to a boolean', () async {
      expect(await service.isRpfmAvailable(), isA<bool>());
    });

    test('getRpfmVersion resolves to a Result', () async {
      final result = await service.getRpfmVersion();
      expect(result, isA<Result<String, RpfmServiceException>>());
    });
  });

  group('dispose', () {
    test('closes the progress stream', () async {
      final local = RpfmServiceImpl(logger: NoopLogger());
      final done = expectLater(local.progressStream, emitsDone);
      local.dispose();
      await done;
    });
  });
}
