import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../providers/shared/service_providers.dart';

enum _InstallPhase { confirm, downloading, success, error }

/// Token-themed popup that proposes to download and install SteamCMD when
/// it's not found locally.
class SteamCmdInstallDialog extends ConsumerStatefulWidget {
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
  ConsumerState<SteamCmdInstallDialog> createState() =>
      _SteamCmdInstallDialogState();
}

class _SteamCmdInstallDialogState extends ConsumerState<SteamCmdInstallDialog> {
  _InstallPhase _phase = _InstallPhase.confirm;
  double _progress = 0;
  String? _errorMessage;

  Future<void> _startInstall() async {
    setState(() {
      _phase = _InstallPhase.downloading;
      _progress = 0;
    });

    final manager = ref.read(steamCmdManagerProvider);
    final result = await manager.downloadAndInstall(
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
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.arrow_download_24_regular,
      title: t.steamPublish.steamcmdDialog.title,
      subtitle: t.steamPublish.steamcmdDialog.subtitle,
      width: 520,
      body: _buildContent(tokens),
      actions: _buildActions(tokens),
    );
  }

  Widget _buildContent(TwmtThemeTokens tokens) {
    return switch (_phase) {
      _InstallPhase.confirm => _buildConfirm(tokens),
      _InstallPhase.downloading => _buildDownloading(tokens),
      _InstallPhase.success => _buildSuccess(tokens),
      _InstallPhase.error => _buildError(tokens),
    };
  }

  Widget _buildConfirm(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.steamPublish.steamcmdDialog.confirmText,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t.steamPublish.steamcmdDialog.confirmText2,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloading(TwmtThemeTokens tokens) {
    final progressPercent = (_progress * 100).toStringAsFixed(0);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.steamPublish.steamcmdDialog.downloading,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$progressPercent%',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: tokens.panel,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.steamPublish.steamcmdDialog.downloadingFrom,
            style: tokens.fontBody.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(TwmtThemeTokens tokens) {
    return _StatusBanner(
      icon: FluentIcons.checkmark_circle_24_filled,
      color: tokens.ok,
      bgColor: tokens.okBg,
      title: t.steamPublish.steamcmdDialog.successTitle,
      subtitle: t.steamPublish.steamcmdDialog.successMessage,
    );
  }

  Widget _buildError(TwmtThemeTokens tokens) {
    return _StatusBanner(
      icon: FluentIcons.error_circle_24_filled,
      color: tokens.err,
      bgColor: tokens.errBg,
      title: t.steamPublish.steamcmdDialog.errorTitle,
      subtitle: _errorMessage,
    );
  }

  List<Widget> _buildActions(TwmtThemeTokens tokens) {
    switch (_phase) {
      case _InstallPhase.confirm:
        return [
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.cancel,
            onTap: () => Navigator.of(context).pop(false),
          ),
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.install,
            icon: FluentIcons.arrow_download_24_regular,
            filled: true,
            onTap: _startInstall,
          ),
        ];
      case _InstallPhase.downloading:
        return [
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.cancel,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ];
      case _InstallPhase.success:
        return [
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.kContinue,
            icon: FluentIcons.checkmark_24_regular,
            filled: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ];
      case _InstallPhase.error:
        return [
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.close,
            onTap: () => Navigator.of(context).pop(false),
          ),
          SmallTextButton(
            label: t.steamPublish.steamcmdDialog.retry,
            icon: FluentIcons.arrow_sync_24_regular,
            filled: true,
            onTap: _startInstall,
          ),
        ];
    }
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;
  final String? subtitle;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12,
                      color: color,
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
}
