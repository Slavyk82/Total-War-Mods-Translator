import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/scan_log_message.dart';
import 'package:twmt/providers/mods_data_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';

class MockWorkshopScannerService extends Mock
    implements WorkshopScannerService {}

void main() {
  group('scanLogStreamProvider', () {
    test('exposes the scanner service scan log stream', () {
      final mock = MockWorkshopScannerService();
      final controller = StreamController<ScanLogMessage>.broadcast();
      addTearDown(controller.close);
      final stream = controller.stream;
      when(() => mock.scanLogStream).thenAnswer((_) => stream);

      final container = ProviderContainer(overrides: [
        workshopScannerServiceProvider.overrideWithValue(mock),
      ]);
      addTearDown(container.dispose);

      expect(container.read(scanLogStreamProvider), same(stream));
    });
  });

  group('ModsInitialRescanDone', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('build returns false', () {
      expect(container.read(modsInitialRescanDoneProvider), isFalse);
    });

    test('markDone flips the flag to true', () {
      container.read(modsInitialRescanDoneProvider.notifier).markDone();
      expect(container.read(modsInitialRescanDoneProvider), isTrue);
    });
  });
}
