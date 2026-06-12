import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/game/game_localization_service.dart';

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockGameLocalizationService extends Mock
    implements GameLocalizationService {}

/// Test double for [SelectedGame] returning a fixed game without touching
/// settings services. Mirrors the established fake in the activity tests.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _game = ConfiguredGame(code: 'wh3', name: 'WH3', path: 'C:/wh3');

GameInstallation _installation({String? path}) => GameInstallation(
      id: 'inst-1',
      gameCode: 'wh3',
      gameName: 'WH3',
      installationPath: path,
      createdAt: 0,
      updatedAt: 0,
    );

Language _lang(String id, String code) =>
    Language(id: id, code: code, name: code, nativeName: code);

DetectedLocalPack _pack(String code) => DetectedLocalPack(
      languageCode: code,
      languageName: code,
      packFilePath: 'local_$code.pack',
      fileSizeBytes: 0,
      lastModified: DateTime(2026, 1, 1),
    );

void main() {
  late _MockGameInstallationRepository gameRepo;
  late _MockLanguageRepository langRepo;
  late _MockGameLocalizationService locService;

  setUp(() {
    gameRepo = _MockGameInstallationRepository();
    langRepo = _MockLanguageRepository();
    locService = _MockGameLocalizationService();
  });

  ProviderContainer makeContainer({ConfiguredGame? selected = _game}) {
    final container = ProviderContainer(
      overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(selected)),
        gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
        languageRepositoryProvider.overrideWithValue(langRepo),
        gameLocalizationServiceProvider.overrideWithValue(locService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('detectedLocalPacksProvider', () {
    test('returns empty when no game is selected', () async {
      final container = makeContainer(selected: null);

      expect(await container.read(detectedLocalPacksProvider.future), isEmpty);
      verifyNever(() => gameRepo.getByGameCode(any()));
    });

    test('returns empty when the installation lookup errors', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer((_) async =>
          Err<GameInstallation, TWMTDatabaseException>(
              const TWMTDatabaseException('not found')));

      final container = makeContainer();

      expect(await container.read(detectedLocalPacksProvider.future), isEmpty);
    });

    test('returns empty when the installation has no path', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_installation(path: null)));

      final container = makeContainer();

      expect(await container.read(detectedLocalPacksProvider.future), isEmpty);
      verifyNever(() => locService.detectLocalizationPacks(any()));
    });

    test('returns the detected packs for a valid installation', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_installation(path: 'C:/wh3/data')));
      when(() => locService.detectLocalizationPacks('C:/wh3/data'))
          .thenAnswer((_) async => [_pack('cn'), _pack('jp')]);

      final container = makeContainer();
      final packs = await container.read(detectedLocalPacksProvider.future);

      expect(packs.map((p) => p.languageCode), ['cn', 'jp']);
    });
  });

  group('hasLocalPacksProvider', () {
    test('is false when no packs are detected', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_installation(path: 'C:/wh3/data')));
      when(() => locService.detectLocalizationPacks('C:/wh3/data'))
          .thenAnswer((_) async => <DetectedLocalPack>[]);

      final container = makeContainer();

      expect(await container.read(hasLocalPacksProvider.future), isFalse);
    });

    test('is true when at least one pack is detected', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_installation(path: 'C:/wh3/data')));
      when(() => locService.detectLocalizationPacks('C:/wh3/data'))
          .thenAnswer((_) async => [_pack('cn')]);

      final container = makeContainer();

      expect(await container.read(hasLocalPacksProvider.future), isTrue);
    });
  });

  group('availableTargetLanguagesProvider', () {
    test('returns empty when the language lookup errors', () async {
      when(() => langRepo.getAll()).thenAnswer((_) async =>
          Err<List<Language>, TWMTDatabaseException>(
              const TWMTDatabaseException('db down')));

      final container = makeContainer();

      expect(
        await container.read(availableTargetLanguagesProvider('en').future),
        isEmpty,
      );
    });

    test('excludes the source language (case-insensitive)', () async {
      when(() => langRepo.getAll()).thenAnswer((_) async => Ok([
            _lang('id-en', 'en'),
            _lang('id-de', 'de'),
            _lang('id-fr', 'fr'),
          ]));

      final container = makeContainer();
      final result =
          await container.read(availableTargetLanguagesProvider('EN').future);

      expect(result.map((l) => l.code), ['de', 'fr']);
    });
  });

  group('gameTranslationProjectsProvider', () {
    test('returns empty when no game is selected', () async {
      final container = makeContainer(selected: null);

      expect(
        await container.read(gameTranslationProjectsProvider.future),
        isEmpty,
      );
    });
  });
}
