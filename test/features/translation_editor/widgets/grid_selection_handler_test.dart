import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/features/translation_editor/widgets/grid_selection_handler.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

import '../../../helpers/test_bootstrap.dart';

TranslationRow _row(String id) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'k-$id',
    sourceText: 's-$id',
    sourceLocFile: 'f.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 't-$id',
    status: TranslationVersionStatus.translated,
    translationSource: TranslationSource.llm,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('checkbox column cell-tap is a no-op', (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final dataSource = EditorDataSource(
      onCellEdit: (_, _) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
    dataSource.updateDataSource([_row('a'), _row('b')]);

    final handler = GridSelectionHandler(
      dataSource: dataSource,
      controller: DataGridController(),
      ref: capturedRef,
      onSelectionChanged: (_, _) {},
    );

    handler.handleCellTap(
      DataGridCellTapDetails(
        rowColumnIndex: RowColumnIndex(1, 0),
        column: GridColumn(columnName: 'checkbox', label: const SizedBox()),
        globalPosition: Offset.zero,
        localPosition: Offset.zero,
        kind: PointerDeviceKind.mouse,
      ),
    );

    // CheckboxCellRenderer owns the tap on the checkbox column; the grid's
    // onCellTap must not also single-select or it clobbers multi-select.
    expect(capturedRef.read(editorSelectionProvider).selectedCount, 0);
  });
}
