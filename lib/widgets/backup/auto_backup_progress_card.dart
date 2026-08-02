import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';

import '../../models/backup/backup_progress.dart';
import '../../providers/backup/auto_backup_progress_provider.dart';
import '../../theme/twmt_theme_tokens.dart';

/// Discreet bottom-right card reporting the startup automatic backup.
///
/// Designed to sit as a direct child of the `MaterialApp.builder` [Stack],
/// beside `LogConsoleOverlay`, so it survives navigation and is not tied to
/// the router shell. It renders a [Positioned] when visible and an empty box
/// otherwise, and it never blocks input: a [Stack] only absorbs pointer events
/// inside its positioned children.
///
/// The backup itself is non-blocking — compression runs in a background
/// isolate — so this card is purely informative. Its job is to explain the
/// disk activity, which users previously experienced as a frozen app.
///
/// Unlike `LogConsoleOverlay` this needs no nested [Overlay]: it hosts no
/// tooltip and no selectable text.
class AutoBackupProgressCard extends ConsumerStatefulWidget {
  const AutoBackupProgressCard({super.key});

  /// How long the "done" confirmation stays before the card fades out. Long
  /// enough to be read, short enough not to linger.
  static const doneHold = Duration(milliseconds: 1500);

  @override
  ConsumerState<AutoBackupProgressCard> createState() =>
      _AutoBackupProgressCardState();
}

class _AutoBackupProgressCardState
    extends ConsumerState<AutoBackupProgressCard> {
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  /// Start the auto-dismiss countdown when the backup completes. The error
  /// state deliberately gets no timer: a failed backup is a data-safety matter
  /// and stays until the user acknowledges it.
  void _scheduleDismissIfDone(AutoBackupUiState state) {
    if (state is! AutoBackupDone) {
      _doneTimer?.cancel();
      _doneTimer = null;
      return;
    }
    if (_doneTimer != null) return;
    _doneTimer = Timer(AutoBackupProgressCard.doneHold, () {
      _doneTimer = null;
      if (mounted) {
        ref.read(autoBackupStatusProvider.notifier).dismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(autoBackupStatusProvider);
    _scheduleDismissIfDone(state);

    if (state is AutoBackupIdle) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        // Keyed by the state's *type* (not the whole card) so the switcher
        // only cross-fades on a Running/Done/Error transition, not on every
        // Running rebuild carrying a new BackupProgress. The Material inside
        // keeps its own const Key('autoBackupCard') so existing find.byKey
        // lookups in tests keep working across the transition.
        child: KeyedSubtree(
          key: ValueKey(state.runtimeType),
          child: _card(context, state),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AutoBackupUiState state) {
    final tokens = context.tokens;
    final isError = state is AutoBackupError;

    return Material(
      key: const Key('autoBackupCard'),
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? tokens.errBg : tokens.panel,
          border: Border.all(color: isError ? tokens.err : tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _body(context, state, tokens),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AutoBackupUiState state,
    TwmtThemeTokens tokens,
  ) {
    switch (state) {
      case AutoBackupIdle():
        return const [];

      case AutoBackupRunning(:final progress):
        return [
          Text(
            t.bootstrap.autoBackup.title,
            style: TextStyle(color: tokens.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            switch (progress.phase) {
              BackupPhase.snapshot => t.bootstrap.autoBackup
                  .snapshotting(size: progress.formattedBytes),
              BackupPhase.compressing => t.bootstrap.autoBackup
                  .compressing(size: progress.formattedBytes),
            },
            style: TextStyle(color: tokens.textMid, fontSize: 12),
          ),
          const SizedBox(height: 10),
          // Always indeterminate: neither phase has an honest denominator.
          const LinearProgressIndicator(),
        ];

      case AutoBackupDone():
        return [
          Text(
            t.bootstrap.autoBackup.done,
            style: TextStyle(color: tokens.ok, fontWeight: FontWeight.w600),
          ),
        ];

      case AutoBackupError(:final message):
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.bootstrap.autoBackup.failedTitle,
                  style: TextStyle(
                    color: tokens.err,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                key: const Key('autoBackupDismiss'),
                onTap: () =>
                    ref.read(autoBackupStatusProvider.notifier).dismiss(),
                child: Icon(Icons.close, size: 16, color: tokens.textMid),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // English by project convention (log content is never localized);
          // shown as diagnostic detail under the localized title above.
          Text(
            message,
            style: TextStyle(color: tokens.textDim, fontSize: 11),
          ),
        ];
    }
  }
}
