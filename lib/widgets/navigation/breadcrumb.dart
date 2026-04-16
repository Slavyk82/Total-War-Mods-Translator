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
/// A non-last crumb is clickable only when its accumulated path resolves to a
/// valid target — either a group default item (`/work` → `/work/home`) or an
/// exact [NavItem.route]. Intermediate leaves whose accumulated path is not a
/// real route (e.g. `/work/projects/<uuid>/editor`) render as plain text.
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
              // A crumb is visually "last" only when its own accumulated URL
              // prefix equals the current URL. When the URL has trailing
              // dynamic segments (UUIDs, language ids) that were skipped
              // during render, the visibly-last crumb is still considered
              // non-last so it remains clickable (e.g. "Projects" in a
              // project detail URL navigates back to the projects list).
              isLast: crumbs[i].accumulatedPath == path,
              onTap: (crumbs[i].accumulatedPath == path ||
                      crumbs[i].path == null)
                  ? null
                  : () => tap(context, crumbs[i].path!),
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
      final accumulated = accum.toString();
      crumbs.add(_Crumb(
        accumulatedPath: accumulated,
        path: _resolveClickablePath(accumulated, segment),
        label: label ?? segment,
        isKnown: label != null,
      ));
    }
    return crumbs;
  }

  /// Resolves the clickable target for a crumb, or `null` when the crumb
  /// should render as non-interactive text.
  String? _resolveClickablePath(String accumulatedPath, String segment) {
    // Group-level: /work → /work/home, /sources → /sources/mods, etc.
    final groupTarget =
        NavigationTreeResolver.defaultRouteForGroupSegment(segment);
    if (groupTarget != null) return groupTarget;

    // Item-level: /work/projects resolves to the item /work/projects.
    final active = NavigationTreeResolver.findActive(accumulatedPath);
    if (active.item?.route == accumulatedPath) return accumulatedPath;

    // Intermediate / invalid path → not clickable.
    return null;
  }
}

class _Crumb {
  const _Crumb({
    required this.accumulatedPath,
    required this.path,
    required this.label,
    required this.isKnown,
  });

  /// The crumb's own URL prefix (segments joined up to this point). Used to
  /// determine whether the crumb is the visually-last one (matches the full
  /// current URL).
  final String accumulatedPath;

  /// Clickable navigation target, or `null` when the crumb is not clickable
  /// (intermediate leaf whose accumulated path is not a real route).
  final String? path;
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
      // Non-clickable: either the last crumb or an intermediate non-item
      // segment. Render plain text with no hover/cursor feedback.
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
