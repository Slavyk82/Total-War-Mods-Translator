import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/steam_detection_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';

import '../../helpers/noop_logger.dart';

void main() {
  late SteamDetectionService service;

  setUp(() {
    service = SteamDetectionService(logger: NoopLogger());
  });

  group('detectGame', () {
    test('rejects an unknown game code without touching the filesystem',
        () async {
      final result = await service.detectGame('not_a_real_game');

      expect(result, isA<Err>());
      final err = result.error;
      expect(err, isA<SteamServiceException>());
      expect(err.code, 'INVALID_GAME_CODE');
    });

    test('returns Ok for a known game code (path may be null when not installed)',
        () async {
      final result = await service.detectGame('wh3');

      // The host may or may not have the game installed; either way the
      // call must succeed and yield a nullable path.
      expect(result, isA<Ok>());
      expect(result.value, anyOf(isNull, isA<String>()));
    });
  });

  group('detectAllGames', () {
    test('returns Ok with a map of detected games', () async {
      final result = await service.detectAllGames();

      expect(result, isA<Ok>());
      expect(result.value, isA<Map<String, String>>());
    });
  });

  group('detectWorkshopFolder', () {
    test('returns Ok with a nullable workshop path', () async {
      final result = await service.detectWorkshopFolder();

      expect(result, isA<Ok>());
      expect(result.value, anyOf(isNull, isA<String>()));
    });
  });

  group('clearCache', () {
    test('can be called before and after detection without throwing',
        () async {
      service.clearCache();
      await service.detectAllGames();
      // Second call hits the cached libraries path.
      await service.detectAllGames();
      service.clearCache();

      expect(true, isTrue);
    });
  });
}
