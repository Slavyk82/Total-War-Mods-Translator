import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Section header rendered above the [LlmModelsList] card.
///
/// Renders the bold "Models" label (or any caller-supplied [title]) used to
/// introduce the provider's model checkbox group. Visuals are driven entirely
/// by [context.tokens] so theme swaps recolour automatically.
class LlmProviderHeader extends StatelessWidget {
  /// Title rendered as a bold 14px body label. Defaults to "Models" to match
  /// the historical layout.
  final String title;

  const LlmProviderHeader({
    super.key,
    this.title = 'Models',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      title,
      style: tokens.fontBody.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: tokens.text,
      ),
    );
  }
}
