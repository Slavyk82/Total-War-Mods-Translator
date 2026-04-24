import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/services/glossary/glossary_filter_service.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

/// Ref-based equivalents of `TranslationBatchHelper.createAndPrepareBatch`
/// and `buildTranslationContext`. The originals require a `WidgetRef`;
/// these accept a `Ref` so they can be called from Notifiers (bulk flow).
///
/// Keep these in sync with
/// `lib/features/translation_editor/utils/translation_batch_helper.dart`
/// if either helper's logic changes.
Future<String?> createBulkBatch({
  required Ref ref,
  required String projectLanguageId,
  required List<String> unitIds,
  required String providerId,
}) async {
  try {
    final batchRepo = ref.read(shared_svc.translationBatchRepositoryProvider);
    final batchUnitRepo =
        ref.read(shared_svc.translationBatchUnitRepositoryProvider);
    final logging = ref.read(loggingServiceProvider);

    final existingBatchesResult =
        await batchRepo.getByProjectLanguage(projectLanguageId);
    final batchNumber = existingBatchesResult.when(
      ok: (batches) => batches.isEmpty
          ? 1
          : (batches.map((b) => b.batchNumber).reduce((a, b) => a > b ? a : b) +
              1),
      err: (_) => 1,
    );

    final batchId = const Uuid().v4();
    final batch = TranslationBatch(
      id: batchId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      batchNumber: batchNumber,
      unitsCount: unitIds.length,
      status: TranslationBatchStatus.pending,
    );

    final batchInsertResult = await batchRepo.insert(batch);
    if (batchInsertResult.isErr) {
      logging.error('Failed to create batch', batchInsertResult.unwrapErr());
      return null;
    }

    final batchUnits = <TranslationBatchUnit>[];
    for (var i = 0; i < unitIds.length; i++) {
      batchUnits.add(TranslationBatchUnit(
        id: const Uuid().v4(),
        batchId: batchId,
        unitId: unitIds[i],
        processingOrder: i,
        status: TranslationBatchUnitStatus.pending,
      ));
    }

    final unitsInsertResult = await batchUnitRepo.insertBatch(batchUnits);
    if (unitsInsertResult.isErr) {
      logging.error(
        'Failed to create batch units',
        unitsInsertResult.unwrapErr(),
      );
      return null;
    }

    logging.info(
      'Created bulk batch with ${batchUnits.length} units in single transaction',
    );
    return batchId;
  } catch (e, stackTrace) {
    ref.read(loggingServiceProvider).error(
          'Failed to create and prepare bulk batch',
          e,
          stackTrace,
        );
    return null;
  }
}

Future<TranslationContext> buildBulkTranslationContext({
  required Ref ref,
  required String projectId,
  required String projectLanguageId,
  required String providerId,
  String? modelId,
  int? unitsPerBatch,
  int? parallelBatches,
  bool? skipTranslationMemory,
}) async {
  try {
    final projectRepo = ref.read(shared_repo.projectRepositoryProvider);
    final projectLanguageRepo =
        ref.read(shared_repo.projectLanguageRepositoryProvider);
    final languageRepo = ref.read(shared_repo.languageRepositoryProvider);
    final glossaryRepo = ref.read(shared_repo.glossaryRepositoryProvider);
    final gameInstallationRepo =
        ref.read(shared_repo.gameInstallationRepositoryProvider);
    final logging = ref.read(loggingServiceProvider);

    String? gameCode;
    final projectResult = await projectRepo.getById(projectId);
    if (projectResult.isOk) {
      final project = projectResult.unwrap();
      final gameInstallationResult =
          await gameInstallationRepo.getById(project.gameInstallationId);
      if (gameInstallationResult.isOk) {
        gameCode = gameInstallationResult.unwrap().gameCode;
      } else {
        logging.warning(
          'Failed to resolve gameCode from gameInstallationId for bulk translation context: ${gameInstallationResult.unwrapErr()}',
        );
      }
    }

    const sourceLanguageCode = 'EN';

    final projectLanguageResult =
        await projectLanguageRepo.getById(projectLanguageId);
    String targetLanguage = 'EN';
    String? languageId;

    if (projectLanguageResult.isOk) {
      final projectLanguage = projectLanguageResult.unwrap();
      languageId = projectLanguage.languageId;
      final languageResult = await languageRepo.getById(projectLanguage.languageId);
      if (languageResult.isOk) {
        targetLanguage = languageResult.unwrap().code.toUpperCase();
      } else {
        logging.warning(
          'Failed to get language for bulk translation context: ${languageResult.unwrapErr()}',
        );
      }
    } else {
      logging.warning(
        'Failed to get project language for bulk translation context: ${projectLanguageResult.unwrapErr()}',
      );
    }

    final glossaryFilterService = GlossaryFilterService(glossaryRepo);
    final List<GlossaryTermWithVariants> glossaryEntries = gameCode != null
        ? await glossaryFilterService.loadAllTerms(
            gameCode: gameCode,
            targetLanguageId: languageId ?? '',
            targetLanguageCode: targetLanguage,
          )
        : <GlossaryTermWithVariants>[];

    String? glossaryId;
    if (gameCode != null) {
      final glossaries = await glossaryRepo.getAllGlossaries(gameCode: gameCode);
      glossaryId = glossaries.firstOrNull?.id;
    }

    return TranslationContext(
      id: const Uuid().v4(),
      projectId: projectId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      modelId: modelId,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguageCode,
      glossaryEntries: glossaryEntries.isEmpty ? null : glossaryEntries,
      glossaryId: glossaryId,
      unitsPerBatch: unitsPerBatch ?? 0,
      parallelBatches: parallelBatches ?? 1,
      skipTranslationMemory: skipTranslationMemory ?? false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  } catch (e, stackTrace) {
    ref.read(loggingServiceProvider).error(
          'Failed to build bulk translation context',
          e,
          stackTrace,
        );
    return TranslationContext(
      id: const Uuid().v4(),
      projectId: projectId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      modelId: modelId,
      targetLanguage: 'en',
      unitsPerBatch: unitsPerBatch ?? 0,
      parallelBatches: parallelBatches ?? 1,
      skipTranslationMemory: skipTranslationMemory ?? false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
