import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/mods/mod_update_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed popup showing mod-update progress.
class ModUpdateDialog extends ConsumerWidget {
  const ModUpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final updateQueue = ref.watch(modUpdateQueueProvider);
    final allComplete = ref.read(modUpdateQueueProvider.notifier).allComplete;
    final total = updateQueue.length;

    return TokenDialog(
      icon: allComplete
          ? FluentIcons.checkmark_circle_24_regular
          : FluentIcons.arrow_download_24_regular,
      iconColor: allComplete ? tokens.ok : tokens.accent,
      title: allComplete ? t.mods.labels.updatesComplete : t.mods.labels.updatingMods,
      subtitle: allComplete
          ? t.mods.labels.allUpdatesProcessed
          : t.mods.labels.updatingCount(count: total),
      width: 720,
      body: SizedBox(
        height: 420,
        child: updateQueue.isEmpty
            ? _buildEmptyState(tokens)
            : ListView.separated(
                itemCount: updateQueue.values.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  return _UpdateItem(
                    updateInfo: updateQueue.values.toList()[index],
                  );
                },
              ),
      ),
      actions: _buildActions(context, ref, allComplete, tokens),
    );
  }

  Widget _buildEmptyState(TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.archive_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 16),
          Text(
            t.mods.labels.noUpdates,
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.mods.labels.noModsInQueue,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    bool allComplete,
    TwmtThemeTokens tokens,
  ) {
    return [
      if (!allComplete)
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: () =>
              ref.read(modUpdateQueueProvider.notifier).cancelAll(),
        ),
      SmallTextButton(
        label: allComplete ? t.common.actions.close : t.mods.actions.hide,
        filled: true,
        onTap: () => Navigator.of(context).pop(),
      ),
    ];
  }
}

class _UpdateItem extends ConsumerWidget {
  final ModUpdateInfo updateInfo;

  const _UpdateItem({required this.updateInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.cube_24_regular,
                color: tokens.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  updateInfo.projectName,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusBadge(status: updateInfo.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _getStatusMessage(updateInfo.status),
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.textDim,
            ),
          ),
          if (updateInfo.isInProgress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              child: LinearProgressIndicator(
                value: updateInfo.progress,
                minHeight: 6,
                backgroundColor: tokens.panel,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(updateInfo.progress * 100).toInt()}%',
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: tokens.textDim,
              ),
            ),
          ],
          if (updateInfo.isFailed && updateInfo.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.errBg,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.error_circle_24_regular,
                    color: tokens.err,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      updateInfo.errorMessage!,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.err,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SmallTextButton(
              label: t.mods.actions.retry,
              icon: FluentIcons.arrow_clockwise_24_regular,
              onTap: () => ref
                  .read(modUpdateQueueProvider.notifier)
                  .retry(updateInfo.projectId),
            ),
          ],
          if (updateInfo.isCompleted && updateInfo.newVersion != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.okBg,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.ok.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.checkmark_circle_24_regular,
                    color: tokens.ok,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.mods.updateStatus.updatedToVersion(version: updateInfo.newVersion!.versionString),
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.ok,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusMessage(ModUpdateStatus status) {
    switch (status) {
      case ModUpdateStatus.pending:
        return t.mods.updateStatus.waitingToStart;
      case ModUpdateStatus.downloading:
        return t.mods.updateStatus.downloading;
      case ModUpdateStatus.detectingChanges:
        return t.mods.updateStatus.detectingChanges;
      case ModUpdateStatus.updatingDatabase:
        return t.mods.updateStatus.updatingDatabase;
      case ModUpdateStatus.completed:
        return t.mods.updateStatus.successfullyUpdated;
      case ModUpdateStatus.failed:
        return t.mods.updateStatus.updateFailed;
      case ModUpdateStatus.cancelled:
        return t.mods.updateStatus.cancelled;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final ModUpdateStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    late final Color color;
    late final IconData icon;
    late final String label;

    switch (status) {
      case ModUpdateStatus.pending:
        color = tokens.textDim;
        icon = FluentIcons.clock_24_regular;
        label = t.mods.updateStatus.pending;
        break;
      case ModUpdateStatus.downloading:
      case ModUpdateStatus.detectingChanges:
      case ModUpdateStatus.updatingDatabase:
        color = tokens.accent;
        icon = FluentIcons.arrow_download_24_regular;
        label = t.mods.updateStatus.inProgress;
        break;
      case ModUpdateStatus.completed:
        color = tokens.ok;
        icon = FluentIcons.checkmark_circle_24_regular;
        label = t.mods.updateStatus.completed;
        break;
      case ModUpdateStatus.failed:
        color = tokens.err;
        icon = FluentIcons.error_circle_24_regular;
        label = t.mods.updateStatus.failed;
        break;
      case ModUpdateStatus.cancelled:
        color = tokens.textFaint;
        icon = FluentIcons.dismiss_circle_24_regular;
        label = t.mods.updateStatus.cancelledBadge;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: tokens.fontBody.copyWith(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
