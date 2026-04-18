import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

TranslationRow _row(String id) => TranslationRow(
      unit: TranslationUnit(
        id: id,
        projectId: 'p1',
        key: 'k_$id',
        sourceText: 's_$id',
        createdAt: 0,
        updatedAt: 0,
      ),
      version: TranslationVersion(
        id: 'v_$id',
        unitId: id,
        projectLanguageId: 'pl1',
        createdAt: 0,
        updatedAt: 0,
      ),
    );

void main() {
  late EditorDataSource ds;

  setUp(() {
    ds = EditorDataSource(
      onCellEdit: (_, _) {},
      onCellTap: (_) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
  });

  tearDown(() => ds.dispose());

  test('updateDataSource populates rows and id index consistently', () {
    final rows = List.generate(1000, (i) => _row('u$i'));
    ds.updateDataSource(rows);

    expect(ds.translationRows.length, 1000);
    // Internal contract: rowById() returns the exact TranslationRow without
    // scanning the list — we assert the lookup for both boundary ids.
    expect(ds.rowById('u0'), same(rows.first));
    expect(ds.rowById('u999'), same(rows.last));
  });

  test('rowById falls back to the first row when id is unknown', () {
    final rows = [_row('a'), _row('b')];
    ds.updateDataSource(rows);
    expect(ds.rowById('missing'), same(rows.first));
  });

  test('updateDataSource rebuilds the id index when rows change', () {
    final first = [_row('a'), _row('b')];
    ds.updateDataSource(first);
    expect(ds.rowById('a'), same(first.first));

    final second = [_row('x'), _row('y')];
    ds.updateDataSource(second);
    expect(ds.rowById('a'), same(second.first)); // fallback
    expect(ds.rowById('x'), same(second.first));
  });
}
