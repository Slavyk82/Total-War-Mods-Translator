import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late Database db;
  late GameInstallationRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create game_installations table
    await db.execute('''
      CREATE TABLE game_installations (
        id TEXT PRIMARY KEY,
        game_code TEXT NOT NULL,
        game_name TEXT NOT NULL,
        installation_path TEXT,
        steam_workshop_path TEXT,
        steam_app_id TEXT,
        is_auto_detected INTEGER DEFAULT 0,
        is_valid INTEGER DEFAULT 1,
        last_validated_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Initialize DatabaseService with the test database
    DatabaseService.setTestDatabase(db);

    repository = GameInstallationRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('GameInstallationRepository', () {
    GameInstallation createTestInstallation({
      String? id,
      String? gameCode,
      String? gameName,
      String? installationPath,
      String? steamWorkshopPath,
      String? steamAppId,
      bool? isAutoDetected,
      bool? isValid,
      int? lastValidatedAt,
      int? createdAt,
      int? updatedAt,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return GameInstallation(
        id: id ?? 'install-id',
        gameCode: gameCode ?? 'wh3',
        gameName: gameName ?? 'Total War: WARHAMMER III',
        installationPath: installationPath ?? 'C:\\Games\\TotalWar\\Warhammer3',
        steamWorkshopPath: steamWorkshopPath ?? 'C:\\Steam\\steamapps\\workshop\\content\\1142710',
        steamAppId: steamAppId ?? '1142710',
        isAutoDetected: isAutoDetected ?? false,
        isValid: isValid ?? true,
        lastValidatedAt: lastValidatedAt,
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
      );
    }

    group('insert', () {
      test('should insert a game installation successfully', () async {
        final installation = createTestInstallation();

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);
        expect(result.value, equals(installation));

        // Verify it's in the database
        final maps = await db.query('game_installations', where: 'id = ?', whereArgs: [installation.id]);
        expect(maps.length, equals(1));
        expect(maps.first['game_code'], equals('wh3'));
      });

      test('should fail when inserting duplicate ID', () async {
        final installation = createTestInstallation();
        await repository.insert(installation);

        final duplicate = createTestInstallation(gameName: 'Different Game');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return installation when found', () async {
        final installation = createTestInstallation();
        await repository.insert(installation);

        final result = await repository.getById(installation.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(installation.id));
        expect(result.value.gameCode, equals(installation.gameCode));
        expect(result.value.gameName, equals(installation.gameName));
      });

      test('should return error when installation not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no installations exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all installations ordered by game_name ASC', () async {
        final wh3 = createTestInstallation(
          id: 'wh3-install',
          gameCode: 'wh3',
          gameName: 'Total War: WARHAMMER III',
        );
        final rome = createTestInstallation(
          id: 'rome-install',
          gameCode: 'rome2',
          gameName: 'Total War: ROME II',
        );
        final troy = createTestInstallation(
          id: 'troy-install',
          gameCode: 'troy',
          gameName: 'A Total War Saga: TROY',
        );

        await repository.insert(wh3);
        await repository.insert(rome);
        await repository.insert(troy);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // Should be ordered by game_name ASC
        expect(result.value[0].gameName, equals('A Total War Saga: TROY'));
        expect(result.value[1].gameName, equals('Total War: ROME II'));
        expect(result.value[2].gameName, equals('Total War: WARHAMMER III'));
      });
    });

    group('update', () {
      test('should update installation successfully', () async {
        final installation = createTestInstallation();
        await repository.insert(installation);

        final updated = installation.copyWith(
          installationPath: 'D:\\NewPath\\Warhammer3',
        );
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.installationPath, equals('D:\\NewPath\\Warhammer3'));

        // Verify in database
        final getResult = await repository.getById(installation.id);
        expect(getResult.value.installationPath, equals('D:\\NewPath\\Warhammer3'));
      });

      test('should return error when installation not found', () async {
        final installation = createTestInstallation(id: 'non-existent');

        final result = await repository.update(installation);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete installation successfully', () async {
        final installation = createTestInstallation();
        await repository.insert(installation);

        final result = await repository.delete(installation.id);

        expect(result.isOk, isTrue);

        // Verify it's deleted
        final getResult = await repository.getById(installation.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when installation not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByGameCode', () {
      test('should return installation when game code found', () async {
        final installation = createTestInstallation(gameCode: 'wh3');
        await repository.insert(installation);

        final result = await repository.getByGameCode('wh3');

        expect(result.isOk, isTrue);
        expect(result.value.gameCode, equals('wh3'));
      });

      test('should return error when game code not found', () async {
        final result = await repository.getByGameCode('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getValid', () {
      test('should return only valid installations', () async {
        final valid1 = createTestInstallation(
          id: 'valid1',
          gameName: 'Game 1',
          isValid: true,
        );
        final valid2 = createTestInstallation(
          id: 'valid2',
          gameName: 'Game 2',
          isValid: true,
        );
        final invalid = createTestInstallation(
          id: 'invalid',
          gameName: 'Invalid Game',
          isValid: false,
        );

        await repository.insert(valid1);
        await repository.insert(valid2);
        await repository.insert(invalid);

        final result = await repository.getValid();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((i) => i.isValid), isTrue);
      });

      test('should return empty list when no valid installations', () async {
        final invalid = createTestInstallation(isValid: false);
        await repository.insert(invalid);

        final result = await repository.getValid();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should order valid installations by game_name ASC', () async {
        final z = createTestInstallation(
          id: 'z-game',
          gameName: 'Z Game',
          isValid: true,
        );
        final a = createTestInstallation(
          id: 'a-game',
          gameName: 'A Game',
          isValid: true,
        );

        await repository.insert(z);
        await repository.insert(a);

        final result = await repository.getValid();

        expect(result.isOk, isTrue);
        expect(result.value[0].gameName, equals('A Game'));
        expect(result.value[1].gameName, equals('Z Game'));
      });
    });

    group('boolean fields', () {
      test('should correctly store and retrieve isAutoDetected', () async {
        final autoDetected = createTestInstallation(
          id: 'auto',
          isAutoDetected: true,
        );
        final manual = createTestInstallation(
          id: 'manual',
          gameCode: 'rome2',
          isAutoDetected: false,
        );

        await repository.insert(autoDetected);
        await repository.insert(manual);

        final autoResult = await repository.getById('auto');
        final manualResult = await repository.getById('manual');

        expect(autoResult.value.isAutoDetected, isTrue);
        expect(manualResult.value.isAutoDetected, isFalse);
      });

      test('should correctly store and retrieve isValid', () async {
        final valid = createTestInstallation(
          id: 'valid',
          isValid: true,
        );
        final invalid = createTestInstallation(
          id: 'invalid',
          gameCode: 'rome2',
          isValid: false,
        );

        await repository.insert(valid);
        await repository.insert(invalid);

        final validResult = await repository.getById('valid');
        final invalidResult = await repository.getById('invalid');

        expect(validResult.value.isValid, isTrue);
        expect(invalidResult.value.isValid, isFalse);
      });
    });

    group('nullable fields', () {
      test('should handle null installation path', () async {
        final installation = GameInstallation(
          id: 'no-path',
          gameCode: 'wh3',
          gameName: 'Total War: WARHAMMER III',
          installationPath: null,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('no-path');
        expect(getResult.value.installationPath, isNull);
      });

      test('should handle null steam workshop path', () async {
        final installation = GameInstallation(
          id: 'no-workshop',
          gameCode: 'wh3',
          gameName: 'Total War: WARHAMMER III',
          steamWorkshopPath: null,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('no-workshop');
        expect(getResult.value.steamWorkshopPath, isNull);
      });

      test('should handle null lastValidatedAt', () async {
        final installation = createTestInstallation(lastValidatedAt: null);

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(installation.id);
        expect(getResult.value.lastValidatedAt, isNull);
      });
    });

    group('edge cases', () {
      test('should handle paths with special characters', () async {
        final installation = createTestInstallation(
          installationPath: 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Total War WARHAMMER III',
        );

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(installation.id);
        expect(getResult.value.installationPath, contains('Program Files (x86)'));
      });

      test('should handle very long paths', () async {
        final longPath = 'C:\\${'a' * 200}\\game';
        final installation = createTestInstallation(
          installationPath: longPath,
        );

        final result = await repository.insert(installation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(installation.id);
        expect(getResult.value.installationPath, equals(longPath));
      });

      test('should update validation timestamp', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final installation = createTestInstallation(lastValidatedAt: null);
        await repository.insert(installation);

        final updated = installation.copyWith(lastValidatedAt: now);
        await repository.update(updated);

        final result = await repository.getById(installation.id);
        expect(result.value.lastValidatedAt, equals(now));
      });

      test('should handle updating isValid from true to false', () async {
        final installation = createTestInstallation(isValid: true);
        await repository.insert(installation);

        final invalidated = installation.copyWith(isValid: false);
        await repository.update(invalidated);

        final result = await repository.getById(installation.id);
        expect(result.value.isValid, isFalse);

        // Also verify getValid doesn't return it anymore
        final validResult = await repository.getValid();
        expect(validResult.value.where((i) => i.id == installation.id), isEmpty);
      });
    });

    group('multiple games', () {
      test('should support multiple Total War games', () async {
        final games = [
          createTestInstallation(
            id: 'wh3',
            gameCode: 'wh3',
            gameName: 'Total War: WARHAMMER III',
            steamAppId: '1142710',
          ),
          createTestInstallation(
            id: 'wh2',
            gameCode: 'wh2',
            gameName: 'Total War: WARHAMMER II',
            steamAppId: '594570',
          ),
          createTestInstallation(
            id: 'rome2',
            gameCode: 'rome2',
            gameName: 'Total War: ROME II',
            steamAppId: '214950',
          ),
          createTestInstallation(
            id: 'troy',
            gameCode: 'troy',
            gameName: 'A Total War Saga: TROY',
            steamAppId: '1099410',
          ),
        ];

        for (final game in games) {
          await repository.insert(game);
        }

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(4));
      });

      test('should find specific game by code', () async {
        final wh3 = createTestInstallation(
          id: 'wh3',
          gameCode: 'wh3',
        );
        final rome2 = createTestInstallation(
          id: 'rome2',
          gameCode: 'rome2',
        );

        await repository.insert(wh3);
        await repository.insert(rome2);

        final result = await repository.getByGameCode('rome2');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('rome2'));
      });
    });
  });
}
