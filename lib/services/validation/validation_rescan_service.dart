import 'dart:async';
import 'dart:convert';

import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/validation/validation_schema.dart';

/// Snapshot of the rescan's current progress. Re-emitted roughly every
/// commit (every 100 units processed).
class RescanProgress {
  final int done;
  final int total;
  final Duration? eta;

  const RescanProgress({
    required this.done,
    required this.total,
    required this.eta,
  });
}

/// Pre-run summary computed by [ValidationRescanService.buildPlan].
class RescanPlan {
  /// Legacy rows still to process (translated, schema_version < 1).
  final int total;

  /// Rows already migrated (schema_version >= 1) — indicates a resume.
  final int already;

  /// True if at least one row is at schema v1 already: the dialog should
  /// render the resume wording rather than the first-run wording.
  final bool isResume;

  /// Calibrated wall-time estimate for the remaining [total] units.
  final Duration estimated;

  const RescanPlan({
    required this.total,
    required this.already,
    required this.isResume,
    required this.estimated,
  });
}

/// Orchestrator for the one-shot startup validation rescan.
///
/// Pages through [TranslationVersionRepository] in deterministic id order,
/// re-runs validation on every legacy row, and commits the new structured
/// JSON in 100-row batches. Resilient to interruption: crashes or process
/// kills leave already-migrated rows at `validation_schema_version` =
/// [currentSchemaVersion] and the remaining rows at a lower version, so a
/// subsequent run resumes cleanly.
///
/// Bump [kCurrentValidationSchemaVersion] whenever the validation logic
/// changes in a way that invalidates previously persisted
/// `validation_issues`. All rows at a lower version become legacy again
/// and the rescan dialog reopens on next boot to re-validate them.
class ValidationRescanService {
  static const int pageSize = 10000;
  static const int commitBatchSize = 10000;
  static const int calibrationSamples = 20;

  final TranslationVersionRepository _versionRepo;
  final TranslationUnitRepository _unitRepo;
  final IValidationService _validation;
  final ILoggingService _logger;

  ValidationRescanService({
    required TranslationVersionRepository versionRepo,
    required TranslationUnitRepository unitRepo,
    required IValidationService validation,
    required ILoggingService logger,
  })  : _versionRepo = versionRepo,
        _unitRepo = unitRepo,
        _validation = validation,
        _logger = logger;

  /// Query the DB and build a [RescanPlan] with a calibrated estimate.
  /// Returns null when there is nothing to migrate.
  Future<RescanPlan?> buildPlan() async {
    final legacy = (await _versionRepo.countLegacyValidationRows()).unwrap();
    final migrated =
        (await _versionRepo.countMigratedValidationRows()).unwrap();

    if (legacy == 0) return null;

    // Calibration pass: validate up to [calibrationSamples] sample rows to
    // measure ms/unit on this machine. Nothing is persisted.
    final sample = (await _versionRepo.getLegacyValidationPage(
      limit: calibrationSamples,
    ))
        .unwrap();
    final unitMap = await _fetchUnits(sample);

    final sw = Stopwatch()..start();
    var sampled = 0;
    for (final v in sample) {
      final u = unitMap[v.unitId];
      if (u == null) continue;
      await _validation.validateTranslation(
        sourceText: u.sourceText,
        translatedText: v.translatedText ?? '',
        key: u.key,
      );
      sampled++;
    }
    sw.stop();

    // Default guess if calibration found no usable units. Use microsecond
    // resolution so tiny-sample calibration (ms=0) still produces a non-zero
    // estimate on fast machines.
    final usPerUnit =
        sampled == 0 ? 8000.0 : sw.elapsedMicroseconds / sampled;
    final estimated =
        Duration(microseconds: (usPerUnit * legacy).round());

    return RescanPlan(
      total: legacy,
      already: migrated,
      isResume: migrated > 0,
      estimated: estimated,
    );
  }

