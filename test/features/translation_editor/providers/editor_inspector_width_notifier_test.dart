import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_inspector_width_notifier.dart';

void main() {
  group('EditorInspectorWidth', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('starts at the default width', () {
      expect(
        container.read(editorInspectorWidthProvider),
        EditorInspectorWidth.defaultWidth,
      );
    });

    test('clamps below the minimum', () {
      final notifier = container.read(editorInspectorWidthProvider.notifier);
      notifier.setWidth(EditorInspectorWidth.minWidth - 100);
      expect(
        container.read(editorInspectorWidthProvider),
        EditorInspectorWidth.minWidth,
      );
    });

    test('clamps above the maximum', () {
      final notifier = container.read(editorInspectorWidthProvider.notifier);
      notifier.setWidth(EditorInspectorWidth.maxWidth + 250);
      expect(
        container.read(editorInspectorWidthProvider),
        EditorInspectorWidth.maxWidth,
      );
    });

    test('accepts values inside the allowed range', () {
      final notifier = container.read(editorInspectorWidthProvider.notifier);
      notifier.setWidth(420);
      expect(container.read(editorInspectorWidthProvider), 420);
    });
  });
}
