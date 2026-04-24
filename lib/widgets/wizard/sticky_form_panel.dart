import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

/// Sticky left column for §7.5 wizard screens.
///
/// Renders a fixed-width panel (default 380) containing [sections] at top,
/// an optional [summary] in the middle, stacked [actions] below, and an
/// optional [extras] widget anchored at the bottom.
///
/// When [extras] is provided, it fills all remaining vertical space and
/// stays pinned to the bottom regardless of how many sections or actions
/// are stacked above it. Without [extras], the panel behaves as a
/// single scroll view.
class StickyFormPanel extends StatelessWidget {
  final List<Widget> sections;
  final SummaryBox? summary;
  final List<Widget> actions;
  final Widget? extras;
  final double width;
  final EdgeInsetsGeometry padding;

  const StickyFormPanel({
    super.key,
    required this.sections,
    this.summary,
    this.actions = const [],
    this.extras,
    this.width = 380,
    this.padding = const EdgeInsets.all(24),
  });

  List<Widget> _topChildren() {
    return [
      ...sections,
      if (summary != null) ...[
        const SizedBox(height: 8),
        summary!,
      ],
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          actions[i],
        ],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Widget content = extras == null
        ? SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _topChildren(),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._topChildren(),
              const SizedBox(height: 16),
              Expanded(child: extras!),
            ],
          );

    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(right: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: padding,
          child: content,
        ),
      ),
    );
  }
}
