import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/log_window_provider.dart';
import 'package:twmt/widgets/logs/log_console_window.dart';

/// Mounts [LogConsoleWindow] above all routes when the window is not closed.
/// Designed to sit as a direct child of the `MaterialApp.builder` [Stack].
///
/// The window is hosted inside its own [Overlay] so that descendants requiring
/// an overlay ancestor — tooltips on the toolbar buttons, and the selection
/// toolbar/handles of the search field and the selectable log lines — resolve
/// correctly. The app's own Navigator overlay is *inside* the routed child, so
/// it is not an ancestor of this sibling; providing a local overlay is what
/// makes those widgets work.
///
/// The overlay fills the screen via [Positioned.fill] (it needs bounded
/// constraints), but it stays non-blocking: an overlay/stack does not absorb
/// pointer events outside its positioned children, so taps in empty areas fall
/// through to the app underneath. Only the floating window's own rectangle
/// intercepts input.
class LogConsoleOverlay extends ConsumerWidget {
  const LogConsoleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(logWindowControllerProvider) !=
        LogWindowVisibility.closed;
    if (!visible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Overlay(
        initialEntries: [
          OverlayEntry(builder: (_) => const LogConsoleWindow()),
        ],
      ),
    );
  }
}
