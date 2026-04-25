import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/i18n/strings.g.dart';

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/scan_terminal_widget.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';

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
  late String _title = t.bootstrap.modScan.titleScanning;
  bool _phaseTwoStarted = false;

  /// Merged stream: relays scan logs and accepts phase-2 status lines added
  /// via [_addPhaseTwoLog]. We own the controller so we can dispose it.
  final StreamController<ScanLogMessage> _logController =
      StreamController<ScanLogMessage>.broadcast();
  StreamSubscription<ScanLogMessage>? _scanSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to the scanner's stream once and forward into our controller.
    final scanLogStream = ref.read(scanLogStreamProvider);
    _scanSub = scanLogStream.listen(_logController.add);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _logController.close();
    super.dispose();
  }

  void _addPhaseTwoLog(ScanLogMessage msg) {
    if (_logController.isClosed) return;
    _logController.add(msg);
  }

  void _closeIfMounted() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  bool _rpfmErrorShown = false;

  /// Handle the case where RPFM-CLI is missing or invalid: skip phase 2 and
  /// surface a clear, actionable error dialog instead of silently closing
  /// the boot dialog with zero mods.
  void _handleRpfmUnavailable() {
    if (_rpfmErrorShown || _closed || !mounted) return;
    _rpfmErrorShown = true;
    _phaseTwoStarted = true; // prevent any later phase-2 trigger

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Capture the long-lived router up front: once the boot dialog pops,
      // the State's context is unmounted and `context.go(...)` becomes a
      // use-across-async-gap problem.
      final router = GoRouter.of(context);
      final goToSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.bootstrap.modScan.rpfmDialog.title),
          content: Text(t.bootstrap.modScan.rpfmDialog.content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.bootstrap.modScan.rpfmDialog.actions.close),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.bootstrap.modScan.rpfmDialog.actions.openSettings),
            ),
          ],
        ),
      );
      // Close the boot dialog first so navigation lands on a clean route
      // stack, then route to Settings if the user asked for it.
      _closeIfMounted();
      if (goToSettings == true) {
        router.go(AppRoutes.settings);
      }
    });
  }

  Future<void> _runPhaseTwo() async {
    if (_phaseTwoStarted) return;
    _phaseTwoStarted = true;
    if (!mounted) return;

    // Step 1 — discover whether there is anything to refresh.
    final ids = await ref
        .read(publishedSubsCacheProvider.notifier)
        .collectPublishedIds();

    // Empty case: skip phase 2 entirely. No title flip, no log lines.
    if (ids.isEmpty) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeIfMounted());
      return;
    }

    // Step 2 — announce the work and flip the title.
    _addPhaseTwoLog(ScanLogMessage.info(
      'Refreshing subscriber counts for ${ids.length} published translations…',
    ));
    if (mounted) {
      setState(() {
        _title = t.bootstrap.modScan.titleRefreshing;
      });
    }

    // Step 3 — fetch and report.
    bool ok = false;
    try {
      ok = await ref
          .read(publishedSubsCacheProvider.notifier)
          .refreshForIds(ids);
    } catch (_) {
      ok = false;
    }
    _addPhaseTwoLog(
      ok
          ? ScanLogMessage.info('Done.')
          : ScanLogMessage.error('Failed — subscriber counts unavailable.'),
    );

    // Step 4 — let the user see the final line, then close.
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
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
      if (next.hasError && next.error is RpfmNotFoundException) {
        _handleRpfmUnavailable();
        return;
      }
      if ((next.hasValue && !next.isLoading) || next.hasError) {
        unawaited(_runPhaseTwo());
      }
    });

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ScanTerminalWidget(
          logStream: _logController.stream,
          title: _title,
        ),
      ),
    );
  }
}
