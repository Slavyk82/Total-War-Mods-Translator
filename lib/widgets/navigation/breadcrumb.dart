import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_tree_resolver.dart';
import '../../theme/twmt_theme_tokens.dart';

/// Reusable breadcrumb widget driven by the current [GoRouter] path.
///
/// Segments are resolved via [NavigationTreeResolver.labelForSegment]. UUID
/// segments (e.g. project ids) are skipped. Unknown non-UUID segments fall
/// back to the raw segment text in a muted mono style.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({super.key});

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final crumbs = _buildCrumbs(path);
    if (crumbs.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;

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
            ),
          ],
        ],
      ),
    );
  }

  List<_Crumb> _buildCrumbs(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <_Crumb>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (_uuidPattern.hasMatch(segment)) continue;
      final label = NavigationTreeResolver.labelForSegment(segment);
      crumbs.add(_Crumb(
        label: label ?? segment,
        isKnown: label != null,
      ));
    }
    return crumbs;
  }
}

class _Crumb {
  const _Crumb({
    required this.label,
    required this.isKnown,
  });

  final String label;
  final bool isKnown;
}

class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({required this.crumb, required this.isLast});

  final _Crumb crumb;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final baseStyle = crumb.isKnown
        ? tokens.fontBody
        : tokens.fontMono; // unknown segments render in mono for signal
    final style = baseStyle.copyWith(
      fontSize: 13,
      color: isLast
          ? tokens.text
          : (crumb.isKnown ? tokens.textMid : tokens.textDim),
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(crumb.label, style: style),
    );
  }
}
