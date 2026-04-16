import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/tm_reuse_stats_provider.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

TranslationRow _row({
  required String id,
  required TranslationVersionStatus status,
  TranslationSource? source,
}) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'k',
    sourceText: 'src',
    sourceLocFile: 'l.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: status == TranslationVersionStatus.pending ? null : 'tr',
    status: status,
    translationSource: source ?? TranslationSource.unknown,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

void main() {
  group('tmReuseStatsProvider', () {
    test('returns empty when no translated rows exist', () async {
      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => [
              _row(id: '1', status: TranslationVersionStatus.pending),
              _row(id: '2', status: TranslationVersionStatus.pending),
            ]),
      ]);
      addTearDown(container.dispose);

      final stats = await container.read(tmReuseStatsProvider('p', 'fr').future);
      expect(stats.translatedCount, 0);
      expect(stats.reusedCount, 0);
      expect(stats.reusePercentage, 0);
    });

    test('returns 100 percent when every translated row is from TM', () async {
      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => [
              _row(
                id: '1',
                status: TranslationVersionStatus.translated,
                source: TranslationSource.tmExact,
              ),
              _row(
                id: '2',
                status: TranslationVersionStatus.translated,
                source: TranslationSource.tmFuzzy,
              ),
              _row(
                id: '3',
                status: TranslationVersionStatus.translated,
                source: TranslationSource.llm,
              ),
            ]),
      ]);
      addTearDown(container.dispose);

      final stats = await container.read(tmReuseStatsProvider('p', 'fr').future);
      expect(stats.translatedCount, 3);
      expect(stats.reusedCount, 3);
      expect(stats.reusePercentage, 100);
    });

    test('returns 50 percent when half manual half tm', () async {
      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => [
              _row(
                id: '1',
                status: TranslationVersionStatus.translated,
                source: TranslationSource.tmExact,
              ),
              _row(
                id: '2',
                status: TranslationVersionStatus.translated,
                source: TranslationSource.manual,
              ),
            ]),
      ]);
      addTearDown(container.dispose);

      final stats = await container.read(tmReuseStatsProvider('p', 'fr').future);
      expect(stats.translatedCount, 2);
      expect(stats.reusedCount, 1);
      expect(stats.reusePercentage, 50);
    });
  });
}
