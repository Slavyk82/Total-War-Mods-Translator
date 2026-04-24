import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

TranslationRow _row({
  required String id,
  required TranslationVersionStatus status,
  String? issuesJson,
}) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'key-$id',
    sourceText: 'src-$id',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 'dst-$id',
    status: status,
    translationSource: TranslationSource.manual,
    validationIssues: issuesJson,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

String _issues(List<({String rule, String sev, String msg})> entries) {
  return jsonEncode(entries
      .map((e) => {'rule': e.rule, 'severity': e.sev, 'message': e.msg})
      .toList());
}

void main() {
  group('filteredTranslationRows — severityFilter', () {
    test('keeps only versions with issues matching the selected severity',
        () async {
      final rows = [
        _row(
          id: 'a',
          status: TranslationVersionStatus.needsReview,
          issuesJson:
              _issues([(rule: 'variables', sev: 'error', msg: 'missing %s')]),
        ),
        _row(
          id: 'b',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues(
              [(rule: 'length', sev: 'warning', msg: 'length ratio')]),
        ),
        _row(
          id: 'c',
          status: TranslationVersionStatus.translated,
        ),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      container
          .read(editorFilterProvider.notifier)
          .setStatusFilter(TranslationVersionStatus.needsReview);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilter(ValidationSeverity.error);

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.map((r) => r.id).toList(), ['a']);
    });

    test('critical severity maps to the error bucket', () async {
      final rows = [
        _row(
          id: 'a',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues([
            (rule: 'x', sev: 'critical', msg: 'panic'),
          ]),
        ),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      container
          .read(editorFilterProvider.notifier)
          .setStatusFilter(TranslationVersionStatus.needsReview);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilter(ValidationSeverity.error);

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.map((r) => r.id).toList(), ['a']);
    });

    test('null severityFilter is a no-op', () async {
      final rows = [
        _row(id: 'a', status: TranslationVersionStatus.needsReview),
        _row(id: 'b', status: TranslationVersionStatus.needsReview),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      container
          .read(editorFilterProvider.notifier)
          .setStatusFilter(TranslationVersionStatus.needsReview);

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.length, 2);
    });
  });

  group('visibleSeverityCounts', () {
    test('counts versions by severity over needsReview rows regardless of the '
        'severity filter itself', () async {
      final rows = [
        _row(
          id: 'a',
          status: TranslationVersionStatus.needsReview,
          issuesJson:
              _issues([(rule: 'variables', sev: 'error', msg: 'missing %s')]),
        ),
        _row(
          id: 'b',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues([
            (rule: 'variables', sev: 'error', msg: 'x'),
            (rule: 'length', sev: 'warning', msg: 'y'),
          ]),
        ),
        _row(
          id: 'c',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues(
              [(rule: 'length', sev: 'warning', msg: 'length ratio')]),
        ),
        _row(
          id: 'd',
          status: TranslationVersionStatus.translated,
        ),
        // `e` pins the per-version invariant: two error issues on the same row
        // must still contribute only +1 to the error count.
        _row(
          id: 'e',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues([
            (rule: 'variables', sev: 'error', msg: 'e1'),
            (rule: 'variables', sev: 'error', msg: 'e2'),
          ]),
        ),
        // `f` re-asserts critical -> error bucketing for this provider.
        _row(
          id: 'f',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues([(rule: 'x', sev: 'critical', msg: 'panic')]),
        ),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      // A status filter that *excludes* needsReview must not zero out the
      // counts — the counts are computed before the status filter.
      container
          .read(editorFilterProvider.notifier)
          .setStatusFilter(TranslationVersionStatus.translated);

      final counts = await container
          .read(visibleSeverityCountsProvider('p', 'fr').future);
      expect(counts.errors, 4);
      expect(counts.warnings, 2);
    });
  });
}
