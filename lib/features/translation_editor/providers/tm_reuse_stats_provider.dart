import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/models/domain/translation_version.dart';

part 'tm_reuse_stats_provider.g.dart';

/// Aggregate stats over translated rows for the editor status bar:
/// what fraction of finalized translations came from TM (exact/fuzzy/llm).
class TmReuseStats {
  final int translatedCount;
  final int reusedCount;
  final double reusePercentage;

  const TmReuseStats({
    required this.translatedCount,
    required this.reusedCount,
    required this.reusePercentage,
  });

  factory TmReuseStats.empty() => const TmReuseStats(
        translatedCount: 0,
        reusedCount: 0,
        reusePercentage: 0,
      );
}

/// Computes [TmReuseStats] from [translationRowsProvider]. Pure derivation;
/// auto-disposes per (projectId, languageId) family key.
@riverpod
Future<TmReuseStats> tmReuseStats(Ref ref, String projectId, String languageId) async {
  final rows = await ref.watch(translationRowsProvider(projectId, languageId).future);
  final translated = rows
      .where((r) => r.status == TranslationVersionStatus.translated)
      .toList();
  if (translated.isEmpty) return TmReuseStats.empty();
  final fromTm = translated.where((r) {
    final src = getTmSourceType(r);
    return src == TmSourceType.exactMatch ||
        src == TmSourceType.fuzzyMatch ||
        src == TmSourceType.llm;
  }).length;
  return TmReuseStats(
    translatedCount: translated.length,
    reusedCount: fromTm,
    reusePercentage: fromTm / translated.length * 100,
  );
}
