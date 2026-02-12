import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../../services/steam/steamcmd_manager.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';

enum _InstallPhase { confirm, downloading, success, error }

/// Dialog proposing to download and install SteamCMD when it's not found.
class SteamCmdInstallDialog extends StatefulWidget {
  const SteamCmdInstallDialog({super.key});

  /// Show the install dialog. Returns `true` if installation succeeded.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SteamCmdInstallDialog(),
    );
    return result ?? false;
  }

  @override
  State<SteamCmdInstallDialog> createState() => _SteamCmdInstallDialogState();
}

class _SteamCmdInstallDialogState extends State<SteamCmdInstallDialog> {
  _InstallPhase _phase = _InstallPhase.confirm;
  double _progress = 0;
  String? _errorMessage;

  Future<void> _startInstall() async {
    setState(() {
      _phase = _InstallPhase.downloading;
      _progress = 0;
    });

    final result = await SteamCmdManager().downloadAndInstall(
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
    );

    if (!mounted) return;

    result.when(
      ok: (_) => setState(() => _phase = _InstallPhase.success),
      err: (error) => setState(() {
        _phase = _InstallPhase.error;
        _errorMessage = error.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildContent(theme),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            FluentIcons.arrow_download_24_regular,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SteamCMD Required',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Valve command-line tool for Workshop uploads',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return switch (_phase) {
      _InstallPhase.confirm => _buildConfirm(theme),
      _InstallPhase.downloading => _buildDownloading(theme),
      _InstallPhase.success => _buildSuccess(theme),
      _InstallPhase.error => _buildError(theme),
    };
  }

  Widget _buildConfirm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SteamCMD was not found on your system. '
          'It is required to publish mods to the Steam Workshop.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Would you like to download and install it automatically? '
          'The download is approximately 3 MB from Valve servers.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildDownloading(ThemeData theme) {
    final progressPercent = (_progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Downloading SteamCMD...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$progressPercent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FluentProgressBar(
            value: _progress,
            height: 8,
            color: theme.colorScheme.primary,
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 8),
          Text(
            'Downloading from Valve CDN...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.checkmark_circle_24_filled,
              size: 24, color: Colors.green.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SteamCMD installed successfully',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You can now publish to the Steam Workshop.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.error_circle_24_filled,
              size: 24, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Installation failed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_phase == _InstallPhase.confirm) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _startInstall,
              icon: const Icon(FluentIcons.arrow_download_24_regular,
                  size: 18),
              label: const Text('Install'),
            ),
          ],
          if (_phase == _InstallPhase.downloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Cancel'),
            ),
          if (_phase == _InstallPhase.success)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon:
                  const Icon(FluentIcons.checkmark_24_regular, size: 18),
              label: const Text('Continue'),
            ),
          if (_phase == _InstallPhase.error) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _startInstall,
              icon: const Icon(FluentIcons.arrow_sync_24_regular,
                  size: 18),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
