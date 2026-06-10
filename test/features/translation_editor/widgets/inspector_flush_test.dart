import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/editor_inspector_panel.dart'
    show resolveInspectorFlush;

/// Regression tests for the inspector flush decision.
///
/// A user could type a translation in the inspector (dirty, bound to row A)
/// without blurring, then filter A out of the grid. The flush-on-rebind logic
/// looked up the previous row only in the FILTERED list and bailed when it was
/// gone — silently dropping the unsaved edit. The decision must instead fall
/// back to the unfiltered persisted text (or flush unconditionally) so the edit
/// survives.
void main() {
  group('resolveInspectorFlush', () {
    test('returns null when the field is not dirty', () {
      expect(
        resolveInspectorFlush(
            dirty: false,
            boundUnitId: 'a',
            currentText: 'x',
            filteredPersisted: 'old',
            unfilteredPersisted: 'old'),
        isNull,
      );
    });

    test('returns null when no unit is bound', () {
      expect(
        resolveInspectorFlush(
            dirty: true,
            boundUnitId: null,
            currentText: 'x',
            filteredPersisted: 'old',
            unfilteredPersisted: 'old'),
        isNull,
      );
    });

    test('flushes when the edit differs from the persisted text (row visible)',
        () {
      final r = resolveInspectorFlush(
          dirty: true,
          boundUnitId: 'a',
          currentText: 'new',
          filteredPersisted: 'old',
          unfilteredPersisted: null);
      expect(r, isNotNull);
      expect(r!.unitId, 'a');
      expect(r.text, 'new');
    });

    test('does NOT flush when the edit equals the persisted text', () {
      expect(
        resolveInspectorFlush(
            dirty: true,
            boundUnitId: 'a',
            currentText: 'same',
            filteredPersisted: 'same',
            unfilteredPersisted: null),
        isNull,
      );
    });

    test('flushes using the UNFILTERED persisted text when the row was '
        'filtered out of the visible set', () {
      final r = resolveInspectorFlush(
          dirty: true,
          boundUnitId: 'a',
          currentText: 'edited',
          filteredPersisted: null,
          unfilteredPersisted: 'old');
      expect(r, isNotNull);
      expect(r!.text, 'edited');
    });

    test('does NOT flush when a filtered-out row already matches its '
        'unfiltered persisted text', () {
      expect(
        resolveInspectorFlush(
            dirty: true,
            boundUnitId: 'a',
            currentText: 'same',
            filteredPersisted: null,
            unfilteredPersisted: 'same'),
        isNull,
      );
    });

    test('flushes unconditionally when the row is in neither set', () {
      final r = resolveInspectorFlush(
          dirty: true,
          boundUnitId: 'a',
          currentText: 'edited',
          filteredPersisted: null,
          unfilteredPersisted: null);
      expect(r, isNotNull);
      expect(r!.text, 'edited');
    });
  });
}
