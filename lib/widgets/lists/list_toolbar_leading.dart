import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Leading cluster for a list-screen `FilterToolbar`.
///
/// Renders the canonical "icon + title + count label" row shared by all
/// Plan 5a list screens (Projects / Mods / Steam Publish / Glossary /
/// Translation Memory). Optional [trailing] widgets follow the count with a
/// 16px gap.
class ListToolbarLeading extends StatelessWidget {
  /// Leading icon rendered at 20px in [TwmtThemeTokens.textMid].
  final IconData icon;

  /// Screen title rendered with [TwmtThemeTokens.fontDisplay] at 20px.
  final String title;

  /// Count/summary label rendered with [TwmtThemeTokens.fontMono] at 12px.
  final String countLabel;

  /// Optional trailing widgets appended after the count with a 16px gap.
  final List<Widget> trailing;

  const ListToolbarLeading({
    super.key,
    required this.icon,
    required this.title,
    required this.countLabel,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Icon(icon, size: 20, color: tokens.textMid),
        const SizedBox(width: 10),
        Text(
          title,
          style: tokens.fontDisplay.copyWith(
            fontSize: 20,
            color: tokens.text,
            fontStyle: tokens.fontDisplayStyle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          countLabel,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: 16),
          ...trailing,
        ],
      ],
    );
  }
}
