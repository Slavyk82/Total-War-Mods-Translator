import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/scan_terminal_widget.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/selected_game_provider.dart';

/// Boot-time dialog that drives the Workshop mods scan and displays its
/// progress in a terminal-like surface.
///
/// Replaces the lazy "first time the Mods screen is opened in this session"
/// trigger that lived in `ModsScreen.initState`: by running the scan during
/// bootstrap, the Home dashboard cards (mods discovered / updates available)
/// get fresh counts before the user sees them.
///
/// The dialog auto-closes once `detectedModsProvider` resolves to a value.
/// It also no-ops when no game is selected (nothing to scan).
class ModScanBootDialog extends ConsumerStatefulWidget {
  const ModScanBootDialog({super.key});

  /// Show the dialog and run the scan. Returns when the scan finishes (or
  /// immediately when there is no game to scan).
  static Future<void> showAndRun(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) return;

    // Mark the once-per-session rescan as already performed so
    // `ModsScreen.initState` does not retrigger it when the user navigates to
    // the Mods tab.
    ref.read(modsInitialRescanDoneProvider.notifier).markDone();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const ModScanBootDialog(),
    );
  }

  @override
  ConsumerState<ModScanBootDialog> createState() => _ModScanBootDialogState();
}

class _ModScanBootDialogState extends ConsumerState<ModScanBootDialog> {
  bool _closed = false;
  String _title = 'Scanning Workshop mods...';
  bool _phaseTwoStarted = false;

  void _closeIfMounted() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _runPhaseTwo() async {
    if (_phaseTwoStarted) return;
    _phaseTwoStarted = true;
    if (!mounted) return;
    setState(() {
      _title = 'Refreshing subscriber counts...';
    });
    try {
      await ref
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
    } catch (_) {
      // Subscriber refresh is best-effort. Log path is inside the API service.
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _closeIfMounted());
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1: subscribe to the mods scan. Once it resolves, kick off phase 2
    // (subscriber refresh) without closing the dialog. Phase 2 closes the
    // dialog when it resolves.
    ref.listen<AsyncValue<List<DetectedMod>>>(detectedModsProvider,
        (prev, next) {
      if ((next.hasValue && !next.isLoading) || next.hasError) {
        unawaited(_runPhaseTwo());
      }
    });

    final scanLogStream = ref.watch(scanLogStreamProvider);

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ScanTerminalWidget(
          logStream: scanLogStream,
          title: _title,
        ),
      ),
    );
  }
}
