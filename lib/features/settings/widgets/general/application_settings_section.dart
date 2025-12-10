import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/update_providers.dart';
import 'settings_section_header.dart';

/// Application settings configuration section.
///
/// Allows users to configure general application preferences like auto-update.
class ApplicationSettingsSection extends ConsumerWidget {
  const ApplicationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateCheckerProvider);
    final downloadState = ref.watch(updateDownloaderProvider);
    final versionAsync = ref.watch(currentAppVersionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Application'),
        const SizedBox(height: 16),
        _buildVersionInfo(context, versionAsync),
        const SizedBox(height: 16),
        _buildCheckUpdateButton(context, ref, updateState),
        if (updateState.hasUpdate) ...[
          const SizedBox(height: 16),
          _buildUpdateAvailable(context, ref, updateState, downloadState),
        ],
        if (updateState.error != null) ...[
          const SizedBox(height: 8),
          _buildErrorMessage(context, updateState.error!),
        ],
        if (downloadState.error != null) ...[
          const SizedBox(height: 8),
          _buildErrorMessage(context, downloadState.error!),
        ],
      ],
    );
  }

  Widget _buildVersionInfo(BuildContext context, AsyncValue<String> versionAsync) {
    final version = versionAsync.when(
      data: (v) => v,
      loading: () => '...',
      error: (e, st) => 'Unknown',
    );

    return Row(
      children: [
        Icon(
          FluentIcons.info_24_regular,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Text(
          'Version: $version',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildCheckUpdateButton(
    BuildContext context,
    WidgetRef ref,
    UpdateCheckState updateState,
  ) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: updateState.isChecking
              ? null
              : () {
                  ref.read(updateCheckerProvider.notifier).checkForUpdates();
                },
          icon: updateState.isChecking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(FluentIcons.arrow_sync_24_regular, size: 16),
          label: Text(updateState.isChecking ? 'Checking...' : 'Check for updates'),
        ),
        if (updateState.lastChecked != null && !updateState.hasUpdate) ...[
          const SizedBox(width: 16),
          Text(
            updateState.availableUpdate == null && !updateState.isChecking
                ? 'You are up to date'
                : '',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildUpdateAvailable(
    BuildContext context,
    WidgetRef ref,
    UpdateCheckState updateState,
    UpdateDownloadState downloadState,
  ) {
    final release = updateState.availableUpdate!;
    final asset = release.windowsInstaller;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.arrow_download_24_filled,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update available: v${release.version}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                onPressed: () {
                  ref.read(updateCheckerProvider.notifier).dismissUpdate();
                },
                tooltip: 'Dismiss',
              ),
            ],
          ),
          if (release.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Release notes:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  release.body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (downloadState.isDownloading) ...[
            _buildDownloadProgress(context, downloadState),
          ] else if (downloadState.downloadedPath != null) ...[
            _buildInstallButton(context, ref),
          ] else ...[
            _buildDownloadButtons(context, ref, release, asset),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(
    BuildContext context,
    UpdateDownloadState downloadState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: downloadState.progress,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(downloadState.progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Downloading update...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildInstallButton(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () {
        ref.read(updateDownloaderProvider.notifier).installUpdate();
      },
      icon: const Icon(FluentIcons.play_24_regular, size: 16),
      label: const Text('Install and restart'),
    );
  }

  Widget _buildDownloadButtons(
    BuildContext context,
    WidgetRef ref,
    dynamic release,
    dynamic asset,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (asset != null && !asset.isEmpty)
          FilledButton.icon(
            onPressed: () {
              ref.read(updateDownloaderProvider.notifier).downloadUpdate(release);
            },
            icon: const Icon(FluentIcons.arrow_download_24_regular, size: 16),
            label: Text('Download (${asset.formattedSize})'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final url = Uri.parse(release.htmlUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
          icon: const Icon(FluentIcons.open_24_regular, size: 16),
          label: const Text('View on GitHub'),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(BuildContext context, String error) {
    return Row(
      children: [
        Icon(
          FluentIcons.warning_24_regular,
          size: 16,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ],
    );
  }
}
