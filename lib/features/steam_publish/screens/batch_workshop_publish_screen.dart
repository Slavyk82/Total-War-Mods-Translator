import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';

import '../../../features/translation_editor/screens/progress/progress_widgets.dart';
import '../providers/batch_workshop_publish_notifier.dart';
import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import '../widgets/steam_guard_dialog.dart';

/// Workshop Publish batch screen (§7.5 degenerate wizard archetype).
///
/// Layout: [WizardScreenLayout] = [DetailScreenToolbar] +
/// [StickyFormPanel] (single "Staging" section — the form becomes the
/// summary here) + [DynamicZonePanel] hosting an overall progress header,
/// a scrollable per-pack row list and an inline log terminal.
///
/// Reads [batchPublishStagingProvider] in [initState] and kicks off
/// [BatchWorkshopPublishNotifier.publishBatch] via an
/// `addPostFrameCallback`. Preserves the 1-second elapsed timer and the
/// [SteamGuardDialog] post-frame trigger.
class BatchWorkshopPublishScreen extends ConsumerStatefulWidget {
  const BatchWorkshopPublishScreen({super.key});

  @override
  ConsumerState<BatchWorkshopPublishScreen> createState() =>
      _BatchWorkshopPublishScreenState();
}

class _BatchWorkshopPublishScreenState
    extends ConsumerState<BatchWorkshopPublishScreen> {
  late final DateTime _startTime;
  bool _steamGuardDialogShown = false;
  late final BatchWorkshopPublishNotifier _publishNotifier;
  BatchPublishStagingData? _stagingData;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _stagingData = ref.read(batchPublishStagingProvider);
    _publishNotifier = ref.read(batchWorkshopPublishProvider.notifier);

    // Elapsed timer: rebuild once per second so the Staging > Elapsed row
    // stays live.
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    if (_stagingData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _publishNotifier.publishBatch(
          items: _stagingData!.items,
          username: _stagingData!.username,
          password: _stagingData!.password,
          steamGuardCode: _stagingData!.steamGuardCode,
        );
      });
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    // Guard against missing ServiceLocator registration (tests) — the
    // notifier reads services that may not be registered in pure widget
    // tests.
    try {
      _publishNotifier.silentCleanup();
    } catch (_) {
      // Ignore — nothing to clean up in a test context.
    }
    super.dispose();
  }

  String get _elapsedTime {
    final elapsed = DateTime.now().difference(_startTime);
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  Future<bool> _confirmLeaveIfActive() async {
    final state = ref.read(batchWorkshopPublishProvider);
    if (!state.isPublishing) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publication in progress'),
        content: const Text(
          'A batch publication is currently in progress. Are you sure you '
          'want to leave? The remaining uploads will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBack() async {
    if (await _confirmLeaveIfActive()) {
      if (mounted) {
        ref.invalidate(publishableItemsProvider);
        if (context.canPop()) context.pop();
      }
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel batch publish?'),
        content: const Text(
          'Remaining uploads will be aborted. Already-uploaded items are not '
          'rolled back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(batchWorkshopPublishProvider.notifier).cancel();
    }
  }

  ({int publish, int update}) _modeCounts(List<BatchPublishItemInfo> items) {
    var publish = 0;
    var update = 0;
    for (final item in items) {
      final id = item.params.publishedFileId;
      if (id.isEmpty || id == '0') {
        publish++;
      } else {
        update++;
      }
    }
    return (publish: publish, update: update);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Fallback when no batch has been staged. Renders a toolbar + empty
    // message so users can still navigate back.
    if (_stagingData == null) {
      return Material(
        color: tokens.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailScreenToolbar(
              crumb: 'Publishing > Steam Workshop > No items staged',
              onBack: () {
                if (context.canPop()) context.pop();
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  'No items to publish.',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.textDim,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final state = ref.watch(batchWorkshopPublishProvider);
    final items = _stagingData!.items;
    final counts = _modeCounts(items);

    // Surface the Steam Guard dialog when the notifier signals it. The flag
    // prevents stacking multiple dialogs across rebuilds.
    if (state.needsSteamGuard && !_steamGuardDialogShown) {
      _steamGuardDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _steamGuardDialogShown = false;
          return;
        }
        final code = await SteamGuardDialog.show(context);
        if (!mounted) {
          _steamGuardDialogShown = false;
          return;
        }
        _steamGuardDialogShown = false;
        if (code != null) {
          ref
              .read(batchWorkshopPublishProvider.notifier)
              .retryWithSteamGuard(code);
        } else {
          ref.read(batchWorkshopPublishProvider.notifier).cancel();
        }
      });
    }

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        crumb:
            'Publishing > Steam Workshop > Batch (${items.length} packs)',
        onBack: _handleBack,
      ),
      formPanel: StickyFormPanel(
        sections: [
          FormSection(
            label: 'Staging',
            children: [
              _StagingRow(
                label: 'Packs',
                value: '${items.length}',
              ),
              const _StagingRow(
                label: 'Total size',
                value: '—',
              ),
              _StagingRow(
                label: 'Publish',
                value: '${counts.publish}',
              ),
              _StagingRow(
                label: 'Update',
                value: '${counts.update}',
              ),
              _StagingRow(
                label: 'Account',
                value: _stagingData!.username.isEmpty
                    ? '—'
                    : _stagingData!.username,
              ),
              _StagingRow(
                label: 'Elapsed',
                value: _elapsedTime,
              ),
              _StagingRow(
                label: 'Completed',
                value: '${state.completedItems} / ${state.totalItems}',
              ),
            ],
          ),
        ],
        actions: [
          if (state.isPublishing && !state.isCancelled)
            SmallTextButton(
              label: 'Stop',
              icon: FluentIcons.stop_24_regular,
              onTap: _confirmCancel,
            )
          else
            SmallTextButton(
              label: 'Close',
              icon: FluentIcons.dismiss_24_regular,
              onTap: () {
                ref.invalidate(publishableItemsProvider);
                if (context.canPop()) context.pop();
              },
            ),
        ],
      ),
      dynamicZone: DynamicZonePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OverallProgressHeader(state: state),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.panel2,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: tokens.border,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final status = state.itemStatuses[item.name] ??
                          BatchPublishStatus.pending;
                      final isCurrent = state.currentItemName == item.name;
                      final result = state.results
                          .cast<BatchPublishItemResult?>()
                          .firstWhere(
                            (r) => r?.name == item.name,
                            orElse: () => null,
                          );
                      final existingId = item.params.publishedFileId;
                      final isUpdate =
                          existingId.isNotEmpty && existingId != '0';
                      return _BatchPackRow(
                        name: item.name,
                        isUpdate: isUpdate,
                        status: status,
                        progress: isCurrent ? state.currentItemProgress : null,
                        result: result,
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 240, child: LogTerminal()),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form panel row
// ---------------------------------------------------------------------------

/// Thin label/value row used inside the Staging form section.
class _StagingRow extends StatelessWidget {
  final String label;
  final String value;

  const _StagingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textMid,
            ),
          ),
        ),
        Text(
          value,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic-zone sub-views
// ---------------------------------------------------------------------------

/// Compact overall progress card: completed/total count, percent, bar.
class _OverallProgressHeader extends StatelessWidget {
  final BatchWorkshopPublishState state;

  const _OverallProgressHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = (state.overallProgress * 100).toStringAsFixed(0);
    final hasFailures = state.failedCount > 0;
    final isDone = state.isComplete;

    final Color accentColor;
    final String heading;
    if (isDone && !hasFailures) {
      accentColor = tokens.ok;
      heading = 'Batch publish complete';
    } else if (isDone && hasFailures) {
      accentColor = tokens.warn;
      heading = 'Completed with errors';
    } else if (state.isCancelled) {
      accentColor = tokens.err;
      heading = 'Cancelled';
    } else if (state.needsSteamGuard) {
      accentColor = tokens.warn;
      heading = 'Steam Guard required';
    } else {
      accentColor = tokens.accent;
      heading = 'Publishing...';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.cloud_arrow_up_24_regular,
                size: 18,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  heading,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 14,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${state.completedItems} / ${state.totalItems}',
                style: tokens.fontMono.copyWith(
                  fontSize: 12,
                  color: tokens.textMid,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$percent%',
                style: tokens.fontMono.copyWith(
                  fontSize: 12,
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.overallProgress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: tokens.panel,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          if (state.currentItemName != null && state.isPublishing) ...[
            const SizedBox(height: 10),
            Text(
              'Current: ${state.currentItemName}',
              style: tokens.fontMono.copyWith(
                fontSize: 11,
                color: tokens.textDim,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Single per-pack row in the dynamic zone list.
class _BatchPackRow extends StatelessWidget {
  final String name;
  final bool isUpdate;
  final BatchPublishStatus status;
  final double? progress;
  final BatchPublishItemResult? result;

  const _BatchPackRow({
    required this.name,
    required this.isUpdate,
    required this.status,
    required this.progress,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final highlight = status == BatchPublishStatus.inProgress;
    final barProgress = switch (status) {
      BatchPublishStatus.success => 1.0,
      BatchPublishStatus.failed => progress ?? 0.0,
      BatchPublishStatus.cancelled => progress ?? 0.0,
      BatchPublishStatus.pending => 0.0,
      BatchPublishStatus.inProgress => progress ?? 0.0,
    };
    final barColor = switch (status) {
      BatchPublishStatus.success => tokens.ok,
      BatchPublishStatus.failed => tokens.err,
      BatchPublishStatus.cancelled => tokens.textFaint,
      BatchPublishStatus.pending => tokens.textFaint,
      BatchPublishStatus.inProgress => tokens.accent,
    };

    return Container(
      color: highlight ? tokens.rowSelected.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          color: tokens.text,
                          fontWeight:
                              highlight ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ModePill(isUpdate: isUpdate),
                  ],
                ),
                if (result != null &&
                    result!.success &&
                    result!.workshopId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Workshop ID: ${result!.workshopId}',
                    style: tokens.fontMono.copyWith(
                      fontSize: 10,
                      color: tokens.textDim,
                    ),
                  ),
                ],
                if (result != null &&
                    !result!.success &&
                    result!.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    result!.errorMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontBody.copyWith(
                      fontSize: 11,
                      color: tokens.err,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barProgress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: tokens.panel,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusPillFor(status: status),
        ],
      ),
    );
  }
}

/// Small publish/update indicator rendered next to the pack name.
class _ModePill extends StatelessWidget {
  final bool isUpdate;
  const _ModePill({required this.isUpdate});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = isUpdate ? 'UPDATE' : 'PUBLISH';
    final fg = isUpdate ? tokens.accent : tokens.ok;
    final bg = isUpdate ? tokens.accentBg : tokens.okBg;
    return StatusPill(label: label, foreground: fg, background: bg);
  }
}

/// Maps a [BatchPublishStatus] to a semantic [StatusPill].
class _StatusPillFor extends StatelessWidget {
  final BatchPublishStatus status;
  const _StatusPillFor({required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    switch (status) {
      case BatchPublishStatus.pending:
        return StatusPill(
          label: 'PENDING',
          foreground: tokens.textDim,
          background: tokens.panel,
        );
      case BatchPublishStatus.inProgress:
        return StatusPill(
          label: 'UPLOADING',
          foreground: tokens.accent,
          background: tokens.accentBg,
        );
      case BatchPublishStatus.success:
        return StatusPill(
          label: 'DONE',
          foreground: tokens.ok,
          background: tokens.okBg,
          icon: FluentIcons.checkmark_24_regular,
        );
      case BatchPublishStatus.failed:
        return StatusPill(
          label: 'FAILED',
          foreground: tokens.err,
          background: tokens.errBg,
          icon: FluentIcons.error_circle_24_regular,
        );
      case BatchPublishStatus.cancelled:
        return StatusPill(
          label: 'CANCELLED',
          foreground: tokens.textFaint,
          background: tokens.panel,
        );
    }
  }
}
