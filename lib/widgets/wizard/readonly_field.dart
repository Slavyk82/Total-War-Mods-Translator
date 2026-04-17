import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Token-themed read-only value box used inside wizard forms (§7.5).
///
/// Label via body-font, value via mono-font on a panel2 container with
/// border. Renders em-dash when [value] is empty. Extracted from Workshop
/// Publish private classes so Game Translation / New Project dialogs share
/// the same read-only style.
class ReadonlyField extends StatelessWidget {
  final String label;
  final String value;

  const ReadonlyField({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            value.isEmpty ? '—' : value,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textMid,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
