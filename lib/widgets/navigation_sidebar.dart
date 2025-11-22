import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/theme_provider.dart';
import 'package:twmt/widgets/fluent/fluent_toggle_switch.dart';

class NavigationSidebar extends ConsumerWidget {
  const NavigationSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavigationItem(
                  context: context,
                  index: 0,
                  icon: FluentIcons.cube_24_regular,
                  selectedIcon: FluentIcons.cube_24_filled,
                  label: 'Mods',
                ),
                _buildNavigationItem(
                  context: context,
                  index: 1,
                  icon: FluentIcons.folder_24_regular,
                  selectedIcon: FluentIcons.folder_24_filled,
                  label: 'Projects',
                ),
                const Divider(height: 24),
                _buildNavigationItem(
                  context: context,
                  index: 2,
                  icon: FluentIcons.settings_24_regular,
                  selectedIcon: FluentIcons.settings_24_filled,
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeProvider);
    final isDark = themeModeAsync.maybeWhen(
      data: (mode) => mode == ThemeMode.dark,
      orElse: () => false,
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.translate_24_filled,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'TWMT',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Icon(
            isDark ? FluentIcons.weather_moon_24_regular : FluentIcons.weather_sunny_24_regular,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          FluentToggleSwitch(
            key: const ValueKey('theme_switch'),
            value: isDark,
            onChanged: (value) => ref.read(themeProvider.notifier).toggleTheme(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = selectedIndex == index;
    final theme = Theme.of(context);

    return _FluentNavigationItem(
      isSelected: isSelected,
      theme: theme,
      icon: icon,
      selectedIcon: selectedIcon,
      label: label,
      onTap: () => onItemSelected(index),
    );
  }
}

class _FluentNavigationItem extends StatefulWidget {
  const _FluentNavigationItem({
    required this.isSelected,
    required this.theme,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool isSelected;
  final ThemeData theme;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FluentNavigationItem> createState() => _FluentNavigationItemState();
}

class _FluentNavigationItemState extends State<_FluentNavigationItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = widget.theme.colorScheme.primary.withValues(alpha: 0.1);
    } else if (_isPressed) {
      backgroundColor = widget.theme.colorScheme.primary.withValues(alpha: 0.05);
    } else if (_isHovered) {
      backgroundColor = widget.theme.colorScheme.primary.withValues(alpha: 0.08);
    } else {
      backgroundColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isSelected ? widget.selectedIcon : widget.icon,
                  size: 20,
                  color: widget.isSelected
                      ? widget.theme.colorScheme.primary
                      : widget.theme.iconTheme.color,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: widget.theme.textTheme.bodyLarge?.copyWith(
                    color: widget.isSelected
                        ? widget.theme.colorScheme.primary
                        : widget.theme.textTheme.bodyLarge?.color,
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
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
