import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Titled group of form fields (§7.5).
///
/// Renders an uppercase mono label followed by optional help text and a
/// vertical stack of [children] (gap 10px). Margin-bottom 16.
class FormSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final String? helpText;

  const FormSection({
    super.key,
    required this.label,
    required this.children,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (helpText != null) ...[
            const SizedBox(height: 2),
            Text(
              helpText!,
              key: const Key('form-section-help-text'),
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: tokens.textFaint,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}
