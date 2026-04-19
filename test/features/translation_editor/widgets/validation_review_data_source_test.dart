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
              columnName: 'severity',
              width: 80,
              label: const SizedBox.shrink(),
            ),
            GridColumn(
              columnName: 'issueType',
              width: 140,
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
            GridColumn(
              columnName: 'actions',
              width: 160,
              label: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('Issue Type cell shows humanised label for known rule',
      (tester) async {
    final ds = ValidationReviewDataSource(
      issues: [
        const ValidationIssue(
          unitKey: 'k',
          unitId: 'u',
          versionId: 'v',
          severity: ValidationSeverity.error,
          issueType: 'variables',
          description: 'Missing {0}',
          sourceText: 'Hello {0}',
          translatedText: 'Bonjour',
        ),
      ],
      isRowSelected: (_) => false,
      isProcessing: (_) => false,
      onCheckboxTap: (_) {},
    );

    await tester.pumpWidget(_host(ds));
    await tester.pumpAndSettle();

    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('variables'), findsNothing);
  });

  testWidgets('Legacy rows show "Legacy" as a safe fallback', (tester) async {
    final ds = ValidationReviewDataSource(
      issues: [
        const ValidationIssue(
          unitKey: 'k',
          unitId: 'u',
          versionId: 'v',
          severity: ValidationSeverity.warning,
          issueType: 'legacy',
          description: 'Pending rescan',
          sourceText: 's',
          translatedText: 't',
        ),
      ],
      isRowSelected: (_) => false,
      isProcessing: (_) => false,
      onCheckboxTap: (_) {},
    );

    await tester.pumpWidget(_host(ds));
    await tester.pumpAndSettle();

    expect(find.text('Legacy'), findsOneWidget);
  });
}
