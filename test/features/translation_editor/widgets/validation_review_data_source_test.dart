import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_data_source.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  Widget _host(ValidationReviewDataSource ds) {
    return MaterialApp(
      home: Scaffold(
        body: SfDataGrid(
          source: ds,
          columnWidthMode: ColumnWidthMode.fill,
          columns: [
            GridColumn(
              columnName: 'checkbox',
              width: 50,
              label: const SizedBox.shrink(),
            ),
            GridColumn(
              columnName: 'key',
              width: 120,
              label: const SizedBox.shrink(),
            ),
            GridColumn(
              columnName: 'description',
              width: 160,
              label: const SizedBox.shrink(),
            ),
            GridColumn(
              columnName: 'sourceText',
              width: 160,
              label: const SizedBox.shrink(),
            ),
            GridColumn(
              columnName: 'translatedText',
              width: 160,
              label: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  ValidationIssue makeIssue({
    required String versionId,
    required ValidationSeverity severity,
  }) {
    return ValidationIssue(
      unitKey: 'key_$versionId',
      unitId: 'unit_$versionId',
      versionId: versionId,
      severity: severity,
      issueType: severity == ValidationSeverity.error ? 'ERROR' : 'WARNING',
      description: 'desc_$versionId',
      sourceText: 'source_$versionId',
      translatedText: 'translated_$versionId',
    );
  }

  testWidgets(
      'translation cell renders with the red severity tint for an error issue',
      (tester) async {
    final ds = ValidationReviewDataSource(
      issues: [makeIssue(versionId: 'v1', severity: ValidationSeverity.error)],
      isRowSelected: (_) => false,
      onCheckboxTap: (_) {},
    );

    await tester.pumpWidget(_host(ds));
    await tester.pumpAndSettle();

    final expectedTint = Colors.red.withValues(alpha: 0.05);
    final matches = find
        .byWidgetPredicate(
          (w) => w is Container && w.color == expectedTint,
        )
        .evaluate();
    expect(
      matches,
      isNotEmpty,
      reason:
          'Expected at least one Container painted with the error-severity '
          'tint (Colors.red at 0.05 alpha) to back the translation cell.',
    );
  });

  test('setSelectedRowColor updates the adapter colour on subsequent builds',
      () {
    final ds = ValidationReviewDataSource(
      issues: [makeIssue(versionId: 'v1', severity: ValidationSeverity.error)],
      isRowSelected: (_) => true,
      onCheckboxTap: (_) {},
    );

    // Build the underlying DataGridRow once; adapter colour is recomputed each
    // time buildRow runs against the currently configured `_selectedRowColor`.
    final gridRow = ds.rows.single;

    const red = Color(0xFFFF0000);
    const blue = Color(0xFF0000FF);

    ds.setSelectedRowColor(red);
    expect(ds.buildRow(gridRow).color, red);

    // No-op when colour is unchanged — outcome still matches.
    ds.setSelectedRowColor(red);
    expect(ds.buildRow(gridRow).color, red);

    ds.setSelectedRowColor(blue);
    expect(ds.buildRow(gridRow).color, blue);
  });
}
