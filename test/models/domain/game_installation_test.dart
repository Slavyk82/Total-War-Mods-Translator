import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/game_installation.dart';

void main() {
  GameInstallation makeInstallation({
    String id = 'gi-1',
    String gameCode = 'wh3',
    String gameName = 'Total War: WARHAMMER III',
    String? installationPath,
    String? steamWorkshopPath,
    String? steamAppId,
    bool isAutoDetected = false,
    bool isValid = true,
    int? lastValidatedAt,
    int createdAt = 100,
    int updatedAt = 200,
  }) {
    return GameInstallation(
      id: id,
      gameCode: gameCode,
      gameName: gameName,
      installationPath: installationPath,
      steamWorkshopPath: steamWorkshopPath,
      steamAppId: steamAppId,
      isAutoDetected: isAutoDetected,
      isValid: isValid,
      lastValidatedAt: lastValidatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const installation = GameInstallation(
        id: 'id',
        gameCode: 'wh3',
        gameName: 'WH3',
        createdAt: 1,
        updatedAt: 2,
      );
      expect(installation.installationPath, isNull);
      expect(installation.steamWorkshopPath, isNull);
      expect(installation.steamAppId, isNull);
      expect(installation.isAutoDetected, isFalse);
      expect(installation.isValid, isTrue);
      expect(installation.lastValidatedAt, isNull);
    });
  });

  group('boolean getters', () {
    test('isValidInstallation mirrors isValid', () {
      expect(makeInstallation(isValid: true).isValidInstallation, isTrue);
      expect(makeInstallation(isValid: false).isValidInstallation, isFalse);
    });

    test('hasValidPaths', () {
      expect(
        makeInstallation(installationPath: 'C:/games').hasValidPaths,
        isTrue,
      );
      expect(makeInstallation(installationPath: null).hasValidPaths, isFalse);
      expect(makeInstallation(installationPath: '').hasValidPaths, isFalse);
    });

    test('hasWorkshopPath', () {
      expect(
        makeInstallation(steamWorkshopPath: 'C:/workshop').hasWorkshopPath,
        isTrue,
      );
      expect(
        makeInstallation(steamWorkshopPath: null).hasWorkshopPath,
        isFalse,
      );
      expect(
        makeInstallation(steamWorkshopPath: '').hasWorkshopPath,
        isFalse,
      );
    });
  });

  group('needsValidation', () {
    test('is true when never validated', () {
      expect(makeInstallation(lastValidatedAt: null).needsValidation, isTrue);
    });

    test('is false when validated recently', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        makeInstallation(lastValidatedAt: nowSec).needsValidation,
        isFalse,
      );
    });

    test('is true when validated more than 24 hours ago', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        makeInstallation(lastValidatedAt: nowSec - 2 * 86400).needsValidation,
        isTrue,
      );
    });
  });

  group('displayName', () {
    test('plain game name when valid', () {
      expect(
        makeInstallation(gameName: 'WH3', isValid: true).displayName,
        'WH3',
      );
    });

    test('tags invalid installations', () {
      expect(
        makeInstallation(gameName: 'WH3', isValid: false).displayName,
        'WH3 (Invalid)',
      );
    });
  });

  group('copyWith', () {
    final base = makeInstallation(
      id: 'a',
      gameCode: 'wh3',
      gameName: 'WH3',
      installationPath: 'path',
      steamWorkshopPath: 'workshop',
      steamAppId: '1142710',
      isAutoDetected: true,
      isValid: true,
      lastValidatedAt: 10,
      createdAt: 100,
      updatedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(gameCode: 'z').gameCode, 'z');
      expect(base.copyWith(gameName: 'z').gameName, 'z');
      expect(base.copyWith(installationPath: 'z').installationPath, 'z');
      expect(base.copyWith(steamWorkshopPath: 'z').steamWorkshopPath, 'z');
      expect(base.copyWith(steamAppId: 'z').steamAppId, 'z');
      expect(base.copyWith(isAutoDetected: false).isAutoDetected, isFalse);
      expect(base.copyWith(isValid: false).isValid, isFalse);
      expect(base.copyWith(lastValidatedAt: 99).lastValidatedAt, 99);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(isValid: false);
      expect(copy.id, base.id);
      expect(copy.gameCode, base.gameCode);
      expect(copy.gameName, base.gameName);
      expect(copy.installationPath, base.installationPath);
      expect(copy.steamWorkshopPath, base.steamWorkshopPath);
      expect(copy.steamAppId, base.steamAppId);
      expect(copy.isAutoDetected, base.isAutoDetected);
      expect(copy.lastValidatedAt, base.lastValidatedAt);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('JSON', () {
    final full = makeInstallation(
      id: 'a',
      gameCode: 'wh3',
      gameName: 'WH3',
      installationPath: 'path',
      steamWorkshopPath: 'workshop',
      steamAppId: '1142710',
      isAutoDetected: true,
      isValid: false,
      lastValidatedAt: 10,
      createdAt: 100,
      updatedAt: 200,
    );

    test('toJson uses snake_case keys and int booleans', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['game_code'], 'wh3');
      expect(json['game_name'], 'WH3');
      expect(json['installation_path'], 'path');
      expect(json['steam_workshop_path'], 'workshop');
      expect(json['steam_app_id'], '1142710');
      expect(json['is_auto_detected'], 1);
      expect(json['is_valid'], 0);
      expect(json['last_validated_at'], 10);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = GameInstallation.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes int booleans and applies defaults', () {
      final decoded = GameInstallation.fromJson({
        'id': 'a',
        'game_code': 'wh3',
        'game_name': 'WH3',
        'is_auto_detected': 1,
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.isAutoDetected, isTrue);
      expect(decoded.isValid, isTrue);
      expect(decoded.installationPath, isNull);
    });
  });

  group('equality and hashCode', () {
    final a = makeInstallation(
      installationPath: 'path',
      steamWorkshopPath: 'workshop',
      steamAppId: 'app',
      lastValidatedAt: 10,
    );

    test('identical instance is equal', () {
      expect(a == a, isTrue);
    });

    test('equal field-for-field copies are equal with same hashCode', () {
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(gameCode: 'z'), isFalse);
      expect(a == a.copyWith(gameName: 'z'), isFalse);
      expect(a == a.copyWith(installationPath: 'z'), isFalse);
      expect(a == a.copyWith(steamWorkshopPath: 'z'), isFalse);
      expect(a == a.copyWith(steamAppId: 'z'), isFalse);
      expect(a == a.copyWith(isAutoDetected: true), isFalse);
      expect(a == a.copyWith(isValid: false), isFalse);
      expect(a == a.copyWith(lastValidatedAt: 99), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, gameCode, gameName and isValid', () {
      final installation = makeInstallation(
        id: 'a',
        gameCode: 'wh3',
        gameName: 'WH3',
        isValid: true,
      );
      expect(
        installation.toString(),
        'GameInstallation(id: a, gameCode: wh3, gameName: WH3, isValid: true)',
      );
    });
  });
}
