import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_tree.dart';
import '../../config/router/navigation_tree_resolver.dart';
import '../../providers/theme_name_provider.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../game_selector_dropdown.dart';
import '../sidebar_update_checker.dart';

/// Five-group sidebar. Reads the current [GoRouter] path to highlight the
/// active item (longest-prefix match). Pass [onNavigate] to intercept taps
/// (e.g. to block navigation during in-progress translations).
class NavigationSidebar extends ConsumerWidget {
  const NavigationSidebar({super.key, this.onNavigate});

  /// Callback invoked with the target route on tap. If null, the widget
  /// defaults to `context.go(route)`.
  final void Function(String route)? onNavigate;

  /// Widget key attached to the currently-active item, for tests.
  static const Key activeItemKey = ValueKey('nav-sidebar-active-item');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final active = NavigationTreeResolver.findActive(path);
    final tokens = context.tokens;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandHeader(),
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: GameSelectorDropdown(),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < navigationTree.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _GroupHeader(label: navigationTree[i].label),
                  for (final item in navigationTree[i].items)
                    _NavItemTile(
                      item: item,
                      isActive: active.item?.route == item.route,
                      onTap: () => _dispatch(context, item.route),
                    ),
                ],
              ],
            ),
          ),
          const SidebarUpdateChecker(),
        ],
      ),
    );
  }

  void _dispatch(BuildContext context, String route) {
    if (onNavigate != null) {
      onNavigate!(route);
    } else {
      context.go(route);
    }
  }
}

class _BrandHeader extends ConsumerWidget {
  const _BrandHeader();

  // Fixed brand colour, theme-independent. Warm antique gold that evokes
  // the Total War visual identity and reads on both Atelier and Forge.
  static const Color _brandColor = Color(0xFFC9A96E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNameAsync = ref.watch(themeNameProvider);
    final themeName =
        themeNameAsync.value ?? TwmtThemeName.atelier;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL WAR',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                      height: 1.05,
                      color: _brandColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mods Translator',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.8,
                      height: 1.1,
                      color: _brandColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ThemeNameButton(
            themeName: themeName,
            onPressed: () =>
                ref.read(themeNameProvider.notifier).cycleTheme(),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        label,
        style: tokens.fontMono.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: tokens.textDim,
        ),
      ),
    );
  }
}

class _NavItemTile extends StatefulWidget {
  const _NavItemTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavItemTile> createState() => _NavItemTileState();
}

class _NavItemTileState extends State<_NavItemTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = widget.isActive
        ? tokens.accentBg
        : (_hover ? tokens.panel2 : Colors.transparent);
    final fg = widget.isActive ? tokens.accent : tokens.text;

    return Padding(
      key: widget.isActive ? NavigationSidebar.activeItemKey : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: widget.isActive
                  ? Border(left: BorderSide(color: tokens.accent, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.isActive ? widget.item.selectedIcon : widget.item.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      color: fg,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeNameButton extends StatefulWidget {
  const _ThemeNameButton({required this.themeName, required this.onPressed});

  final TwmtThemeName themeName;
  final VoidCallback onPressed;

  @override
  State<_ThemeNameButton> createState() => _ThemeNameButtonState();
}

class _ThemeNameButtonState extends State<_ThemeNameButton> {
  bool _hover = false;

  // Fixed theme-switch icon and colour, identical on every palette.
  static const IconData _icon = FluentIcons.color_24_regular;
  static const Color _iconColor = Color(0xFFC9A96E);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: 'Theme: ${widget.themeName.name} (click to cycle)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hover ? tokens.panel2 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(_icon, size: 18, color: _iconColor),
          ),
        ),
      ),
    );
  }
}
