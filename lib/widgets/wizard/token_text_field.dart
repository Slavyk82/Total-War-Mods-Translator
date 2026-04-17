import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Token-themed text field used inside wizard forms (§7.5).
///
/// Panel2 fill, border outline, accent focus, font-body 13px text,
/// text-faint placeholder. Extracted from Workshop Publish private classes
/// so Game Translation / New Project dialogs share the same input style.
class TokenTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  const TokenTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.enabled,
    this.maxLines = 1,
    this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 2 : 1,
      focusNode: focusNode,
      style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: tokens.panel2,
        hintText: hint,
        hintStyle: tokens.fontBody.copyWith(
          fontSize: 13,
          color: tokens.textFaint,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.accent),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide:
              BorderSide(color: tokens.border.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
