// Regression test for GlossaryEntryEditorDialog._saveEntry.
//
// 2026-06-10 review (LOW / L13): the save path used to invalidate only
// glossaryEntriesProvider and glossaryStatisticsProvider. GlossaryDataGrid
// swaps its data source to glossarySearchResultsProvider whenever a search
// filter is active, so editing an entry from active search results left the
// grid showing the stale pre-save sourceTerm/targetTerm until the search
// text changed. The delete path (GlossaryEntryEditor.delete) already
// invalidates all three providers; this locks the save path to the same
// contract.
//
// The invalidation lives in the dialog widget (not the notifier), so the
// test pumps the real dialog, taps Save, and asserts that the cached search
// results provider is refetched afterwards.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_entry_editor.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryService extends Mock implements IGlossaryService {}

class _FakeGlossaryEntry extends Fake implements GlossaryEntry {}

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
  setUpAll(() {
    registerFallbackValue(_FakeGlossaryEntry());
  });

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
    when(() => service.updateEntry(any()))
        .thenAnswer((_) async => Ok(_entry('e1')));

    container = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        glossaryServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Reads (and keeps alive) the three providers the datagrid swaps between,
  /// exactly like the mounted datagrid does during an edit-from-search flow.
  Future<void> warmUpGridProviders() async {
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

  testWidgets(
      'saving an edited entry invalidates the entries, search-results and '
      'statistics providers the grid watches', (tester) async {
    await warmUpGridProviders();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => GlossaryEntryEditorDialog(
                      glossaryId: _glossaryId,
                      targetLanguageCode: 'fr',
                      entry: _entry('e1'),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.common.actions.save));
    await tester.pumpAndSettle();

    verify(() => service.updateEntry(any())).called(1);

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

    // Flush the success toast's auto-dismiss timer so the test ends with no
    // pending timers.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
