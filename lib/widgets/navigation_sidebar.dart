import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/app_version_provider.dart';
import 'package:twmt/providers/theme_provider.dart';

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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Consumer(
              builder: (context, ref, child) {
                final versionAsync = ref.watch(appVersionProvider);
                return Text(
                  versionAsync.when(
                    data: (version) => 'v$version',
                    loading: () => '',
                    error: (error, stack) => '',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeProvider);
    final themeMode = themeModeAsync.maybeWhen(
      data: (mode) => mode,
      orElse: () => ThemeMode.system,
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Image.asset(
            'assets/twmt_icon.png',
            width: 32,
            height: 32,
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
          _ThemeModeButton(
            themeMode: themeMode,
            onPressed: () => ref.read(themeProvider.notifier).cycleTheme(),
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

/// Button that displays and cycles through theme modes (system, light, dark)
class _ThemeModeButton extends StatefulWidget {
  const _ThemeModeButton({
    required this.themeMode,
    required this.onPressed,
  });

  final ThemeMode themeMode;
  final VoidCallback onPressed;

  @override
  State<_ThemeModeButton> createState() => _ThemeModeButtonState();
}

class _ThemeModeButtonState extends State<_ThemeModeButton> {
  bool _isHovered = false;

  IconData _getIcon() {
    switch (widget.themeMode) {
      case ThemeMode.system:
        return FluentIcons.desktop_24_regular;
      case ThemeMode.light:
        return FluentIcons.weather_sunny_24_regular;
      case ThemeMode.dark:
        return FluentIcons.weather_moon_24_regular;
    }
  }

  String _getTooltip() {
    switch (widget.themeMode) {
      case ThemeMode.system:
        return 'Theme: System (click to change)';
      case ThemeMode.light:
        return 'Theme: Light (click to change)';
      case ThemeMode.dark:
        return 'Theme: Dark (click to change)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: _getTooltip(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _getIcon(),
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
