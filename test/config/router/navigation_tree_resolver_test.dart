import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/navigation_tree.dart';
import 'package:twmt/config/router/navigation_tree_resolver.dart';

void main() {
  group('NavigationTreeResolver.findActive', () {
    test('exact top-level match resolves to its item and group', () {
      final result = NavigationTreeResolver.findActive('/sources/mods');
      expect(result.group?.label, 'Sources');
      expect(result.item?.label, 'Mods');
    });

    test('sub-route resolves to parent item (longest-prefix match)', () {
      final result = NavigationTreeResolver.findActive(
        '/work/projects/abc-123/editor/fr-FR',
      );
      expect(result.group?.label, 'Work');
      expect(result.item?.label, 'Projects');
    });

    test('unknown path returns null group and item', () {
      final result = NavigationTreeResolver.findActive('/nowhere');
      expect(result.group, isNull);
      expect(result.item, isNull);
    });

    test('empty path returns null', () {
      final result = NavigationTreeResolver.findActive('');
      expect(result.group, isNull);
      expect(result.item, isNull);
    });

    test('every item in the tree is findable by its exact route', () {
      for (final group in navigationTree) {
        for (final item in group.items) {
          final result = NavigationTreeResolver.findActive(item.route);
          expect(result.item?.label, item.label,
              reason: 'route=${item.route}');
          expect(result.group?.label, group.label,
              reason: 'route=${item.route}');
        }
      }
    });
  });

  group('NavigationTreeResolver.labelForSegment', () {
    test('group segments resolve to group labels', () {
      expect(NavigationTreeResolver.labelForSegment('sources'), 'Sources');
      expect(NavigationTreeResolver.labelForSegment('work'), 'Work');
      expect(NavigationTreeResolver.labelForSegment('resources'), 'Resources');
      expect(NavigationTreeResolver.labelForSegment('publishing'), 'Publishing');
      expect(NavigationTreeResolver.labelForSegment('system'), 'System');
    });

    test('item segments resolve to item labels', () {
      expect(NavigationTreeResolver.labelForSegment('mods'), 'Mods');
      expect(NavigationTreeResolver.labelForSegment('game-files'), 'Game Files');
      expect(NavigationTreeResolver.labelForSegment('projects'), 'Projects');
      expect(NavigationTreeResolver.labelForSegment('home'), 'Home');
      expect(NavigationTreeResolver.labelForSegment('glossary'), 'Glossary');
      expect(NavigationTreeResolver.labelForSegment('tm'), 'Translation Memory');
      expect(NavigationTreeResolver.labelForSegment('pack'), 'Pack Compilation');
      expect(NavigationTreeResolver.labelForSegment('steam'), 'Steam Workshop');
      expect(NavigationTreeResolver.labelForSegment('settings'), 'Settings');
      expect(NavigationTreeResolver.labelForSegment('help'), 'Help');
    });

    test('leaf segments resolve to their labels', () {
      expect(NavigationTreeResolver.labelForSegment('editor'), 'Editor');
      expect(NavigationTreeResolver.labelForSegment('single'), 'Single');
      expect(NavigationTreeResolver.labelForSegment('batch'), 'Batch');
      expect(NavigationTreeResolver.labelForSegment('batch-export'), 'Batch Export');
    });

    test('unknown segment returns null', () {
      expect(NavigationTreeResolver.labelForSegment('unknown'), isNull);
      expect(NavigationTreeResolver.labelForSegment(''), isNull);
    });
  });
}
