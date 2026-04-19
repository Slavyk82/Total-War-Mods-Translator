import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'validation_inspector_width_notifier.g.dart';

/// Current pixel width of the validation review inspector panel.
///
/// Kept separate from the translation editor's inspector width so the two
/// screens don't stomp on each other's preferred sizing within a session.
@riverpod
class ValidationInspectorWidth extends _$ValidationInspectorWidth {
  /// Lower bound: below this the labels and action buttons stop being usable.
  static const double minWidth = 240;

  /// Upper bound: past this the inspector eats too much of the grid viewport.
  static const double maxWidth = 640;

  /// Default width matching the editor's inspector.
  static const double defaultWidth = 320;

  @override
  double build() => defaultWidth;

  /// Update the width, clamping to `[minWidth, maxWidth]`.
  void setWidth(double width) {
    final clamped = width.clamp(minWidth, maxWidth);
    if (clamped != state) state = clamped;
  }
}
