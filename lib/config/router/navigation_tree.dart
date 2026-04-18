import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

import 'app_router.dart';

/// Immutable group of sidebar nav items.
class NavGroup {
  const NavGroup(this.label, this.items);

  final String label;
  final List<NavItem> items;
}

/// Immutable sidebar nav item.
class NavItem {
  const NavItem({
    required this.label,
    required this.route,
    required this.icon,
    required this.selectedIcon,
  });

  /// Display label (English, EN-only per parent spec §11).
  final String label;

  /// Absolute route path this item navigates to (use [AppRoutes] constants).
  final String route;

  /// Outline icon for the inactive state.
  final IconData icon;

  /// Filled icon for the active state.
  final IconData selectedIcon;
}

/// Single source of truth for the sidebar structure and breadcrumb label
/// resolution. Mutating this list is a user-facing change — update spec first.
const List<NavGroup> navigationTree = [
  NavGroup('Workflow', [
    NavItem(
      label: 'Detect',
      route: AppRoutes.mods,
      icon: FluentIcons.cube_24_regular,
      selectedIcon: FluentIcons.cube_24_filled,
    ),
    NavItem(
      label: 'Translate',
      route: AppRoutes.projects,
      icon: FluentIcons.folder_24_regular,
      selectedIcon: FluentIcons.folder_24_filled,
    ),
    NavItem(
      label: 'Compile',
      route: AppRoutes.packCompilation,
      icon: FluentIcons.box_multiple_24_regular,
      selectedIcon: FluentIcons.box_multiple_24_filled,
    ),
    NavItem(
      label: 'Publish',
      route: AppRoutes.steamPublish,
      icon: FluentIcons.cloud_arrow_up_24_regular,
      selectedIcon: FluentIcons.cloud_arrow_up_24_filled,
    ),
  ]),
  NavGroup('Work', [
    NavItem(
      label: 'Home',
      route: AppRoutes.home,
      icon: FluentIcons.home_24_regular,
      selectedIcon: FluentIcons.home_24_filled,
    ),
  ]),
  NavGroup('Resources', [
    NavItem(
      label: 'Glossary',
      route: AppRoutes.glossary,
      icon: FluentIcons.book_24_regular,
      selectedIcon: FluentIcons.book_24_filled,
    ),
    NavItem(
      label: 'Translation Memory',
      route: AppRoutes.translationMemory,
      icon: FluentIcons.database_24_regular,
      selectedIcon: FluentIcons.database_24_filled,
    ),
    NavItem(
      label: 'Game Files',
      route: AppRoutes.gameFiles,
      icon: FluentIcons.globe_24_regular,
      selectedIcon: FluentIcons.globe_24_filled,
    ),
  ]),
  NavGroup('System', [
    NavItem(
      label: 'Settings',
      route: AppRoutes.settings,
      icon: FluentIcons.settings_24_regular,
      selectedIcon: FluentIcons.settings_24_filled,
    ),
    NavItem(
      label: 'Help',
      route: AppRoutes.help,
      icon: FluentIcons.question_circle_24_regular,
      selectedIcon: FluentIcons.question_circle_24_filled,
    ),
  ]),
];
