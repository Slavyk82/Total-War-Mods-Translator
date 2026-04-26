import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/translation_version.dart';
import '../../../models/domain/translation_version_history.dart';
import '../../../providers/shared/service_providers.dart';

/// Token-themed popup showing the historical edits of a translation version.
class TranslationHistoryDialog extends ConsumerStatefulWidget {
  final String versionId;
  final String unitKey;

  const TranslationHistoryDialog({
    super.key,
    required this.versionId,
    required this.unitKey,
  });

  @override
  ConsumerState<TranslationHistoryDialog> createState() =>
      _TranslationHistoryDialogState();
}

class _TranslationHistoryDialogState
    extends ConsumerState<TranslationHistoryDialog> {
  List<TranslationVersionHistory>? _history;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(translationVersionHistoryRepositoryProvider);
      final result = await repository.getByVersion(widget.versionId);

      result.when(
        ok: (history) {
          if (mounted) {
            setState(() {
              _history = history;
              _isLoading = false;
            });
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _error = error.toString();
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TokenDialog(
      icon: FluentIcons.history_24_regular,
      title: t.translationEditor.dialogs.translationHistory.title,
      subtitle: t.translationEditor.dialogs.promptPreview.keyLabel(key: widget.unitKey),
      width: 720,
      body: SizedBox(
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(height: 1, color: tokens.border),
            const SizedBox(height: 12),
            Expanded(child: _buildContent(tokens)),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.close,
          filled: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildContent(TwmtThemeTokens tokens) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    if (_error != null) {
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
              t.translationEditor.dialogs.translationHistory.errorLoading,
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
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

    if (_history == null || _history!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.history_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              t.translationEditor.dialogs.translationHistory.noHistory,
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.translationEditor.dialogs.translationHistory.noHistoryDetail,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _history!.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: tokens.border,
      ),
      itemBuilder: (context, index) {
        return _buildHistoryEntry(tokens, _history![index]);
      },
    );
  }

  Widget _buildHistoryEntry(
    TwmtThemeTokens tokens,
    TranslationVersionHistory entry,
  ) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateStr = dateFormat.format(entry.createdAtAsDateTime);
    final statusColor = _statusColor(tokens, entry.status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _statusIcon(entry.status),
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                entry.statusDisplay,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                FluentIcons.person_24_regular,
                size: 14,
                color: tokens.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                entry.changedByDisplay,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.textDim,
                ),
              ),
              const Spacer(),
              Icon(
                FluentIcons.clock_24_regular,
                size: 14,
                color: tokens.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                dateStr,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.panel2,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: Text(
              entry.translatedText,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
              ),
            ),
          ),
          if (entry.hasChangeReason) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 14,
                  color: tokens.textFaint,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reason: ${entry.changeReason}',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textDim,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon(TranslationVersionStatus status) {
    switch (status) {
      case TranslationVersionStatus.pending:
        return FluentIcons.circle_24_regular;
      case TranslationVersionStatus.translated:
        return FluentIcons.checkmark_circle_24_regular;
      case TranslationVersionStatus.needsReview:
        return FluentIcons.warning_24_regular;
    }
  }

  Color _statusColor(TwmtThemeTokens tokens, TranslationVersionStatus status) {
    switch (status) {
      case TranslationVersionStatus.pending:
        return tokens.textFaint;
      case TranslationVersionStatus.translated:
        return tokens.ok;
      case TranslationVersionStatus.needsReview:
        return tokens.warn;
    }
  }
}
