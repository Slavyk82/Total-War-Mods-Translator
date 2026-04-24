import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Right-hand bulk-actions side panel of the Projects screen.
///
/// Width matches the translation editor's inspector panel default (320 px).
/// Body is intentionally empty for now — future bulk actions will be wired in
/// here.
class ProjectsBulkMenuPanel extends StatelessWidget {
  const ProjectsBulkMenuPanel({super.key});

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
    );
  }
}
