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
  group('filteredTranslationRows — severityFilters', () {
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
          .setStatusFilters({TranslationVersionStatus.needsReview});
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilters({ValidationSeverity.error});

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
          .setStatusFilters({TranslationVersionStatus.needsReview});
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilters({ValidationSeverity.error});

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.map((r) => r.id).toList(), ['a']);
    });

    test('empty severityFilters is a no-op', () async {
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
          .setStatusFilters({TranslationVersionStatus.needsReview});

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.length, 2);
    });
  });
}
