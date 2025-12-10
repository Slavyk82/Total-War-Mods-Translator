import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/steam/steam_workshop_service_impl.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late SteamWorkshopServiceImpl service;
  late MockHttpClient mockHttpClient;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockHttpClient = MockHttpClient();
    service = SteamWorkshopServiceImpl(httpClient: mockHttpClient);
  });

  tearDown(() {
    mockHttpClient.close();
  });

  group('SteamWorkshopService - getWorkshopItemDetails', () {
    const workshopId = '1234567890';

    test('should return workshop item details on successful API call', () async {
      // Arrange
      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 1,
              "publishedfileid": "$workshopId",
              "title": "Test Mod",
              "description": "A test mod description",
              "time_updated": 1700000000,
              "time_created": 1699000000,
              "file_size": 1024000,
              "preview_url": "https://example.com/preview.jpg",
              "subscriptions": 5000,
              "favorited": 1000,
              "tags": [
                {"tag": "units"},
                {"tag": "battles"}
              ],
              "children": [
                {"publishedfileid": "9876543210"}
              ]
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.getWorkshopItemDetails(workshopId: workshopId);

      // Assert
      expect(result.isOk, true);
      final details = result.unwrap();
      expect(details.publishedFileId, workshopId);
      expect(details.title, 'Test Mod');
      expect(details.fileSize, 1024000);
      expect(details.subscriptions, 5000);
      expect(details.tags, ['units', 'battles']);
      expect(details.timeUpdated.millisecondsSinceEpoch, 1700000000 * 1000);
      expect(details.timeCreated?.millisecondsSinceEpoch, 1699000000 * 1000);
    });

    test('should return error for invalid workshop ID format', () async {
      // Act
      final result = await service.getWorkshopItemDetails(workshopId: 'invalid-id');

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
      expect(result.error.message, contains('Invalid Workshop ID format'));
    });

    test('should return error when API returns non-200 status', () async {
      // Arrange
      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('Error', 500));

      // Act
      final result = await service.getWorkshopItemDetails(workshopId: workshopId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
      expect(result.error.message, contains('failed with status 500'));
    });

    test('should return error when API response has invalid format', () async {
      // Arrange
      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('{"invalid": "format"}', 200));

      // Act
      final result = await service.getWorkshopItemDetails(workshopId: workshopId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
      expect(result.error.message, contains('Invalid API response format'));
    });

    test('should return error when workshop item not found (result != 1)', () async {
      // Arrange
      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 9,
              "publishedfileid": "$workshopId"
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.getWorkshopItemDetails(workshopId: workshopId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
      expect(result.error.message, contains('not accessible'));
    });

    test('should handle network errors gracefully', () async {
      // Arrange
      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('Network error'));

      // Act
      final result = await service.getWorkshopItemDetails(workshopId: workshopId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
      expect(result.error.message, contains('Failed to fetch Workshop item details'));
    });
  });

  group('SteamWorkshopService - checkForUpdates', () {
    test('should check multiple workshop items for updates', () async {
      // Arrange
      final workshopIds = {
        '1111111111': DateTime(2024, 1, 1),
        '2222222222': DateTime(2024, 6, 1),
      };

      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 1,
              "publishedfileid": "1111111111",
              "title": "Mod 1",
              "time_updated": 1720000000
            },
            {
              "result": 1,
              "publishedfileid": "2222222222",
              "title": "Mod 2",
              "time_updated": 1717200000
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.checkForUpdates(workshopIds: workshopIds);

      // Assert
      expect(result.isOk, true);
      final updates = result.value;
      expect(updates.length, 2);

      // First mod should have update (newer timestamp)
      final update1 = updates.firstWhere((u) => u.workshopId == '1111111111');
      expect(update1.hasUpdate, true);
      expect(update1.modName, 'Mod 1');

      // Second mod should have update (newer timestamp)
      final update2 = updates.firstWhere((u) => u.workshopId == '2222222222');
      expect(update2.hasUpdate, true);
      expect(update2.modName, 'Mod 2');
    });

    test('should return empty list for empty input', () async {
      // Act
      final result = await service.checkForUpdates(workshopIds: {});

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
    });

    test('should skip items with failed result code', () async {
      // Arrange
      final workshopIds = {
        '1111111111': DateTime(2024, 1, 1),
        '2222222222': DateTime(2024, 6, 1),
      };

      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 1,
              "publishedfileid": "1111111111",
              "title": "Mod 1",
              "time_updated": 1720000000
            },
            {
              "result": 9,
              "publishedfileid": "2222222222"
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.checkForUpdates(workshopIds: workshopIds);

      // Assert
      expect(result.isOk, true);
      expect(result.value.length, 1);
      expect(result.value.first.workshopId, '1111111111');
    });

    test('should handle API errors', () async {
      // Arrange
      final workshopIds = {
        '1111111111': DateTime(2024, 1, 1),
      };

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('Error', 500));

      // Act
      final result = await service.checkForUpdates(workshopIds: workshopIds);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
    });
  });

  group('SteamWorkshopService - getLastUpdatedTime', () {
    test('should return last updated time for valid workshop item', () async {
      // Arrange
      const workshopId = '1234567890';
      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 1,
              "publishedfileid": "$workshopId",
              "title": "Test Mod",
              "time_updated": 1700000000,
              "file_size": 1024000
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.getLastUpdatedTime(workshopId: workshopId);

      // Assert
      expect(result.isOk, true);
      expect(result.value.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('should return error when workshop item not found', () async {
      // Arrange
      const workshopId = '1234567890';
      final responseBody = '''
      {
        "response": {
          "publishedfiledetails": [
            {
              "result": 9,
              "publishedfileid": "$workshopId"
            }
          ]
        }
      }
      ''';

      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(responseBody, 200));

      // Act
      final result = await service.getLastUpdatedTime(workshopId: workshopId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<SteamException>());
    });
  });
}
