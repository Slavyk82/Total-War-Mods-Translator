import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/folders_settings_tab.dart';
import '../widgets/llm_providers_tab.dart';

/// Settings screen with tabbed interface for General and LLM Providers.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FluentScaffold(
      body: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.settings_24_regular,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: theme.textTheme.headlineLarge,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: const _FluentTabBar(
                tabs: [
                  _FluentTab(
                    icon: FluentIcons.settings_24_regular,
                    label: 'General',
                  ),
                  _FluentTab(
                    icon: FluentIcons.folder_24_regular,
                    label: 'Folders',
                  ),
                  _FluentTab(
                    icon: FluentIcons.brain_circuit_24_regular,
                    label: 'LLM Providers',
                  ),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  GeneralSettingsTab(),
                  FoldersSettingsTab(),
                  LlmProvidersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fluent Design tab bar without Material ripple effects.
class _FluentTabBar extends StatelessWidget {
  final List<Widget> tabs;

  const _FluentTabBar({
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TabBar(
      isScrollable: true,
      labelPadding: EdgeInsets.zero,
      indicator: const BoxDecoration(),
      dividerColor: Colors.transparent,
      labelColor: isDark ? const Color(0xFFE1E1E1) : const Color(0xFF323130),
      unselectedLabelColor:
          isDark ? const Color(0xFFA19F9D) : const Color(0xFF605E5C),
      tabs: tabs,
    );
  }
}

/// Fluent Design tab with hover states.
class _FluentTab extends StatefulWidget {
  final IconData icon;
  final String label;

  const _FluentTab({
    required this.icon,
    required this.label,
  });

  @override
  State<_FluentTab> createState() => _FluentTabState();
}

class _FluentTabState extends State<_FluentTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use Tab widget which handles selection state internally
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
                ? theme.colorScheme.surface.withValues(alpha: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}
