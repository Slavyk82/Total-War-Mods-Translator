import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/workshop_api_service_impl.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';

import '../../helpers/noop_logger.dart';

/// These tests exercise only the input-validation and early-return branches
/// that do not perform a network request. Paths that hit the Steam Web API are
/// intentionally not covered here.
void main() {
  late WorkshopApiServiceImpl service;

  setUp(() {
    service = WorkshopApiServiceImpl(logger: NoopLogger());
  });

  group('getModInfo validation', () {
    test('rejects a non-numeric Workshop ID', () async {
      final result = await service.getModInfo(workshopId: 'abc', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
      expect((result.error as InvalidWorkshopIdException).invalidId, 'abc');
    });

    test('rejects an empty Workshop ID', () async {
      final result = await service.getModInfo(workshopId: '', appId: 1142710);

      expect(result.error, isA<InvalidWorkshopIdException>());
    });
  });

  group('getMultipleModInfo validation', () {
    test('rejects when any ID is invalid', () async {
      final result = await service.getMultipleModInfo(
        workshopIds: ['123', 'not-a-number'],
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
    });

    test('rejects more than 100 items', () async {
      final ids = List.generate(101, (i) => '$i');

      final result = await service.getMultipleModInfo(
        workshopIds: ids,
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect(result.error.message, contains('100'));
    });
  });

  group('searchMods', () {
    test('is unsupported and returns an explanatory error', () async {
      final result = await service.searchMods(query: 'orcs', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect(result.error.message, contains('Search not implemented'));
    });
  });

  group('checkForUpdates', () {
    test('returns an empty map when no mods are supplied', () async {
      final result = await service.checkForUpdates(
        modsWithTimestamps: {},
        appId: 1142710,
      );

      expect(result, isA<Ok>());
      expect(result.value, isEmpty);
    });
  });
}
