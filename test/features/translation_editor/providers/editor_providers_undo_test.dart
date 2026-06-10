import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _FakeAction implements HistoryAction {
  @override
  String get versionId => 'v-1';

  @override
  String get oldValue => 'old';

  @override
  String get newValue => 'new';

  @override
  DateTime get timestamp => DateTime(2026, 1, 1);

  @override
  Future<void> undo() async {}

  @override
  Future<void> redo() async {}
}

TranslationVersion _version(String translatedText) {
  return TranslationVersion(
    id: 'v-1',
    unitId: 'u-1',
    projectLanguageId: 'pl-1',
    translatedText: translatedText,
    status: TranslationVersionStatus.translated,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_version('fallback'));
  });

  group('undoRedoManagerProvider lifecycle (M17)', () {
    test(
        'manager instance survives between ref.read calls while the editor '
        'screen watches the provider', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulates the editor screen's ref.watch keeping the session alive.
      final sub = container.listen(
        undoRedoManagerProvider('p-1', 'l-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      // Simulates handleCellEdit: ref.read + recordAction.
      final managerAtEdit = container.read(undoRedoManagerProvider('p-1', 'l-1'));
      managerAtEdit.recordAction(_FakeAction());

      // Let any pending autoDispose flush happen (this is where the old
      // unwatched provider lost its state).
      await pumpEventQueue();

      // Simulates handleUndo: a later, independent ref.read.
      final managerAtUndo = container.read(undoRedoManagerProvider('p-1', 'l-1'));

      expect(identical(managerAtEdit, managerAtUndo), isTrue,
          reason: 'ref.read must return the same live manager instance');
      expect(managerAtUndo.canUndo, isTrue,
          reason: 'the recorded action must still be on the stack');
      expect(await managerAtUndo.undo(), isTrue);
    });

    test('each (projectId, languageId) scope gets its own isolated manager',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final subA = container.listen(
        undoRedoManagerProvider('p-1', 'l-1'),
        (_, _) {},
      );
      final subB = container.listen(
        undoRedoManagerProvider('p-2', 'l-1'),
        (_, _) {},
      );
      addTearDown(subA.close);
      addTearDown(subB.close);

      final managerA = container.read(undoRedoManagerProvider('p-1', 'l-1'));
      final managerB = container.read(undoRedoManagerProvider('p-2', 'l-1'));

      expect(identical(managerA, managerB), isFalse);

      managerA.recordAction(_FakeAction());
      expect(managerA.canUndo, isTrue);
      expect(managerB.canUndo, isFalse,
          reason: 'undo history must not bleed across projects');
    });

    test('stack is dropped when the editor scope is no longer watched '
        '(project/language switch or screen close)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(
        undoRedoManagerProvider('p-1', 'l-1'),
        (_, _) {},
      );
      final manager = container.read(undoRedoManagerProvider('p-1', 'l-1'));
      manager.recordAction(_FakeAction());

      // Screen closes / switches scope: the watch goes away.
      sub.close();
      await pumpEventQueue();

      // Re-opening the same scope must start with a clean stack.
      final sub2 = container.listen(
        undoRedoManagerProvider('p-1', 'l-1'),
        (_, _) {},
      );
      addTearDown(sub2.close);
      final fresh = container.read(undoRedoManagerProvider('p-1', 'l-1'));

      expect(identical(manager, fresh), isFalse);
      expect(fresh.canUndo, isFalse);
    });

    test(
        'end-to-end: a recorded edit followed by a ref.read-based undo '
        'actually writes the old value back', () async {
      final repo = _MockTranslationVersionRepository();
      when(() => repo.getById('v-1'))
          .thenAnswer((_) async => Ok(_version('new')));
      when(() => repo.update(any()))
          .thenAnswer((invocation) async =>
              Ok(invocation.positionalArguments.first as TranslationVersion));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(
        undoRedoManagerProvider('p-1', 'l-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      // Edit: record the action (as handleCellEdit does).
      container.read(undoRedoManagerProvider('p-1', 'l-1')).recordAction(
            TranslationEditAction(
              versionId: 'v-1',
              oldValue: 'old',
              newValue: 'new',
              timestamp: DateTime(2026, 1, 1),
              repository: repo,
            ),
          );

      await pumpEventQueue();

      // Undo: independent ref.read (as handleUndo does).
      final success =
          await container.read(undoRedoManagerProvider('p-1', 'l-1')).undo();

      expect(success, isTrue);
      final updated = verify(() => repo.update(captureAny())).captured.single
          as TranslationVersion;
      expect(updated.translatedText, 'old');
    });
  });
}
