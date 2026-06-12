import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/config/settings_keys.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/services/mods/game_installation_sync_service.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../helpers/noop_logger.dart';

class MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class MockSettingsService extends Mock implements SettingsService {}

const _wh3Name = 'Total War: WARHAMMER III';
const _wh3AppId = '1142710';

GameInstallation _existing({
  String installationPath = r'C:\Games\wh3',
  String? steamWorkshopPath = r'C:\Steam\workshop\content\1142710',
  String? steamAppId = _wh3AppId,
}) {
  return GameInstallation(
    id: 'gi1',
    gameCode: 'wh3',
    gameName: _wh3Name,
    installationPath: installationPath,
    steamWorkshopPath: steamWorkshopPath,
    steamAppId: steamAppId,
    createdAt: 1,
    updatedAt: 1,
  );
}

void main() {
  late MockGameInstallationRepository repo;
  late MockSettingsService settings;
  late GameInstallationSyncService service;

  setUpAll(() {
    registerFallbackValue(_existing());
  });

  setUp(() {
    repo = MockGameInstallationRepository();
    settings = MockSettingsService();
    service = GameInstallationSyncService(
      gameInstallationRepository: repo,
      settingsService: settings,
      logger: NoopLogger(),
    );

    // Default: every settings key is empty unless overridden.
    when(() => settings.getString(any())).thenAnswer((_) async => '');
    when(() => repo.insert(any()))
        .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));
    when(() => repo.update(any()))
        .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));
  });

  void stubGamePath(String value) {
    when(() => settings.getString(SettingsKeys.gamePathWh3))
        .thenAnswer((_) async => value);
  }

  group('syncGame', () {
    test('rejects an unknown game code', () async {
      final result = await service.syncGame('not_a_game');
      expect(result, isA<Err>());
      expect((result as Err).error.message, contains('Unknown game code'));
      verifyNever(() => repo.getByGameCode(any()));
    });

    test('skips silently when no path is configured', () async {
      // gamePathWh3 defaults to '' from setUp.
      final result = await service.syncGame('wh3');
      expect(result, isA<Ok>());
      verifyNever(() => repo.getByGameCode(any()));
    });

    test('creates a new installation with detected fields', () async {
      stubGamePath(r'C:\does\not\exist\wh3');
      when(() => repo.getByGameCode('wh3'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));

      final result = await service.syncGame('wh3');
      expect(result, isA<Ok>());

      final created =
          verify(() => repo.insert(captureAny())).captured.single
              as GameInstallation;
      expect(created.gameCode, 'wh3');
      expect(created.gameName, _wh3Name);
      expect(created.steamAppId, _wh3AppId);
      expect(created.installationPath, r'C:\does\not\exist\wh3');
      // No base workshop path and the auto-detect dir doesn't exist -> null.
      expect(created.steamWorkshopPath, isNull);
      // Path doesn't exist -> invalid.
      expect(created.isValid, isFalse);
    });

    test('detects the workshop path from a configured base path', () async {
      final tempRoot =
          await Directory.systemTemp.createTemp('gi_sync_test_');
      addTearDown(() => tempRoot.delete(recursive: true));
      // base/<appId> must exist for detection to succeed.
      Directory('${tempRoot.path}/$_wh3AppId').createSync();

      stubGamePath(r'C:\Games\wh3');
      when(() => settings.getString(SettingsKeys.workshopPath))
          .thenAnswer((_) async => tempRoot.path);
      when(() => repo.getByGameCode('wh3'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));

      await service.syncGame('wh3');

      final created =
          verify(() => repo.insert(captureAny())).captured.single
              as GameInstallation;
      expect(created.steamWorkshopPath, contains(_wh3AppId));
    });

    test('does not update an installation that is already in sync', () async {
      stubGamePath(r'C:\Games\wh3');
      when(() => repo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_existing(installationPath: r'C:\Games\wh3')),
      );

      final result = await service.syncGame('wh3');
      expect(result, isA<Ok>());
      verifyNever(() => repo.update(any()));
    });

    test('updates an installation when the install path changed', () async {
      stubGamePath(r'C:\Games\wh3_new');
      when(() => repo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_existing(installationPath: r'C:\Games\wh3_old')),
      );

      await service.syncGame('wh3');

      final updated =
          verify(() => repo.update(captureAny())).captured.single
              as GameInstallation;
      expect(updated.installationPath, r'C:\Games\wh3_new');
    });

    test('re-detects the workshop path when it is missing', () async {
      stubGamePath(r'C:\Games\wh3');
      when(() => repo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_existing(steamWorkshopPath: null)),
      );

      await service.syncGame('wh3');

      // Missing workshop path triggers an update.
      verify(() => repo.update(any())).called(1);
    });

    test('updates when the stored workshop path is stale vs the base setting',
        () async {
      final tempRoot =
          await Directory.systemTemp.createTemp('gi_sync_stale_');
      addTearDown(() => tempRoot.delete(recursive: true));
      Directory('${tempRoot.path}/$_wh3AppId').createSync();

      stubGamePath(r'C:\Games\wh3');
      when(() => settings.getString(SettingsKeys.workshopPath))
          .thenAnswer((_) async => tempRoot.path);
      // Stored workshop path does not contain the new base path -> stale.
      when(() => repo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_existing(
          installationPath: r'C:\Games\wh3',
          steamWorkshopPath: r'D:\old\workshop\1142710',
        )),
      );

      await service.syncGame('wh3');

      final updated =
          verify(() => repo.update(captureAny())).captured.single
              as GameInstallation;
      // Re-detected against the configured base path.
      expect(updated.steamWorkshopPath, contains(tempRoot.path));
    });

    test('surfaces an update failure as an Err', () async {
      stubGamePath(r'C:\Games\wh3_new');
      when(() => repo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_existing(installationPath: r'C:\Games\wh3_old')),
      );
      when(() => repo.update(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('update boom')));

      final result = await service.syncGame('wh3');
      expect(result, isA<Err>());
      expect((result as Err).error.message,
          contains('Failed to update game installation'));
    });

    test('marks a new installation valid when the path holds an .exe', () async {
      final gameDir = await Directory.systemTemp.createTemp('gi_sync_valid_');
      addTearDown(() => gameDir.delete(recursive: true));
      File('${gameDir.path}/launcher.exe').writeAsStringSync('MZ');

      stubGamePath(gameDir.path);
      when(() => repo.getByGameCode('wh3'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));

      await service.syncGame('wh3');

      final created =
          verify(() => repo.insert(captureAny())).captured.single
              as GameInstallation;
      expect(created.isValid, isTrue);
    });

    test('surfaces an insert failure as an Err', () async {
      stubGamePath(r'C:\does\not\exist\wh3');
      when(() => repo.getByGameCode('wh3'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));
      when(() => repo.insert(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('insert boom')));

      final result = await service.syncGame('wh3');
      expect(result, isA<Err>());
      expect((result as Err).error.message,
          contains('Failed to insert game installation'));
    });
  });

  group('syncAllGames', () {
    test('iterates every supported game and succeeds with no paths set',
        () async {
      final result = await service.syncAllGames();
      expect(result, isA<Ok>());
      // All paths empty -> no DB lookups at all.
      verifyNever(() => repo.getByGameCode(any()));
    });
  });
}
