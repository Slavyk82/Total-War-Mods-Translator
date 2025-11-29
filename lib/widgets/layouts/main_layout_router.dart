import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'fluent_scaffold.dart';
import '../navigation_sidebar_router.dart';
import '../fluent/fluent_widgets.dart';
import '../../config/router/app_router.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../features/pack_compilation/providers/pack_compilation_providers.dart';

/// Router-aware main layout with breadcrumbs and keyboard shortcuts
///
/// This layout wraps all main screens via ShellRoute and provides:
/// - Navigation sidebar with route-aware selection
/// - Breadcrumb navigation for nested routes
/// - Keyboard shortcuts (Ctrl+1-7 for main screens)
/// - Fluent Design styling
/// - Navigation blocking during active translations
class MainLayoutRouter extends ConsumerWidget {
  final Widget child;

  const MainLayoutRouter({
    super.key,
    required this.child,
  });

  /// Check if navigation is allowed and show warning if blocked
  bool _canNavigate(BuildContext context, WidgetRef ref) {
    final isTranslating = ref.read(translationInProgressProvider);
    if (isTranslating) {
      FluentToast.warning(
        context,
        'Translation in progress. Stop the translation first.',
      );
      return false;
    }

    final isCompiling = ref.read(compilationInProgressProvider);
    if (isCompiling) {
      FluentToast.warning(
        context,
        'Pack generation in progress. Stop the generation first.',
      );
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () {
          if (_canNavigate(context, ref)) context.goHome();
        },
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () {
          if (_canNavigate(context, ref)) context.goMods();
        },
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () {
          if (_canNavigate(context, ref)) context.goProjects();
        },
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () {
          if (_canNavigate(context, ref)) context.goGlossary();
        },
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () {
          if (_canNavigate(context, ref)) context.goTranslationMemory();
        },
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () {
          if (_canNavigate(context, ref)) context.goSettings();
        },
        const SingleActivator(LogicalKeyboardKey.home, control: true): () {
          if (_canNavigate(context, ref)) context.goHome();
        },
      },
      child: Focus(
        autofocus: true,
        child: FluentScaffold(
          body: Column(
            children: [
              // Breadcrumbs
              _buildBreadcrumbs(context, ref),

              // Main content with sidebar
              Expanded(
                child: Row(
                  children: [
                    NavigationSidebarRouter(
                      onNavigate: (path) {
                        if (_canNavigate(context, ref)) {
                          context.go(path);
                        }
                      },
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final breadcrumbs = _generateBreadcrumbs(location);

    // Don't show breadcrumbs for top-level routes
    if (breadcrumbs.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Home button
          _BreadcrumbItem(
            icon: FluentIcons.home_24_regular,
            label: 'Home',
            isFirst: true,
            onTap: () {
              if (_canNavigate(context, ref)) context.goHome();
            },
          ),

          // Breadcrumb trail
          ...breadcrumbs.asMap().entries.map((entry) {
            final index = entry.key;
            final breadcrumb = entry.value;
            final isLast = index == breadcrumbs.length - 1;

            return Row(
              children: [
                Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                _BreadcrumbItem(
                  label: breadcrumb.label,
                  isLast: isLast,
                  onTap: isLast ? null : () {
                    if (_canNavigate(context, ref)) context.go(breadcrumb.path);
                  },
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  List<_Breadcrumb> _generateBreadcrumbs(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final breadcrumbs = <_Breadcrumb>[];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final segmentPath = '/${segments.sublist(0, i + 1).join('/')}';

      // Skip IDs in breadcrumbs (they're just noise)
      if (_isUuid(segment)) {
        continue;
      }

      final label = _formatBreadcrumbLabel(segment);
      breadcrumbs.add(_Breadcrumb(label: label, path: segmentPath));
    }

    return breadcrumbs;
  }

  String _formatBreadcrumbLabel(String segment) {
    // Convert kebab-case or snake_case to Title Case
    return segment
        .split(RegExp(r'[-_]'))
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  bool _isUuid(String value) {
    // Simple UUID detection (8-4-4-4-12 hex pattern)
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidPattern.hasMatch(value);
  }
}

class _Breadcrumb {
  final String label;
  final String path;

  _Breadcrumb({required this.label, required this.path});
}

class _BreadcrumbItem extends StatefulWidget {
  final IconData? icon;
  final String label;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const _BreadcrumbItem({
    this.icon,
    required this.label,
    this.isFirst = false,
    this.isLast = false,
    this.onTap,
  });

  @override
  State<_BreadcrumbItem> createState() => _BreadcrumbItemState();
}

class _BreadcrumbItemState extends State<_BreadcrumbItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClickable = widget.onTap != null;

    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: widget.isLast
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: widget.isLast ? FontWeight.w600 : FontWeight.normal,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
        ],
        Text(widget.label, style: textStyle),
      ],
    );

    if (!isClickable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
