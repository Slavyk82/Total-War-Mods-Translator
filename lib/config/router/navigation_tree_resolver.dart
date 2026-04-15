import 'navigation_tree.dart';

/// Result of a tree lookup for the current route path.
class NavigationActive {
  const NavigationActive(this.group, this.item);
  final NavGroup? group;
  final NavItem? item;
}

/// Pure helpers for navigation label/active-state resolution.
/// Shared between sidebar highlight and breadcrumb label lookup.
class NavigationTreeResolver {
  const NavigationTreeResolver._();

  /// Returns the active group and item for the given URL [path], using
  /// longest-prefix `startsWith` matching across every item in [navigationTree].
  ///
  /// Returns [NavigationActive] with null fields when nothing matches.
  static NavigationActive findActive(String path) {
    if (path.isEmpty) {
      return const NavigationActive(null, null);
    }

    NavGroup? bestGroup;
    NavItem? bestItem;
    int bestLength = -1;

    for (final group in navigationTree) {
      for (final item in group.items) {
        final route = item.route;
        final matches = path == route || path.startsWith('$route/');
        if (matches && route.length > bestLength) {
          bestLength = route.length;
          bestGroup = group;
          bestItem = item;
        }
      }
    }

    return NavigationActive(bestGroup, bestItem);
  }

  /// Returns the display label for a single URL [segment], or `null` if the
  /// segment is unknown (dynamic id, unsupported leaf, etc.). Used by the
  /// breadcrumb to render static segments.
  static String? labelForSegment(String segment) {
    return _segmentLabels[segment];
  }
}

const Map<String, String> _segmentLabels = {
  // Group segments
  'sources': 'Sources',
  'work': 'Work',
  'resources': 'Resources',
  'publishing': 'Publishing',
  'system': 'System',
  // Item segments
  'mods': 'Mods',
  'game-files': 'Game Files',
  'home': 'Home',
  'projects': 'Projects',
  'glossary': 'Glossary',
  'tm': 'Translation Memory',
  'pack': 'Pack Compilation',
  'steam': 'Steam Workshop',
  'settings': 'Settings',
  'help': 'Help',
  // Leaf segments
  'editor': 'Editor',
  'single': 'Single',
  'batch': 'Batch',
  'batch-export': 'Batch Export',
};
