import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../config/app_constants.dart';
import '../../../models/history/diff_models.dart';
import '../../../providers/history/history_providers.dart';
import '../../../providers/shared/service_providers.dart';

/// Token-themed side-by-side popup comparing two translation versions.
class VersionComparisonDialog extends ConsumerStatefulWidget {
  final String historyId1;
  final String historyId2;
  final String versionId;

  const VersionComparisonDialog({
    super.key,
    required this.historyId1,
    required this.historyId2,
    required this.versionId,
  });

  @override
  ConsumerState<VersionComparisonDialog> createState() =>
      _VersionComparisonDialogState();
}

class _VersionComparisonDialogState
    extends ConsumerState<VersionComparisonDialog> {
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  final bool _syncScrolling = true;

  @override
  void initState() {
    super.initState();
    _setupScrollSync();
  }

  void _setupScrollSync() {
    _leftScrollController.addListener(() {
      if (_syncScrolling && _leftScrollController.hasClients) {
        _rightScrollController.jumpTo(_leftScrollController.offset);
      }
    });
    _rightScrollController.addListener(() {
      if (_syncScrolling && _rightScrollController.hasClients) {
        _leftScrollController.jumpTo(_rightScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final media = MediaQuery.of(context);
    final comparisonAsync = ref.watch(
      versionComparisonProvider(widget.historyId1, widget.historyId2),
    );

    return TokenDialog(
      icon: FluentIcons.document_text_link_24_regular,
      title: 'Compare Versions',
      width: media.size.width * 0.8,
      body: SizedBox(
        height: media.size.height * 0.72,
        child: comparisonAsync.when(
          data: (comparison) => _buildComparison(tokens, comparison),
          loading: () => Center(
            child: CircularProgressIndicator(color: tokens.accent),
          ),
          error: (error, _) => _buildError(tokens, error),
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildComparison(
    TwmtThemeTokens tokens,
    VersionComparison comparison,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildVersionPanel(
                      tokens,
                      comparison.version1,
                      'Old Version',
                      comparison.diff,
                      true,
                      _leftScrollController,
                    ),
                  ),
                  Container(width: 1, color: tokens.border),
                  Expanded(
                    child: _buildVersionPanel(
                      tokens,
                      comparison.version2,
                      'New Version',
                      comparison.diff,
                      false,
                      _rightScrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildStatistics(tokens, comparison.stats),
        const SizedBox(height: 12),
        _buildActionRow(tokens, comparison),
      ],
    );
  }

  Widget _buildVersionPanel(
    TwmtThemeTokens tokens,
    dynamic version,
    String title,
    List<DiffSegment> diff,
    bool isOld,
    ScrollController scrollController,
  ) {
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(version.createdAt * 1000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border(
              bottom: BorderSide(color: tokens.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    version.isUserChange
                        ? FluentIcons.person_24_regular
                        : FluentIcons.bot_24_regular,
                    size: 14,
                    color: tokens.textDim,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    version.changedByDisplay,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12,
                      color: tokens.textDim,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeago.format(timestamp),
                    style: tokens.fontBody.copyWith(
                      fontSize: 12,
                      color: tokens.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: SelectableText.rich(
              _buildDiffTextSpan(tokens, diff, isOld),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _buildDiffTextSpan(
    TwmtThemeTokens tokens,
    List<DiffSegment> diff,
    bool isOld,
  ) {
    final spans = <TextSpan>[];

    for (final segment in diff) {
      Color? backgroundColor;
      TextDecoration? decoration;

      if (isOld) {
        if (segment.type == DiffType.removed) {
          backgroundColor = tokens.err.withValues(alpha: 0.25);
          decoration = TextDecoration.lineThrough;
        } else if (segment.type == DiffType.added) {
          continue;
        }
      } else {
        if (segment.type == DiffType.added) {
          backgroundColor = tokens.ok.withValues(alpha: 0.25);
        } else if (segment.type == DiffType.removed) {
          continue;
        }
      }

      spans.add(
        TextSpan(
          text: segment.text,
          style: tokens.fontMono.copyWith(
            fontSize: 13,
            color: tokens.text,
            backgroundColor: backgroundColor,
            decoration: decoration,
          ),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  Widget _buildStatistics(TwmtThemeTokens tokens, DiffStats stats) {
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
          Text(
            'Changes',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStatItem(
                  tokens, 'Characters Added', stats.charsAdded, tokens.ok),
              _buildStatItem(
                  tokens, 'Characters Removed', stats.charsRemoved, tokens.err),
              _buildStatItem(
                  tokens, 'Words Added', stats.wordsAdded, tokens.ok),
              _buildStatItem(
                  tokens, 'Words Removed', stats.wordsRemoved, tokens.err),
              _buildStatItem(
                  tokens, 'Total Changes', stats.charsChanged, tokens.info),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    TwmtThemeTokens tokens,
    String label,
    int value,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
        Text(
          '$value',
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    TwmtThemeTokens tokens,
    VersionComparison comparison,
  ) {
    return Row(
      children: [
        SmallTextButton(
          label: 'Copy Old',
          icon: FluentIcons.copy_24_regular,
          onTap: () => _copyToClipboard(comparison.version1.translatedText),
        ),
        const SizedBox(width: 8),
        SmallTextButton(
          label: 'Copy New',
          icon: FluentIcons.copy_24_regular,
          onTap: () => _copyToClipboard(comparison.version2.translatedText),
        ),
        const Spacer(),
        SmallTextButton(
          label: 'Restore Old',
          icon: FluentIcons.arrow_undo_24_regular,
          filled: true,
          onTap: () => _restoreVersion(context, comparison.version1),
        ),
      ],
    );
  }

  Widget _buildError(TwmtThemeTokens tokens, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: tokens.err,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to compare versions',
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      FluentToast.success(context, 'Copied to clipboard');
    }
  }

  Future<void> _restoreVersion(BuildContext context, dynamic version) async {
    final confirmed = await TokenDialog.showConfirm(
      context,
      icon: FluentIcons.arrow_undo_24_regular,
      title: 'Restore Version',
      message: 'Are you sure you want to restore this version?\n\n'
          'Preview:\n"${version.getTranslatedTextPreview(100)}"',
      confirmLabel: 'Restore',
    );

    if (confirmed && mounted) {
      final service = ref.read(historyServiceProvider);
      final result = await service.revertToVersion(
        versionId: widget.versionId,
        historyId: version.id,
        changedBy: AppConstants.defaultUserId,
      );

      if (mounted) {
        result.when(
          ok: (_) {
            FluentToast.success(context, 'Version restored successfully');
            Navigator.of(context).pop();
          },
          err: (error) {
            FluentToast.error(context, 'Failed to restore: $error');
          },
        );
      }
    }
  }
}
