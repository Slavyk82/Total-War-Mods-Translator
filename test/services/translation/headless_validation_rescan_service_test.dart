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

    // Wrap the call in a FutureProvider so it receives a Ref — the
    // idiomatic way to test a Ref-taking function from a ProviderContainer.
    final resultProvider = FutureProvider<RescanResult>((ref) {
      return runHeadlessValidationRescan(
        ref: ref,
        projectLanguageId: 'pl-1',
      );
    });

    final container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(resultProvider.future);

    expect(result.scanned, 0);
    expect(result.needsReviewTotal, 0);
  });
}
