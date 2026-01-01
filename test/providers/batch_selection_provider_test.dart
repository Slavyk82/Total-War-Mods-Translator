import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/batch/batch_selection_provider.dart';

void main() {
  group('BatchSelectionState', () {
    test('initial state has empty selection and selection mode off', () {
      const state = BatchSelectionState();

      expect(state.selectedUnitIds, isEmpty);
      expect(state.isSelectionMode, isFalse);
      expect(state.hasSelection, isFalse);
      expect(state.selectionCount, 0);
    });

    test('copyWith creates new state with updated values', () {
      const state = BatchSelectionState();
      final newState = state.copyWith(
        selectedUnitIds: {'unit1', 'unit2'},
        isSelectionMode: true,
      );

      expect(newState.selectedUnitIds, {'unit1', 'unit2'});
      expect(newState.isSelectionMode, isTrue);
      expect(newState.hasSelection, isTrue);
      expect(newState.selectionCount, 2);
    });

    test('copyWith preserves values when not specified', () {
      final state = const BatchSelectionState().copyWith(
        selectedUnitIds: {'unit1'},
        isSelectionMode: true,
      );

      final newState = state.copyWith(isSelectionMode: false);

      expect(newState.selectedUnitIds, {'unit1'});
      expect(newState.isSelectionMode, isFalse);
    });

    test('isSelected returns true for selected unit', () {
      final state = const BatchSelectionState().copyWith(
        selectedUnitIds: {'unit1', 'unit2'},
      );

      expect(state.isSelected('unit1'), isTrue);
      expect(state.isSelected('unit2'), isTrue);
      expect(state.isSelected('unit3'), isFalse);
    });
  });

  group('BatchSelectionNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty', () {
      final state = container.read(batchSelectionProvider);

      expect(state.selectedUnitIds, isEmpty);
      expect(state.isSelectionMode, isFalse);
    });

    group('toggleSelection', () {
      test('adds unit when not selected', () {
        container.read(batchSelectionProvider.notifier).toggleSelection('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, contains('unit1'));
        expect(state.isSelectionMode, isTrue);
      });

      test('removes unit when already selected', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.toggleSelection('unit1');
        notifier.toggleSelection('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, isEmpty);
        expect(state.isSelectionMode, isFalse);
      });

      test('keeps selection mode on when other units remain selected', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.toggleSelection('unit1');
        notifier.toggleSelection('unit2');
        notifier.toggleSelection('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit2'});
        expect(state.isSelectionMode, isTrue);
      });
    });

    group('select', () {
      test('adds unit to selection', () {
        container.read(batchSelectionProvider.notifier).select('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, contains('unit1'));
        expect(state.isSelectionMode, isTrue);
      });

      test('does not duplicate unit if already selected', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');
        notifier.select('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectionCount, 1);
      });
    });

    group('deselect', () {
      test('removes unit from selection', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');
        notifier.select('unit2');
        notifier.deselect('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit2'});
      });

      test('turns off selection mode when last unit deselected', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');
        notifier.deselect('unit1');

        final state = container.read(batchSelectionProvider);
        expect(state.isSelectionMode, isFalse);
      });
    });

    group('selectMultiple', () {
      test('adds multiple units to selection', () {
        container.read(batchSelectionProvider.notifier).selectMultiple(
          ['unit1', 'unit2', 'unit3'],
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit2', 'unit3'});
        expect(state.isSelectionMode, isTrue);
      });

      test('merges with existing selection', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');
        notifier.selectMultiple(['unit2', 'unit3']);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit2', 'unit3'});
      });

      test('handles empty list without changing state', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');
        notifier.selectMultiple([]);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1'});
      });
    });

    group('selectAll', () {
      test('selects all provided units', () {
        container.read(batchSelectionProvider.notifier).selectAll(
          ['unit1', 'unit2', 'unit3', 'unit4'],
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit2', 'unit3', 'unit4'});
        expect(state.isSelectionMode, isTrue);
      });

      test('replaces existing selection', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('oldUnit');
        notifier.selectAll(['unit1', 'unit2']);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit2'});
        expect(state.isSelected('oldUnit'), isFalse);
      });
    });

    group('clearSelection', () {
      test('clears all selections', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.selectAll(['unit1', 'unit2', 'unit3']);
        notifier.clearSelection();

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, isEmpty);
        expect(state.isSelectionMode, isFalse);
      });
    });

    group('selectRange', () {
      test('selects range of units between two indices', () {
        final allUnits = ['unit1', 'unit2', 'unit3', 'unit4', 'unit5'];
        container.read(batchSelectionProvider.notifier).selectRange(
          allUnits,
          'unit2',
          'unit4',
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit2', 'unit3', 'unit4'});
      });

      test('handles reversed order (from > to)', () {
        final allUnits = ['unit1', 'unit2', 'unit3', 'unit4', 'unit5'];
        container.read(batchSelectionProvider.notifier).selectRange(
          allUnits,
          'unit4',
          'unit2',
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit2', 'unit3', 'unit4'});
      });

      test('merges with existing selection', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.select('unit1');

        final allUnits = ['unit1', 'unit2', 'unit3', 'unit4', 'unit5'];
        notifier.selectRange(allUnits, 'unit3', 'unit5');

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit3', 'unit4', 'unit5'});
      });

      test('does nothing when fromId not found', () {
        final allUnits = ['unit1', 'unit2', 'unit3'];
        container.read(batchSelectionProvider.notifier).selectRange(
          allUnits,
          'nonexistent',
          'unit2',
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, isEmpty);
      });

      test('does nothing when toId not found', () {
        final allUnits = ['unit1', 'unit2', 'unit3'];
        container.read(batchSelectionProvider.notifier).selectRange(
          allUnits,
          'unit1',
          'nonexistent',
        );

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, isEmpty);
      });
    });

    group('invertSelection', () {
      test('inverts selection with all units', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        notifier.selectMultiple(['unit1', 'unit3']);

        final allUnits = ['unit1', 'unit2', 'unit3', 'unit4'];
        notifier.invertSelection(allUnits);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit2', 'unit4'});
      });

      test('selects all when nothing selected', () {
        final allUnits = ['unit1', 'unit2', 'unit3'];
        container.read(batchSelectionProvider.notifier).invertSelection(allUnits);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, {'unit1', 'unit2', 'unit3'});
      });

      test('clears selection when all selected', () {
        final notifier = container.read(batchSelectionProvider.notifier);
        final allUnits = ['unit1', 'unit2', 'unit3'];
        notifier.selectAll(allUnits);
        notifier.invertSelection(allUnits);

        final state = container.read(batchSelectionProvider);
        expect(state.selectedUnitIds, isEmpty);
        expect(state.isSelectionMode, isFalse);
      });
    });
  });
}
