import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_inspector_width_notifier.g.dart';

/// Current pixel width of the right-hand inspector panel.
///
/// State lives in memory for the session only; persisting the preference is
/// out of scope here and can be layered on later without changing callers.
@riverpod
class EditorInspectorWidth extends _$EditorInspectorWidth {
  /// Lower bound: below this the labels and the target field stop being usable.
  static const double minWidth = 240;

  /// Upper bound: past this the inspector eats too much of the grid viewport.
  static const double maxWidth = 640;

  /// Default width matching the previous fixed layout.
  static const double defaultWidth = 320;

  @override
  double build() => defaultWidth;

  /// Update the width, clamping to `[minWidth, maxWidth]`.
  void setWidth(double width) {
    final clamped = width.clamp(minWidth, maxWidth);
    if (clamped != state) state = clamped;
  }
}
