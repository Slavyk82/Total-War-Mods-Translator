import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Sticky right column for §7.5 wizard screens.
///
/// Mirrors [StickyFormPanel]'s visual treatment (fixed width, themed
/// background, hairline divider) but attaches to the right edge — divider
/// on the left — and takes an arbitrary list of [children] instead of the
/// form-specific sections/summary/actions slots. Children are laid out in
/// a full-height [Column] so callers can include [Expanded] children that
/// stretch to fill the remaining vertical space.
class RightStickyPanel extends StatelessWidget {
  final List<Widget> children;
  final double width;
  final EdgeInsetsGeometry padding;

  const RightStickyPanel({
    super.key,
    required this.children,
    this.width = 380,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(left: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
