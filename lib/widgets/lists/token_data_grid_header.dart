import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Tokenised column header shared by every SfDataGrid in the app
/// (editor, validation review, glossary, translation memory).
///
/// Renders the column label in the theme's monospace face, all-caps, with the
/// faint text colour and wide letter-spacing called out in the mockup. The
/// caller is expected to pass an already-uppercased [text] so the constructor
/// can stay `const`-friendly.
class TokenDataGridHeader extends StatelessWidget {
  final String text;

  const TokenDataGridHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: tokens.fontMono.copyWith(
          fontSize: 10,
          color: tokens.textFaint,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
