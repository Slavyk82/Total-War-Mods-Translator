import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/settings/providers/update_providers.dart';
import '../providers/app_version_provider.dart';

/// Update checker widget for the navigation sidebar footer.
///
/// Displays the current version, a check for updates button, and shows
/// update available section when an update is detected - similar to settings.
class SidebarUpdateChecker extends ConsumerWidget {
  const SidebarUpdateChecker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(appVersionProvider);
    final updateState = ref.watch(updateCheckerProvider);
    final downloadState = ref.watch(updateDownloaderProvider);
    final theme = Theme.of(context);

    final version = versionAsync.when(
      data: (v) => v,
      loading: () => '...',
      error: (_, _) => 'Unknown',
    );

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Version info
          Row(
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Version: $version',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Check for updates button or update available section
          if (updateState.hasUpdate)
            _UpdateAvailableSection(
              updateState: updateState,
              downloadState: downloadState,
            )
          else
            _CheckUpdateButton(updateState: updateState),

          // Only show download errors (not update check errors like "no release found")
          if (downloadState.error != null) ...[
            const SizedBox(height: 8),
            _ErrorMessage(error: downloadState.error!),
          ],
        ],
      ),
    );
  }
}

/// Button to check for updates or display up-to-date status.
class _CheckUpdateButton extends ConsumerWidget {
  const _CheckUpdateButton({required this.updateState});

  final UpdateCheckState updateState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Determine button state
    final isUpToDate = updateState.lastChecked != null &&
                       !updateState.hasUpdate &&
                       !updateState.isChecking;

    // Choose icon based on state
    Widget icon;
    String label;

    if (updateState.isChecking) {
      icon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onPrimary,
        ),
      );
      label = 'Checking...';
    } else if (isUpToDate) {
      icon = const Icon(FluentIcons.checkmark_circle_24_regular, size: 14);
      label = 'Up-to-date';
    } else {
      icon = const Icon(FluentIcons.arrow_sync_24_regular, size: 14);
      label = 'Check for updates';
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: updateState.isChecking
            ? null
            : () {
                ref.read(updateCheckerProvider.notifier).checkForUpdates();
              },
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }
}

/// Section displayed when an update is available.
class _UpdateAvailableSection extends ConsumerWidget {
  const _UpdateAvailableSection({
    required this.updateState,
    required this.downloadState,
  });

  final UpdateCheckState updateState;
  final UpdateDownloadState downloadState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final release = updateState.availableUpdate!;
    final asset = release.windowsInstaller;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with version and dismiss button
          Row(
            children: [
              Icon(
                FluentIcons.arrow_download_24_filled,
                color: theme.colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'v${release.version} available',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  icon: Icon(
                    FluentIcons.dismiss_24_regular,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    ref.read(updateCheckerProvider.notifier).dismissUpdate();
                  },
                  tooltip: 'Dismiss',
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Download progress or action buttons
          if (downloadState.isDownloading)
            _DownloadProgress(downloadState: downloadState)
          else if (downloadState.downloadedPath != null)
            _InstallButton()
          else
            _DownloadButtons(release: release, asset: asset),
        ],
      ),
    );
  }
}

/// Download progress indicator.
class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.downloadState});

  final UpdateDownloadState downloadState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: downloadState.progress,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(downloadState.progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Downloading...',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Install button shown after download completes.
class _InstallButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          ref.read(updateDownloaderProvider.notifier).installUpdate();
        },
        icon: const Icon(FluentIcons.play_24_regular, size: 14),
        label: const Text('Install & Restart', style: TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 28),
        ),
      ),
    );
  }
}

/// Download and GitHub buttons.
class _DownloadButtons extends ConsumerWidget {
  const _DownloadButtons({
    required this.release,
    required this.asset,
  });

  final dynamic release;
  final dynamic asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asset != null && !asset.isEmpty)
          FilledButton.icon(
            onPressed: () {
              ref.read(updateDownloaderProvider.notifier).downloadUpdate(release);
            },
            icon: const Icon(FluentIcons.arrow_download_24_regular, size: 14),
            label: Text(
              'Download (${asset.formattedSize})',
              style: const TextStyle(fontSize: 12),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 28),
            ),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final url = Uri.parse(release.htmlUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
          icon: const Icon(FluentIcons.open_24_regular, size: 14),
          label: const Text('View on GitHub', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 28),
          ),
        ),
      ],
    );
  }
}

/// Error message display.
class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          FluentIcons.warning_24_regular,
          size: 12,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            error,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
