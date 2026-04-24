import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/services/translation/headless_validation_rescan_service.dart';

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

void main() {
  late _MockVersionRepo repo;

  setUp(() {
    repo = _MockVersionRepo();
  });

  test('returns zero-valued result when no translated units', () async {
    // getByProjectLanguage returns an empty list (no versions at all).
    when(() => repo.getByProjectLanguage(any()))
        .thenAnswer((_) async => const Ok([]));

    // normalizeStatusEncoding is also called before the main fetch.
    when(() => repo.normalizeStatusEncoding())
        .thenAnswer((_) async => const Ok(0));

    final container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final result = await runHeadlessValidationRescan(
      ref: container,
      projectLanguageId: 'pl-1',
    );

    expect(result.scanned, 0);
    expect(result.needsReviewTotal, 0);
  });
}
