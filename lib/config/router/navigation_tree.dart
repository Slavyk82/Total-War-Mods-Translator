import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

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
  NavGroup('Sources', [
    NavItem(
      label: 'Mods',
      route: '/sources/mods',
      icon: FluentIcons.cube_24_regular,
      selectedIcon: FluentIcons.cube_24_filled,
    ),
    NavItem(
      label: 'Game Files',
      route: '/sources/game-files',
      icon: FluentIcons.globe_24_regular,
      selectedIcon: FluentIcons.globe_24_filled,
    ),
  ]),
  NavGroup('Work', [
    NavItem(
      label: 'Home',
      route: '/work/home',
      icon: FluentIcons.home_24_regular,
      selectedIcon: FluentIcons.home_24_filled,
    ),
    NavItem(
      label: 'Projects',
      route: '/work/projects',
      icon: FluentIcons.folder_24_regular,
      selectedIcon: FluentIcons.folder_24_filled,
    ),
  ]),
  NavGroup('Resources', [
    NavItem(
      label: 'Glossary',
      route: '/resources/glossary',
      icon: FluentIcons.book_24_regular,
      selectedIcon: FluentIcons.book_24_filled,
    ),
    NavItem(
      label: 'Translation Memory',
      route: '/resources/tm',
      icon: FluentIcons.database_24_regular,
      selectedIcon: FluentIcons.database_24_filled,
    ),
  ]),
  NavGroup('Publishing', [
    NavItem(
      label: 'Pack Compilation',
      route: '/publishing/pack',
      icon: FluentIcons.box_multiple_24_regular,
      selectedIcon: FluentIcons.box_multiple_24_filled,
    ),
    NavItem(
      label: 'Steam Workshop',
      route: '/publishing/steam',
      icon: FluentIcons.cloud_arrow_up_24_regular,
      selectedIcon: FluentIcons.cloud_arrow_up_24_filled,
    ),
  ]),
  NavGroup('System', [
    NavItem(
      label: 'Settings',
      route: '/system/settings',
      icon: FluentIcons.settings_24_regular,
      selectedIcon: FluentIcons.settings_24_filled,
    ),
    NavItem(
      label: 'Help',
      route: '/system/help',
      icon: FluentIcons.question_circle_24_regular,
      selectedIcon: FluentIcons.question_circle_24_filled,
    ),
  ]),
];
