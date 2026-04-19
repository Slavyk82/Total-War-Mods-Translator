import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/validation_inspector_width_notifier.dart';

void main() {
  group('ValidationInspectorWidth', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('starts at the default width', () {
      expect(
        container.read(validationInspectorWidthProvider),
        ValidationInspectorWidth.defaultWidth,
      );
    });

    test('clamps below the minimum', () {
      final notifier =
          container.read(validationInspectorWidthProvider.notifier);
      notifier.setWidth(ValidationInspectorWidth.minWidth - 100);
      expect(
        container.read(validationInspectorWidthProvider),
        ValidationInspectorWidth.minWidth,
      );
    });

    test('clamps above the maximum', () {
      final notifier =
          container.read(validationInspectorWidthProvider.notifier);
      notifier.setWidth(ValidationInspectorWidth.maxWidth + 250);
      expect(
        container.read(validationInspectorWidthProvider),
        ValidationInspectorWidth.maxWidth,
      );
    });

    test('accepts values inside the allowed range', () {
      final notifier =
          container.read(validationInspectorWidthProvider.notifier);
      notifier.setWidth(420);
      expect(container.read(validationInspectorWidthProvider), 420);
    });
  });
}
