import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_guard.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../lists/small_icon_button.dart';
import 'crumb_segment.dart';

/// Detail-screen top toolbar (§7.2 / §7.5).
///
/// 48px fixed height with a back button, a crumb trail, and optional trailing
/// widgets. The crumb trail renders each [CrumbSegment]: the first and last
/// segments are plain text (last in bold, marking the current screen); any
/// middle segment with a non-null `route` is clickable and navigates via
/// [GoRouter] after passing the [canNavigateNow] guard.
class DetailScreenToolbar extends ConsumerWidget {
  final List<CrumbSegment> crumbs;
  final VoidCallback onBack;
  final List<Widget> trailing;

  const DetailScreenToolbar({
    super.key,
    required this.crumbs,
    required this.onBack,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SmallIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(child: _CrumbTrail(crumbs: crumbs)),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            ...trailing,
          ],
        ],
      ),
    );
  }
}

class _CrumbTrail extends ConsumerWidget {
  final List<CrumbSegment> crumbs;
  const _CrumbTrail({required this.crumbs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final baseStyle = tokens.fontMono.copyWith(
      fontSize: 12,
      color: tokens.textDim,
      letterSpacing: 0.5,
    );
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('›', style: baseStyle.copyWith(color: tokens.textFaint)),
    );

    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      if (i > 0) children.add(sep);
      final s = crumbs[i];
      final isFirst = i == 0;
      final isLast = i == crumbs.length - 1;
      children.add(_CrumbLabel(
        segment: s,
        isFirst: isFirst,
        isLast: isLast,
        baseStyle: baseStyle,
        currentStyle: baseStyle.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w600,
        ),
        onTap: (isFirst || isLast || s.route == null)
            ? null
            : () {
                if (canNavigateNow(context, ref)) {
                  context.go(s.route!);
                }
              },
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _CrumbLabel extends StatefulWidget {
  final CrumbSegment segment;
  final bool isFirst;
  final bool isLast;
  final TextStyle baseStyle;
  final TextStyle currentStyle;
  final VoidCallback? onTap;

  const _CrumbLabel({
    required this.segment,
    required this.isFirst,
    required this.isLast,
    required this.baseStyle,
    required this.currentStyle,
    required this.onTap,
  });

  @override
  State<_CrumbLabel> createState() => _CrumbLabelState();
}

class _CrumbLabelState extends State<_CrumbLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null;
    final style = widget.isLast ? widget.currentStyle : widget.baseStyle;
    final effective = clickable && _hovered
        ? style.copyWith(decoration: TextDecoration.underline)
        : style;

    final label = Text(
      widget.segment.label,
      style: effective,
      overflow: TextOverflow.ellipsis,
    );

    if (!clickable) return label;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: label,
      ),
    );
  }
}
