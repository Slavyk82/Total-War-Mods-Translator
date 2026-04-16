import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Base rectangular card primitive that derives its decoration exclusively
/// from [TwmtThemeTokens] via `context.tokens`.
///
/// Every default (`backgroundColor`, `borderColor`, `radius`) resolves from
/// the active theme tokens so the card re-themes automatically when the app
/// switches between Atelier and Forge. Callers can override any slot for
/// highlight or status variants (e.g. accent background on the "needs review"
/// action card).
class TokenCard extends StatelessWidget {
  /// Content rendered inside the padded container.
  final Widget child;

  /// Inner padding around [child]. Defaults to the spec's 18 px all-around.
  final EdgeInsetsGeometry padding;

  /// Optional override for the card fill. Falls back to `tokens.panel2`.
  final Color? backgroundColor;

  /// Optional override for the border stroke. Falls back to `tokens.border`.
  final Color? borderColor;

  /// Optional override for the corner radius. Falls back to `tokens.radiusLg`.
  final double? radius;

  const TokenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.backgroundColor,
    this.borderColor,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: const Key('TokenCardContainer'),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? tokens.panel2,
        border: Border.all(color: borderColor ?? tokens.border),
        borderRadius: BorderRadius.circular(radius ?? tokens.radiusLg),
      ),
      child: child,
    );
  }
}
