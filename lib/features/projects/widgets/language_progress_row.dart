import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Column sizing shared between [LanguageProgressRow] and its header so the
/// project-detail languages list visually matches the projects list archetype
/// (see `ProjectsScreen._projectColumns`).
const List<ListRowColumn> languageProgressColumns = [
  ListRowColumn.flex(1), // language name
  ListRowColumn.fixed(200), // progress bar + %
  ListRowColumn.fixed(150), // last modified
  ListRowColumn.fixed(120), // status pill
];

/// Trailing-action width reserved for [LanguageProgressRow] so fixed columns
/// in the header land at the same x-coordinate as the row content.
const double languageProgressTrailingActionWidth = 36;

/// Single-language row for Project Detail — mirrors the projects-list row
/// layout: progress bar precedes percent with an 8px gap, followed by the
/// last-updated date and a status pill.
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
    final barColor = _progressColor(tokens, percent);
    final (pillLabel, pillFg, pillBg) = _statusAppearance(tokens, percent);
    final updatedAtMs =
        langDetails.projectLanguage.updatedAt * 1000;
    final lastModified = updatedAtMs > 0
        ? DateFormat('dd/MM/yyyy HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(updatedAtMs))
        : '—';

    return ListRow(
      columns: languageProgressColumns,
      onTap: onOpenEditor,
      trailingAction: onDelete == null
          ? null
          : SmallIconButton(
              icon: FluentIcons.delete_24_regular,
              tooltip: 'Delete language',
              onTap: onDelete!,
              foreground: tokens.err,
              background: tokens.errBg,
              borderColor: tokens.err.withValues(alpha: 0.3),
            ),
      children: [
        Text(
          langDetails.language.displayName,
          overflow: TextOverflow.ellipsis,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
            fontWeight: FontWeight.w500,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _ProgressBar(percent: percent, color: barColor),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            lastModified,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: pillLabel,
              foreground: pillFg,
              background: pillBg,
            ),
          ),
        ),
      ],
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

/// Progress cell: bar on the left, percent right-aligned in a fixed 36px gutter,
/// matching the projects-list `_ProgressBar` layout.
class _ProgressBar extends StatelessWidget {
  final double percent;
  final Color color;
  const _ProgressBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final clamped = percent.clamp(0.0, 100.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: tokens.panel),
                  FractionallySizedBox(
                    widthFactor: clamped / 100,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${clamped.toInt()}%',
            textAlign: TextAlign.right,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
