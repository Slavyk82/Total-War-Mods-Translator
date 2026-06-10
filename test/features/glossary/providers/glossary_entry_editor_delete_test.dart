// Regression tests for GlossaryEntryEditor.delete().
//
// 2026-06-10 review (HIGH): delete() used to await service.deleteEntry()
// and DISCARD the Result, then unconditionally clear editor state. Verified
// consequences:
//   (a) failed deletes (DB error / entry not found) surfaced as a success
//       toast, because the only caller (GlossaryDataGrid._deleteEntry) shows
//       the success toast on the non-throwing path;
//   (b) even successful deletes left the deleted row visible in the grid,
//       because nothing on the delete path invalidated the cached
//       glossaryEntries / glossarySearchResults / glossaryStatistics
//       providers the grid watches.
//
// These tests lock in the fixed contract, mirroring save() in the same
// notifier and TmDeleteState.deleteEntry:
//   - on Err the method throws (so the caller's catch shows the error toast)
//     and does NOT clear editor state nor invalidate anything;
//   - on Ok it clears editor state and invalidates the three providers the
//     grid can be watching.
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryService extends Mock implements IGlossaryService {}

const _glossaryId = 'glossary-1';

GlossaryEntry _entry(String id) => GlossaryEntry(
      id: id,
      glossaryId: _glossaryId,
      targetLanguageCode: 'fr',
      sourceTerm: 'Sword',
      targetTerm: 'Épée',
      createdAt: 1700000000,
      updatedAt: 1700000000,
    );

void main() {
  late _MockGlossaryService service;
  late ProviderContainer container;

  setUp(() {
    service = _MockGlossaryService();

    // Read-side stubs used by the providers the datagrid watches.
    when(() => service.getEntriesByGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => Ok([_entry('e1')]));
    when(() => service.searchEntries(
          query: any(named: 'query'),
          glossaryIds: any(named: 'glossaryIds'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => Ok([_entry('e1')]));
    when(() => service.getGlossaryStats(any()))
        .thenAnswer((_) async => const Ok(<String, dynamic>{
              'totalEntries': 1,
            }));

    container = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        glossaryServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Reads (and keeps alive) the three providers the datagrid swaps between.
  Future<void> warmUpGridProviders() async {
    // listen() keeps the autoDispose providers cached, exactly like the
    // mounted datagrid does.
    container.listen(
      glossaryEntriesProvider(glossaryId: _glossaryId),
      (previous, next) {},
    );
    container.listen(
      glossarySearchResultsProvider(query: 'Sword'),
      (previous, next) {},
    );
    container.listen(
      glossaryStatisticsProvider(_glossaryId),
      (previous, next) {},
    );
    await container
        .read(glossaryEntriesProvider(glossaryId: _glossaryId).future);
    await container
        .read(glossarySearchResultsProvider(query: 'Sword').future);
    await container.read(glossaryStatisticsProvider(_glossaryId).future);
  }

  test('delete throws on Err so the caller can show the error toast, '
      'and does not clear editor state or invalidate entry providers',
      () async {
    when(() => service.deleteEntry(any())).thenAnswer(
      (_) async => const Err(GlossaryEntryNotFoundException('e1')),
    );

    await warmUpGridProviders();

    final notifier = container.read(glossaryEntryEditorProvider.notifier);
    notifier.edit(_entry('e1'));

    await expectLater(
      notifier.delete('e1'),
      throwsA(isA<Exception>()),
      reason: 'A failed delete must throw so GlossaryDataGrid._deleteEntry '
          'shows the error toast instead of the success one',
    );

    expect(
      container.read(glossaryEntryEditorProvider),
      isNotNull,
      reason: 'Editor state must not be cleared when the delete failed',
    );

    // The cached read-side providers must not have been refetched.
    await container
        .read(glossaryEntriesProvider(glossaryId: _glossaryId).future);
    await container
        .read(glossarySearchResultsProvider(query: 'Sword').future);
    await container.read(glossaryStatisticsProvider(_glossaryId).future);
    verify(() => service.getEntriesByGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(1);
    verify(() => service.searchEntries(
          query: any(named: 'query'),
          glossaryIds: any(named: 'glossaryIds'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(1);
    verify(() => service.getGlossaryStats(any())).called(1);
  });

  test('delete on Ok clears editor state and invalidates the entries, '
      'search-results and statistics providers the grid watches', () async {
    when(() => service.deleteEntry(any()))
        .thenAnswer((_) async => const Ok(null));

    await warmUpGridProviders();

    final notifier = container.read(glossaryEntryEditorProvider.notifier);
    notifier.edit(_entry('e1'));

    await notifier.delete('e1');

    verify(() => service.deleteEntry('e1')).called(1);

    expect(
      container.read(glossaryEntryEditorProvider),
      isNull,
      reason: 'Editor state must be cleared after a successful delete',
    );

    // Each provider must have been invalidated: re-reading them must hit the
    // service a second time instead of returning the stale cached list.
    await container
        .read(glossaryEntriesProvider(glossaryId: _glossaryId).future);
    await container
        .read(glossarySearchResultsProvider(query: 'Sword').future);
    await container.read(glossaryStatisticsProvider(_glossaryId).future);
    verify(() => service.getEntriesByGlossary(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(2);
    verify(() => service.searchEntries(
          query: any(named: 'query'),
          glossaryIds: any(named: 'glossaryIds'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).called(2);
    verify(() => service.getGlossaryStats(any())).called(2);
  });
}
