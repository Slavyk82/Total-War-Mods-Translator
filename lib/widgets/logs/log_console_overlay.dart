import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/log_window_provider.dart';
import 'package:twmt/widgets/logs/log_console_window.dart';

/// Mounts [LogConsoleWindow] above all routes when the window is not closed.
/// Designed to sit as a direct child of the `MaterialApp.builder` [Stack].
class LogConsoleOverlay extends ConsumerWidget {
  const LogConsoleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(logWindowControllerProvider) !=
        LogWindowVisibility.closed;
    return visible ? const LogConsoleWindow() : const SizedBox.shrink();
  }
}
