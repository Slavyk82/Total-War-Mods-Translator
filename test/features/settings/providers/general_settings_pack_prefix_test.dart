import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/providers/settings_providers.dart';

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  late MockSettingsService mockService;
  late ProviderContainer container;

  setUp(() {
    mockService = MockSettingsService();

    // Permissive stubs so GeneralSettings.build() can complete.
    when(() => mockService.getString(any(),
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => '');
    when(() => mockService.getBool(any(),
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => true);
    when(() => mockService.getPackPrefix())
        .thenAnswer((_) async => '!!!!!!!!!!');
    when(() => mockService.setString(any(), any()))
        .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

    container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(mockService),
    ]);
  });

  tearDown(() => container.dispose());

  test('build() exposes the pack prefix', () async {
    when(() => mockService.getPackPrefix())
        .thenAnswer((_) async => 'zzz_');

    final settings = await container.read(generalSettingsProvider.future);

    expect(settings[SettingsKeys.packPrefix], 'zzz_');
  });

  test('updatePackPrefix sanitizes before persisting', () async {
    await container.read(generalSettingsProvider.future);

    await container
        .read(generalSettingsProvider.notifier)
        .updatePackPrefix(r'zz/z*_');

    verify(() => mockService.setString(SettingsKeys.packPrefix, 'zzz_'))
        .called(1);
  });
}
