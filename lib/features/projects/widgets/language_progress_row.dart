import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Single-language row for Project Detail — consumes [ListRow] with fixed
/// columns and a status pill derived from translation progress.
class LanguageProgressRow extends StatelessWidget {
  final ProjectLanguageDetails langDetails;
  final VoidCallback? onOpenEditor;
  final VoidCallback? onDelete;

  const LanguageProgressRow({
    super.key,
    required this.langDetails,
    this.onOpenEditor,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = langDetails.progressPercent;
    final percentInt = percent.clamp(0, 100).toInt();
    final barColor = _progressColor(tokens, percent);
    final (pillLabel, pillFg, pillBg) = _statusAppearance(tokens, percent);

    return ListRow(
      columns: const [
        ListRowColumn.flex(1),
        ListRowColumn.fixed(60),
        ListRowColumn.fixed(120),
        ListRowColumn.fixed(100),
      ],
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                langDetails.language.displayName,
                overflow: TextOverflow.ellipsis,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              label: pillLabel,
              foreground: pillFg,
              background: pillBg,
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$percentInt%',
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: barColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 4,
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${langDetails.translatedUnits} / ${langDetails.totalUnits}',
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textDim,
            ),
          ),
        ),
      ],
      trailingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallTextButton(
            label: 'Open',
            onTap: onOpenEditor,
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 6),
            SmallIconButton(
              icon: FluentIcons.delete_24_regular,
              tooltip: 'Delete language',
              onTap: onDelete!,
              foreground: tokens.err,
              background: tokens.errBg,
              borderColor: tokens.err.withValues(alpha: 0.3),
            ),
          ],
        ],
      ),
    );
  }

  Color _progressColor(TwmtThemeTokens tokens, double percent) {
    if (percent >= 100) return tokens.ok;
    if (percent >= 50) return tokens.accent;
    if (percent > 0) return tokens.warn;
    return tokens.textFaint;
  }

  (String, Color, Color) _statusAppearance(TwmtThemeTokens tokens, double percent) {
    if (percent >= 100) return ('COMPLETED', tokens.ok, tokens.okBg);
    if (percent > 0) return ('TRANSLATING', tokens.accent, tokens.accentBg);
    return ('PENDING', tokens.textDim, tokens.panel2);
  }
}
