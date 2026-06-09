import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_window_provider.g.dart';

/// Visibility state of the floating log console window.
enum LogWindowVisibility { closed, open, minimized }

/// App-level controller for the floating log console.
///
/// Holds ONLY the visibility. The window widget owns its own position, size,
/// level filters and search text — intentionally not persisted (reset on each
/// open). Kept alive because the toggle is app-global UI state.
@Riverpod(keepAlive: true)
class LogWindowController extends _$LogWindowController {
  @override
  LogWindowVisibility build() => LogWindowVisibility.closed;

  /// Open from closed or minimized.
  void open() => state = LogWindowVisibility.open;

  /// Fully hide the window.
  void close() => state = LogWindowVisibility.closed;

  /// Collapse to the minimized bar.
  void minimize() => state = LogWindowVisibility.minimized;

  /// Restore from minimized to the full window.
  void restore() => state = LogWindowVisibility.open;

  /// Sidebar button behavior: open when not open, otherwise close.
  void toggleOpen() {
    state = state == LogWindowVisibility.open
        ? LogWindowVisibility.closed
        : LogWindowVisibility.open;
  }
}
