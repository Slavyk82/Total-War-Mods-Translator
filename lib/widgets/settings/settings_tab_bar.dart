import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Descriptor for a tab inside [SettingsTabBar].
class SettingsTabItem {
  const SettingsTabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Tokenised tab bar used by Settings screen.
class SettingsTabBar extends StatelessWidget {
  const SettingsTabBar({super.key, required this.tabs});

  final List<SettingsTabItem> tabs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabBar(
      isScrollable: true,
      labelPadding: EdgeInsets.zero,
      indicator: const BoxDecoration(),
      dividerColor: Colors.transparent,
      labelColor: tokens.text,
      unselectedLabelColor: tokens.textDim,
      tabs: [
        for (final item in tabs) _SettingsTab(icon: item.icon, label: item.label),
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tab(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? tokens.panel2.withValues(alpha: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16),
              const SizedBox(width: 8),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}
