import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

/// One line in the bulk review dialog. Wraps a [NeedsReviewRow] with the
/// project context needed to show "which project it belongs to" in the UI
/// and to route per-row actions back to the right `projectLanguageId`.
class BulkReviewRow {
  final String projectId;
  final String projectName;
  final String projectLanguageId;
  final String unitId;
  final String versionId;
  final String key;
  final String sourceText;
  final String? translatedText;

  const BulkReviewRow({
    required this.projectId,
    required this.projectName,
    required this.projectLanguageId,
    required this.unitId,
    required this.versionId,
    required this.key,
    required this.sourceText,
    required this.translatedText,
  });
}

/// Flat list of every `needsReview` unit across the visible bulk scope for
/// the currently selected target language. One DB roundtrip per matching
/// project — cheap enough for the hundreds-of-projects case and dodges the
/// churn of adding an `IN (…)` cross-project query just for this view.
final bulkReviewRowsProvider =
    FutureProvider.autoDispose<List<BulkReviewRow>>((ref) async {
  final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
  final targetCode = ref.watch(bulkTargetLanguageProvider).asData?.value;
  final scope = scopeAsync.asData?.value;
  if (scope == null || targetCode == null) return const [];

  final versionRepo = ref.read(translationVersionRepositoryProvider);
  // Repair any rows that were written with the camelCase status encoding
  // (`'needsReview'`) instead of the canonical snake_case (`'needs_review'`).
  // Idempotent and bounded to mis-encoded rows — costs nothing once the DB
  // is clean. Without this, rows produced by an older
  // `setNeedsReviewForUnitKeys` would not match the dialog's filter.
  await versionRepo.normalizeStatusEncoding();
  final rows = <BulkReviewRow>[];

  for (final project in scope.matching) {
    final lang = project.languages.firstWhere(
      (l) => l.language?.code == targetCode,
      orElse: () => throw StateError('unreachable'),
    );
    final projectLanguageId = lang.projectLanguage.id;

    final result = await versionRepo.getNeedsReviewRows(
      projectLanguageId: projectLanguageId,
    );
    if (result.isErr) continue;

    for (final r in result.unwrap()) {
      rows.add(BulkReviewRow(
        projectId: project.project.id,
        projectName: project.project.name,
        projectLanguageId: projectLanguageId,
        unitId: r.unitId,
        versionId: r.versionId,
        key: r.key,
        sourceText: r.sourceText,
        translatedText: r.translatedText,
      ));
    }
  }

  rows.sort((a, b) {
    final byProject = a.projectName.compareTo(b.projectName);
    if (byProject != 0) return byProject;
    return a.key.compareTo(b.key);
  });
  return rows;
});
