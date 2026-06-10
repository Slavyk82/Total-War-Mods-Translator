// Regression test for TmExportState.exportToTmx option forwarding.
//
// 2026-06-10 review (LOW / L14): the TMX export dialog's scope and format
// options never reached the export service. The dialog now passes
// minUsageCount / includeMetadata / includeStats and this test locks in
// that the provider forwards them verbatim to
// ITranslationMemoryService.exportToTmx.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmService extends Mock implements ITranslationMemoryService {}

void main() {
  late _MockTmService service;
  late ProviderContainer container;

  setUp(() {
    service = _MockTmService();
    when(() => service.exportToTmx(
          outputPath: any(named: 'outputPath'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          minUsageCount: any(named: 'minUsageCount'),
          includeMetadata: any(named: 'includeMetadata'),
          includeStats: any(named: 'includeStats'),
        )).thenAnswer((_) async => const Ok(3));

    container = ProviderContainer(overrides: [
      loggingServiceProvider.overrideWithValue(FakeLogger()),
      translationMemoryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
  });

  test('forwards scope and format options to the service', () async {
    await container.read(tmExportStateProvider.notifier).exportToTmx(
          outputPath: r'C:\tmp\out.tmx',
          targetLanguageCode: 'fr',
          minUsageCount: 6,
          includeMetadata: false,
          includeStats: false,
        );

    verify(() => service.exportToTmx(
          outputPath: r'C:\tmp\out.tmx',
          targetLanguageCode: 'fr',
          minUsageCount: 6,
          includeMetadata: false,
          includeStats: false,
        )).called(1);

    final state = container.read(tmExportStateProvider);
    expect(state.asData?.value?.entriesExported, 3);
  });

  test('defaults export everything with metadata and stats', () async {
    await container.read(tmExportStateProvider.notifier).exportToTmx(
          outputPath: r'C:\tmp\out.tmx',
        );

    verify(() => service.exportToTmx(
          outputPath: r'C:\tmp\out.tmx',
          targetLanguageCode: null,
          minUsageCount: null,
          includeMetadata: true,
          includeStats: true,
        )).called(1);
  });
}
