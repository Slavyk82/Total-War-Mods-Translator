import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Label + child pair used inside wizard forms (§7.5).
///
/// Renders a token-themed body-font label above an arbitrary [child] widget
/// (typically a [TokenTextField], dropdown, or other input). Keeps the label
/// typography consistent across dialogs, Workshop Publish screens, and
/// Pack Compilation editor.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
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
        child,
      ],
    );
  }
}
