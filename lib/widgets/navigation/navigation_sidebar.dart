import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/i18n/strings.g.dart';

import '../../config/router/navigation_tree.dart';
import '../../config/router/navigation_tree_resolver.dart';
import '../../providers/theme_name_provider.dart';
import '../../theme/tokens/atelier_tokens.dart';
import '../../theme/tokens/forge_tokens.dart';
import '../../theme/tokens/shogun_tokens.dart';
import '../../theme/tokens/slate_tokens.dart';
import '../../theme/tokens/vellum_tokens.dart';
import '../../theme/tokens/warpstone_tokens.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../game_selector_dropdown.dart';
import '../sidebar_update_checker.dart';
import '../workflow/pipeline_timeline.dart';

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
                  if (navigationTree[i].label.isNotEmpty)
                    _GroupHeader(label: navigationTree[i].label),
                  if (navigationTree[i].label == 'Workflow')
                    ..._buildWorkflowCards(context, navigationTree[i], active)
                  else
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
          const _ThemeSelector(),
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

  /// Builds the Workflow group as a stack of cards threaded by a continuous
  /// vertical timeline rail on the left, with a numbered waypoint badge at
  /// each step — same pattern used by the translation editor's inner
  /// sidebar. The currently-active step's badge fills solid accent; its
  /// siblings render outlined.
  List<Widget> _buildWorkflowCards(
    BuildContext context,
    NavGroup group,
    NavigationActive active,
  ) {
    final widgets = <Widget>[];
    final lastStep = group.items.length - 1;
    for (var step = 0; step < group.items.length; step++) {
      final item = group.items[step];
      final isActive = active.item?.route == item.route;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: pipelineRow(
            key: isActive ? NavigationSidebar.activeItemKey : null,
            rail: TimelineRail(
              step: step + 1,
              primary: isActive,
              lineAbove: step > 0,
              lineBelow: step < lastStep,
            ),
            child: _WorkflowStepCard(
              item: item,
              isActive: isActive,
              onTap: () => _dispatch(context, item.route),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  // Fixed brand colour, theme-independent. Warm antique gold that evokes
  // the Total War visual identity and reads on both Atelier and Forge.
  static const Color _brandColor = Color(0xFFC9A96E);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SizedBox(
        width: double.infinity,
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
                      fontWeight: widget.isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
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

/// Card-style tile for the Workflow pipeline. Renders the item icon and
/// label inside a bordered container; the step number and connecting line
/// are painted by the sibling [TimelineRail] in [pipelineRow].
class _WorkflowStepCard extends StatefulWidget {
  const _WorkflowStepCard({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_WorkflowStepCard> createState() => _WorkflowStepCardState();
}

class _WorkflowStepCardState extends State<_WorkflowStepCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final active = widget.isActive;
    final hovered = _hover;

    final borderColor = active
        ? tokens.accent
        : (hovered ? tokens.accent.withValues(alpha: 0.5) : tokens.border);
    final bg = active
        ? tokens.accentBg
        : (hovered ? tokens.panel2 : tokens.panel);
    final fg = active ? tokens.accent : tokens.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: borderColor, width: active ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  active ? widget.item.selectedIcon : widget.item.icon,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
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

/// Dropdown selector for the active palette, rendered at the foot of the
/// sidebar. Shows the same swatch preview used by the Appearance settings
/// tab, paired with the theme label.
class _ThemeSelector extends ConsumerStatefulWidget {
  const _ThemeSelector();

  @override
  ConsumerState<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends ConsumerState<_ThemeSelector> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final themeNameAsync = ref.watch(themeNameProvider);
    final active = themeNameAsync.value ?? TwmtThemeName.atelier;
    final activeTokens = _tokensFor(active);
    final activeLabel = _labelFor(active);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              t.widgets.navigationSidebar.themeSwitcher,
              style: tokens.fontMono.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: tokens.textDim,
              ),
            ),
          ),
          PopupMenuButton<TwmtThemeName>(
            tooltip: t.widgets.navigationSidebar.selectTheme,
            initialValue: active,
            position: PopupMenuPosition.over,
            color: tokens.panel2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              side: BorderSide(color: tokens.border),
            ),
            onSelected: (name) =>
                ref.read(themeNameProvider.notifier).setThemeName(name),
            itemBuilder: (context) => [
              for (final name in TwmtThemeName.values)
                PopupMenuItem<TwmtThemeName>(
                  value: name,
                  child: _ThemeMenuEntry(
                    label: _labelFor(name),
                    tokens: _tokensFor(name),
                    isSelected: name == active,
                  ),
                ),
            ],
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _hover ? tokens.panel2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    _ThemeSwatch(tokens: activeTokens),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activeLabel,
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: tokens.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      FluentIcons.chevron_up_down_24_regular,
                      size: 14,
                      color: tokens.textDim,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TwmtThemeTokens _tokensFor(TwmtThemeName name) => switch (name) {
    TwmtThemeName.atelier => atelierTokens,
    TwmtThemeName.forge => forgeTokens,
    TwmtThemeName.slate => slateTokens,
    TwmtThemeName.vellum => vellumTokens,
    TwmtThemeName.warpstone => warpstoneTokens,
    TwmtThemeName.shogun => shogunTokens,
  };

  static String _labelFor(TwmtThemeName name) => switch (name) {
    TwmtThemeName.atelier => 'Atelier',
    TwmtThemeName.forge => 'Forge',
    TwmtThemeName.slate => 'Slate',
    TwmtThemeName.vellum => 'Vellum',
    TwmtThemeName.warpstone => 'Warpstone',
    TwmtThemeName.shogun => 'Shogun',
  };
}

class _ThemeMenuEntry extends StatelessWidget {
  const _ThemeMenuEntry({
    required this.label,
    required this.tokens,
    required this.isSelected,
  });

  final String label;
  final TwmtThemeTokens tokens;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final active = context.tokens;
    return Row(
      children: [
        _ThemeSwatch(tokens: tokens),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: active.fontBody.copyWith(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? active.accent : active.text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isSelected)
          Icon(
            FluentIcons.checkmark_24_regular,
            size: 14,
            color: active.accent,
          ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.tokens});

  final TwmtThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final active = context.tokens;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(active.radiusSm),
        border: Border.all(color: active.border, width: 1),
        gradient: LinearGradient(
          colors: [tokens.bg, tokens.bg, tokens.accent, tokens.accent],
          stops: const [0.0, 0.5, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
