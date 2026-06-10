import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

/// Fake action whose undo/redo can be toggled to throw, simulating a
/// transient DB failure (e.g. 'database is locked' during a running batch).
class _FakeAction implements HistoryAction {
  _FakeAction({this.failUndo = false});

  bool failUndo;
  bool failRedo = false;
  int undoCalls = 0;
  int redoCalls = 0;

  @override
  String get versionId => 'v-1';

  @override
  String get oldValue => 'old';

  @override
  String get newValue => 'new';

  @override
  DateTime get timestamp => DateTime(2026, 1, 1);

  @override
  Future<void> undo() async {
    undoCalls++;
    if (failUndo) throw Exception('Failed to undo: database is locked');
  }

  @override
  Future<void> redo() async {
    redoCalls++;
    if (failRedo) throw Exception('Failed to redo: database is locked');
  }
}

void main() {
  group('UndoRedoManager — success paths', () {
    test('undo moves the action from the undo stack to the redo stack',
        () async {
      final manager = UndoRedoManager();
      final action = _FakeAction();
      manager.recordAction(action);

      final success = await manager.undo();

      expect(success, isTrue);
      expect(manager.undoCount, 0);
      expect(manager.redoCount, 1);
      expect(manager.lastRedoableAction, same(action));
    });

    test('redo moves the action back to the undo stack', () async {
      final manager = UndoRedoManager();
      final action = _FakeAction();
      manager.recordAction(action);
      await manager.undo();

      final success = await manager.redo();

      expect(success, isTrue);
      expect(manager.redoCount, 0);
      expect(manager.undoCount, 1);
      expect(manager.lastUndoableAction, same(action));
    });
  });

  group('UndoRedoManager — failed undo (M11)', () {
    test('failed undo restores the action onto the undo stack and rethrows',
        () async {
      final manager = UndoRedoManager();
      final action = _FakeAction(failUndo: true);
      manager.recordAction(action);

      await expectLater(manager.undo(), throwsA(isA<Exception>()));

      // The action must NOT be lost: it stays on the undo stack so the user
      // can retry once the transient failure clears.
      expect(manager.canUndo, isTrue);
      expect(manager.undoCount, 1);
      expect(manager.lastUndoableAction, same(action));
      // A failed undo must never land on the redo stack (the DB was not
      // changed, so there is nothing to redo).
      expect(manager.canRedo, isFalse);
      expect(manager.redoCount, 0);
    });

    test('retrying after a failed undo succeeds and targets the same action',
        () async {
      final manager = UndoRedoManager();
      final action = _FakeAction(failUndo: true);
      manager.recordAction(action);

      await expectLater(manager.undo(), throwsA(isA<Exception>()));

      // Transient failure clears.
      action.failUndo = false;
      final success = await manager.undo();

      expect(success, isTrue);
      expect(action.undoCalls, 2);
      expect(manager.undoCount, 0);
      expect(manager.lastRedoableAction, same(action));
    });

    test('failed undo keeps stack order intact (retry targets the newest '
        'action, not an older one)', () async {
      final manager = UndoRedoManager();
      final older = _FakeAction();
      final newest = _FakeAction(failUndo: true);
      manager.recordAction(older);
      manager.recordAction(newest);

      await expectLater(manager.undo(), throwsA(isA<Exception>()));

      expect(manager.undoCount, 2);
      expect(manager.lastUndoableAction, same(newest));
      expect(older.undoCalls, 0);
    });
  });

  group('UndoRedoManager — failed redo (M11)', () {
    test('failed redo restores the action onto the redo stack and rethrows',
        () async {
      final manager = UndoRedoManager();
      final action = _FakeAction();
      manager.recordAction(action);
      await manager.undo();
      action.failRedo = true;

      await expectLater(manager.redo(), throwsA(isA<Exception>()));

      expect(manager.canRedo, isTrue);
      expect(manager.redoCount, 1);
      expect(manager.lastRedoableAction, same(action));
      // A failed redo must never land on the undo stack.
      expect(manager.canUndo, isFalse);
      expect(manager.undoCount, 0);
    });

    test('retrying after a failed redo succeeds', () async {
      final manager = UndoRedoManager();
      final action = _FakeAction();
      manager.recordAction(action);
      await manager.undo();
      action.failRedo = true;

      await expectLater(manager.redo(), throwsA(isA<Exception>()));
      action.failRedo = false;

      final success = await manager.redo();

      expect(success, isTrue);
      expect(manager.undoCount, 1);
      expect(manager.lastUndoableAction, same(action));
    });
  });

  group('TranslationEditAction with failing repository (M11 end-to-end)', () {
    test('repository Err makes undo throw and the manager keeps the entry',
        () async {
      final repo = _MockTranslationVersionRepository();
      when(() => repo.getById('v-1')).thenAnswer(
        (_) async => Err(TWMTDatabaseException('database is locked')),
      );

      final manager = UndoRedoManager();
      final action = TranslationEditAction(
        versionId: 'v-1',
        oldValue: 'old',
        newValue: 'new',
        timestamp: DateTime(2026, 1, 1),
        repository: repo,
      );
      manager.recordAction(action);

      await expectLater(manager.undo(), throwsA(isA<Exception>()));

      expect(manager.canUndo, isTrue);
      expect(manager.lastUndoableAction, same(action));
      expect(manager.canRedo, isFalse);
    });
  });
}
