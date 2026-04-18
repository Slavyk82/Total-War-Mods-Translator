import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Token-themed text field used inside wizard forms (§7.5).
///
/// Panel2 fill, border outline, accent focus, font-body 13px text,
/// text-faint placeholder. Extracted from Workshop Publish private classes
/// so Game Translation / New Project dialogs share the same input style.
///
/// Plan 5f · Task 1: extended with [obscureText], [autofocus], [maxLength]
/// and [prefixIcon] so masked/API-key and icon-prefixed inputs across
/// Settings and dialogs share the same token styling.
class TokenTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool obscureText;
  final bool autofocus;
  final int? maxLength;
  final Widget? prefixIcon;

  const TokenTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.enabled,
    this.maxLines = 1,
    this.onChanged,
    this.focusNode,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLength,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      // obscureText requires maxLines == 1 (Flutter asserts this).
      maxLines: obscureText ? 1 : maxLines,
      minLines: (!obscureText && maxLines > 1) ? 2 : 1,
      focusNode: focusNode,
      obscureText: obscureText,
      autofocus: autofocus,
      maxLength: maxLength,
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
        prefixIcon: prefixIcon,
        // Suppress the default counter below the field when maxLength is set.
        counterText: maxLength != null ? '' : null,
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
