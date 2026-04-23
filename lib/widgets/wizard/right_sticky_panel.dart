import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Sticky right column for §7.5 wizard screens.
///
/// Mirrors [StickyFormPanel]'s visual treatment (fixed width, themed
/// background, hairline divider) but attaches to the right edge — divider
/// on the left — and takes an arbitrary list of [children] instead of the
/// form-specific sections/summary/actions slots. Intended for advisory or
/// companion content (e.g. conflict analysis) shown alongside the wizard's
/// dynamic zone.
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