  /// Run the rescan and emit progress events.
  ///
  /// The caller subscribes and should drain the stream to completion; when
  /// it ends, all legacy rows are at schema v1. Cancelling the subscription
  /// pauses the rescan mid-batch — a subsequent call picks up where it left
  /// off because `validation_schema_version` is updated per commit.
  Stream<RescanProgress> run() async* {
    final total = (await _versionRepo.countLegacyValidationRows()).unwrap();
    if (total == 0) {
      yield const RescanProgress(done: 0, total: 0, eta: Duration.zero);
      return;
    }

    var done = 0;
    String? afterId;
    // Anchor ETA on wall-time since the scan started, not per-batch
    // stopwatches. Per-batch averaging exaggerates the cost of the first
    // batch (SQLite WAL / FTS warm-up) and inflates the ETA; wall-time
    // amortises it naturally and converges on the real rate as the scan
    // progresses.
    final runStart = DateTime.now();

    while (true) {
      final page = (await _versionRepo.getLegacyValidationPage(
        limit: pageSize,
        afterId: afterId,
      ))
          .unwrap();
      if (page.isEmpty) break;
      afterId = page.last.id;

      final unitsMap = await _fetchUnits(page);

      final pending = <({
        String versionId,
        String status,
        String? validationIssues,
        int schemaVersion,
      })>[];

      for (final v in page) {
        final u = unitsMap[v.unitId];
        if (u == null) continue;

        final validationResult = await _validation.validateTranslation(
          sourceText: u.sourceText,
          translatedText: v.translatedText ?? '',
          key: u.key,
        );

        String status = 'translated';
        String? issuesJson;
        if (validationResult.isErr) {
          status = 'needs_review';
        } else {
          final result = validationResult.unwrap();
          if (result.hasErrors || result.hasWarnings) {
            status = 'needs_review';
            issuesJson = jsonEncode(
              result.issues.map((i) => i.toJson()).toList(),
            );
          }
        }

        pending.add((
          versionId: v.id,
          status: status,
          validationIssues: issuesJson,
          schemaVersion: kCurrentValidationSchemaVersion,
        ));

        if (pending.length >= commitBatchSize) {
          await _commit(pending);
          done += pending.length;
          pending.clear();
          yield RescanProgress(
            done: done,
            total: total,
            eta: _etaFromWallTime(runStart, done, total),
          );
        }
      }

      if (pending.isNotEmpty) {
        await _commit(pending);
        done += pending.length;
        yield RescanProgress(
          done: done,
          total: total,
          eta: _etaFromWallTime(runStart, done, total),
        );
      }
    }

    _logger.info('Validation rescan complete', {'processed': done});
  }

  Future<void> _commit(
    List<({
      String versionId,
      String status,
      String? validationIssues,
      int schemaVersion,
    })> updates,
  ) async {
    final res = await _versionRepo.updateValidationBatch(updates);
    if (res.isErr) {
      _logger.error('Rescan commit failed', res.error, StackTrace.current);
      throw Exception('Rescan commit failed: ${res.error}');
    }
  }

  Future<Map<String, TranslationUnit>> _fetchUnits(
      List<TranslationVersion> versions) async {
    final ids = versions.map((v) => v.unitId).toSet().toList();
    if (ids.isEmpty) return const {};
    final res = await _unitRepo.getByIds(ids);
    if (res.isErr) return const {};
    return {for (final u in res.unwrap()) u.id: u};
  }

  Duration? _etaFromWallTime(DateTime runStart, int done, int total) {
    final remaining = total - done;
    if (remaining <= 0) return Duration.zero;
    if (done <= 0) return null;
    final elapsedMs = DateTime.now().difference(runStart).inMilliseconds;
    if (elapsedMs <= 0) return null;
    final msPerUnit = elapsedMs / done;
    return Duration(milliseconds: (msPerUnit * remaining).round());
  }
}
