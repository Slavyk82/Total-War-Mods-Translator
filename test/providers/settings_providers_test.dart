import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/utils/pack_prefix_sanitizer.dart';

class MockSettingsService extends Mock implements SettingsService {}

/// Builds permissive stubs so a settings notifier `build()` can complete.
void _stubReads(MockSettingsService mock) {
  when(() => mock.getString(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => '');
  when(() => mock.getBool(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => true);
  when(() => mock.getInt(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => 500);
  when(() => mock.getPackPrefix()).thenAnswer((_) async => '!!!!!!!!!!');
  when(() => mock.setString(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setBool(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setInt(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
}

void main() {
  group('GeneralSettings notifier', () {
    late MockSettingsService mockService;
    late ProviderContainer container;

    setUp(() {
      mockService = MockSettingsService();
      _stubReads(mockService);

      container = ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(mockService),
      ]);
    });

    tearDown(() => container.dispose());

    test('build() maps every key from the mocked service', () async {
      // Distinct values so we can prove the map is built from the service.
      when(() => mockService.getString(SettingsKeys.gamePathWh3,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'C:/wh3');
      when(() => mockService.getString(SettingsKeys.workshopPath,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'C:/workshop');
      when(() => mockService.getString(SettingsKeys.rpfmPath,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'C:/rpfm.exe');
      when(() => mockService.getString(SettingsKeys.rpfmSchemaPath,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'C:/schemas');
      when(() => mockService.getString(SettingsKeys.defaultTargetLanguage,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'de');
      when(() => mockService.getBool(SettingsKeys.autoUpdate,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => false);
      when(() => mockService.getPackPrefix()).thenAnswer((_) async => 'pp_');

      final settings = await container.read(generalSettingsProvider.future);

      expect(settings[SettingsKeys.gamePathWh3], 'C:/wh3');
      expect(settings[SettingsKeys.workshopPath], 'C:/workshop');
      expect(settings[SettingsKeys.rpfmPath], 'C:/rpfm.exe');
      expect(settings[SettingsKeys.rpfmSchemaPath], 'C:/schemas');
      expect(settings[SettingsKeys.defaultTargetLanguage], 'de');
      // getBool result is stringified.
      expect(settings[SettingsKeys.autoUpdate], 'false');
      expect(settings[SettingsKeys.packPrefix], 'pp_');
    });

    test('build() exposes all nine game-path keys', () async {
      final settings = await container.read(generalSettingsProvider.future);

      for (final key in [
        SettingsKeys.gamePathWh3,
        SettingsKeys.gamePathWh2,
        SettingsKeys.gamePathWh,
        SettingsKeys.gamePathRome2,
        SettingsKeys.gamePathAttila,
        SettingsKeys.gamePathTroy,
        SettingsKeys.gamePath3k,
        SettingsKeys.gamePathPharaoh,
        SettingsKeys.gamePathPharaohDynasties,
      ]) {
        expect(settings.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('updateGamePath persists under the right key for a known code (clearing branch)',
        () async {
      await container.read(generalSettingsProvider.future);

      // Empty path => clearing branch, which SKIPS glossary auto-provisioning,
      // so no ServiceLocator dependency is touched.
      await container
          .read(generalSettingsProvider.notifier)
          .updateGamePath('wh3', '');

      verify(() => mockService.setString(SettingsKeys.gamePathWh3, '')).called(1);
    });

    test('updateGamePath maps each known game code to its key (clearing branch)',
        () async {
      await container.read(generalSettingsProvider.future);
      final notifier = container.read(generalSettingsProvider.notifier);

      final cases = <String, String>{
        'wh3': SettingsKeys.gamePathWh3,
        'wh2': SettingsKeys.gamePathWh2,
        'wh': SettingsKeys.gamePathWh,
        'rome2': SettingsKeys.gamePathRome2,
        'attila': SettingsKeys.gamePathAttila,
        'troy': SettingsKeys.gamePathTroy,
        '3k': SettingsKeys.gamePath3k,
        'pharaoh': SettingsKeys.gamePathPharaoh,
        'pharaoh_dynasties': SettingsKeys.gamePathPharaohDynasties,
      };

      for (final entry in cases.entries) {
        await notifier.updateGamePath(entry.key, '');
        verify(() => mockService.setString(entry.value, '')).called(1);
      }
    });

    test('updateGamePath throws ArgumentError for an unknown game code', () async {
      await container.read(generalSettingsProvider.future);

      expect(
        () => container
            .read(generalSettingsProvider.notifier)
            .updateGamePath('unknown_game', ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('updateWorkshopPath persists under the workshop key', () async {
      await container.read(generalSettingsProvider.future);

      await container
          .read(generalSettingsProvider.notifier)
          .updateWorkshopPath('C:/ws');

      verify(() => mockService.setString(SettingsKeys.workshopPath, 'C:/ws'))
          .called(1);
    });

    test('updateRpfmPath persists under the rpfm key', () async {
      await container.read(generalSettingsProvider.future);

      await container
          .read(generalSettingsProvider.notifier)
          .updateRpfmPath('C:/rpfm.exe');

      verify(() => mockService.setString(SettingsKeys.rpfmPath, 'C:/rpfm.exe'))
          .called(1);
    });

    test('updateRpfmSchemaPath persists under the schema key', () async {
      await container.read(generalSettingsProvider.future);

      await container
          .read(generalSettingsProvider.notifier)
          .updateRpfmSchemaPath('C:/schemas');

      verify(() =>
              mockService.setString(SettingsKeys.rpfmSchemaPath, 'C:/schemas'))
          .called(1);
    });

    test('updateDefaultTargetLanguage persists under the language key', () async {
      await container.read(generalSettingsProvider.future);

      await container
          .read(generalSettingsProvider.notifier)
          .updateDefaultTargetLanguage('es');

      verify(() =>
              mockService.setString(SettingsKeys.defaultTargetLanguage, 'es'))
          .called(1);
    });

    test('updateAutoUpdate persists via setBool', () async {
      await container.read(generalSettingsProvider.future);

      await container
          .read(generalSettingsProvider.notifier)
          .updateAutoUpdate(false);

      verify(() => mockService.setBool(SettingsKeys.autoUpdate, false))
          .called(1);
    });

    test('updatePackPrefix sanitizes before persisting', () async {
      await container.read(generalSettingsProvider.future);

      const raw = r'zz/z*_';
      await container
          .read(generalSettingsProvider.notifier)
          .updatePackPrefix(raw);

      verify(() => mockService.setString(
            SettingsKeys.packPrefix,
            sanitizePackPrefix(raw),
          )).called(1);
      // Sanity-check the expected sanitized form is what we asserted.
      expect(sanitizePackPrefix(raw), 'zzz_');
    });
  });

  group('LlmProviderSettings notifier', () {
    late MockSettingsService mockService;
    late ProviderContainer container;

    // The exact channel the flutter_secure_storage MethodChannel platform
    // implementation talks to (confirmed in the installed
    // flutter_secure_storage_platform_interface-1.1.2 source).
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    setUp(() {
      // Required so the platform MethodChannel can be mocked.
      TestWidgetsFlutterBinding.ensureInitialized();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return null; // no stored key
          case 'write':
            return null;
          case 'readAll':
            return <String, String>{};
          case 'delete':
            return null;
          case 'deleteAll':
            return null;
          case 'containsKey':
            return false;
          default:
            return null;
        }
      });

      mockService = MockSettingsService();
      _stubReads(mockService);

      container = ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(mockService),
      ]);
    });

    tearDown(() {
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    test('build() defaults API keys to empty and reads non-secret fields',
        () async {
      when(() => mockService.getString(SettingsKeys.activeProvider,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'anthropic');
      when(() => mockService.getString(SettingsKeys.anthropicModel,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'claude-x');
      when(() => mockService.getString(SettingsKeys.openaiModel,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'gpt-x');
      when(() => mockService.getString(SettingsKeys.deeplPlan,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'pro');
      when(() => mockService.getInt(SettingsKeys.rateLimit,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 42);

      final settings =
          await container.read(llmProviderSettingsProvider.future);

      // Non-secret fields from the mocked SettingsService.
      expect(settings[SettingsKeys.activeProvider], 'anthropic');
      expect(settings[SettingsKeys.anthropicModel], 'claude-x');
      expect(settings[SettingsKeys.openaiModel], 'gpt-x');
      expect(settings[SettingsKeys.deeplPlan], 'pro');
      expect(settings[SettingsKeys.rateLimit], '42');

      // Secret fields default to '' when secure storage returns null.
      expect(settings[SettingsKeys.anthropicApiKey], '');
      expect(settings[SettingsKeys.openaiApiKey], '');
      expect(settings[SettingsKeys.deeplApiKey], '');
      expect(settings[SettingsKeys.deepseekApiKey], '');
      expect(settings[SettingsKeys.geminiApiKey], '');
    });

    test('updateActiveProvider persists via setString', () async {
      await container.read(llmProviderSettingsProvider.future);

      await container
          .read(llmProviderSettingsProvider.notifier)
          .updateActiveProvider('openai');

      verify(() => mockService.setString(SettingsKeys.activeProvider, 'openai'))
          .called(1);
    });

    test('updateAnthropicModel persists via setString', () async {
      await container.read(llmProviderSettingsProvider.future);

      await container
          .read(llmProviderSettingsProvider.notifier)
          .updateAnthropicModel('claude-3');

      verify(() =>
              mockService.setString(SettingsKeys.anthropicModel, 'claude-3'))
          .called(1);
    });

    test('updateOpenaiModel persists via setString', () async {
      await container.read(llmProviderSettingsProvider.future);

      await container
          .read(llmProviderSettingsProvider.notifier)
          .updateOpenaiModel('gpt-4');

      verify(() => mockService.setString(SettingsKeys.openaiModel, 'gpt-4'))
          .called(1);
    });

    test('updateDeeplPlan persists via setString', () async {
      await container.read(llmProviderSettingsProvider.future);

      await container
          .read(llmProviderSettingsProvider.notifier)
          .updateDeeplPlan('pro');

      verify(() => mockService.setString(SettingsKeys.deeplPlan, 'pro'))
          .called(1);
    });

    test('updateRateLimit persists via setInt', () async {
      await container.read(llmProviderSettingsProvider.future);

      await container
          .read(llmProviderSettingsProvider.notifier)
          .updateRateLimit(123);

      verify(() => mockService.setInt(SettingsKeys.rateLimit, 123)).called(1);
    });

    test('updateAnthropicApiKey completes without throwing (secure storage write)',
        () async {
      await container.read(llmProviderSettingsProvider.future);

      await expectLater(
        container
            .read(llmProviderSettingsProvider.notifier)
            .updateAnthropicApiKey('secret-key'),
        completes,
      );
    });

    test('updateOpenaiApiKey completes without throwing', () async {
      await container.read(llmProviderSettingsProvider.future);

      await expectLater(
        container
            .read(llmProviderSettingsProvider.notifier)
            .updateOpenaiApiKey('secret-key'),
        completes,
      );
    });

    test('updateDeeplApiKey completes without throwing', () async {
      await container.read(llmProviderSettingsProvider.future);

      await expectLater(
        container
            .read(llmProviderSettingsProvider.notifier)
            .updateDeeplApiKey('secret-key'),
        completes,
      );
    });

    test('updateDeepseekApiKey completes without throwing', () async {
      await container.read(llmProviderSettingsProvider.future);

      await expectLater(
        container
            .read(llmProviderSettingsProvider.notifier)
            .updateDeepseekApiKey('secret-key'),
        completes,
      );
    });

    test('updateGeminiApiKey completes without throwing', () async {
      await container.read(llmProviderSettingsProvider.future);

      await expectLater(
        container
            .read(llmProviderSettingsProvider.notifier)
            .updateGeminiApiKey('secret-key'),
        completes,
      );
    });
  });

  group('Bridge providers', () {
    test('settingsServiceProvider can be overridden with a mock', () {
      final mock = MockSettingsService();
      final container = ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(mock),
      ]);
      addTearDown(container.dispose);

      expect(container.read(settingsServiceProvider), same(mock));
    });

    test('AppConstants.defaultPackPrefix is a non-null sanity reference', () {
      // Guards the import used by the SettingsService default; keeps the
      // pack-prefix default observable from the provider layer.
      expect(AppConstants.defaultPackPrefix, isA<String>());
    });
  });
}
