import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_tree_resolver.dart';
import '../../theme/twmt_theme_tokens.dart';

/// Reusable breadcrumb widget driven by the current [GoRouter] path.
///
/// Segments are resolved via [NavigationTreeResolver.labelForSegment]. UUID
/// segments (e.g. project ids) are skipped when rendered but included in the
/// accumulated path so a parent crumb can navigate to the correct sub-route.
/// Unknown non-UUID segments fall back to the raw segment text in a muted mono
/// style.
///
/// Non-last crumbs are clickable and navigate to their accumulated path via
/// [onCrumbTap] (defaults to `context.go`). The last crumb is plain text.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({super.key, this.onCrumbTap});

  /// Override for testing. Default navigates via `context.go(path)`.
  final void Function(BuildContext context, String path)? onCrumbTap;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static void _defaultNavigate(BuildContext context, String path) =>
      context.go(path);

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final crumbs = _buildCrumbs(path);
    if (crumbs.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    final tap = onCrumbTap ?? _defaultNavigate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 14,
                  color: tokens.textDim,
                ),
              ),
            _BreadcrumbSegment(
              crumb: crumbs[i],
              isLast: i == crumbs.length - 1,
              onTap: i == crumbs.length - 1
                  ? null
                  : () => tap(context, crumbs[i].path),
            ),
          ],
        ],
      ),
    );
  }

  List<_Crumb> _buildCrumbs(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <_Crumb>[];
    final accum = StringBuffer();
    for (final segment in segments) {
      accum.write('/');
      accum.write(segment);
      // UUIDs are not rendered as crumbs but are included in the accumulated
      // path so an ancestor crumb can resolve to a valid sub-route.
      if (_uuidPattern.hasMatch(segment)) continue;
      final label = NavigationTreeResolver.labelForSegment(segment);
      crumbs.add(_Crumb(
        path: accum.toString(),
        label: label ?? segment,
        isKnown: label != null,
      ));
    }
    return crumbs;
  }
}

class _Crumb {
  const _Crumb({
    required this.path,
    required this.label,
    required this.isKnown,
  });

  final String path;
  final String label;
  final bool isKnown;
}

class _BreadcrumbSegment extends StatefulWidget {
  const _BreadcrumbSegment({
    required this.crumb,
    required this.isLast,
    this.onTap,
  });

  final _Crumb crumb;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  State<_BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<_BreadcrumbSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final baseStyle = widget.crumb.isKnown
        ? tokens.fontBody
        : tokens.fontMono; // unknown segments render in mono for signal
    final Color color;
    if (widget.isLast) {
      color = tokens.text;
    } else if (_hovered && widget.onTap != null) {
      // Subtle hover state: brighten to `text` on hover for clickable crumbs.
      color = tokens.text;
    } else {
      color = widget.crumb.isKnown ? tokens.textMid : tokens.textDim;
    }
    final style = baseStyle.copyWith(
      fontSize: 13,
      color: color,
      fontWeight: widget.isLast ? FontWeight.w600 : FontWeight.w400,
    );
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(widget.crumb.label, style: style),
    );
    if (widget.onTap == null) {
      return text;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: text,
      ),
    );
  }
}
