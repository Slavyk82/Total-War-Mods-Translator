import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/config/router/navigation_tree.dart';

void main() {
  group('navigationTree', () {
    test('has 4 groups in the new order (first is uncategorised)', () {
      expect(navigationTree.map((g) => g.label).toList(),
          ['', 'Workflow', 'Tools', 'System']);
    });

    test('uncategorised top group has Home only', () {
      final top = navigationTree.first;
      expect(top.label, '');
      expect(top.items.map((i) => i.label).toList(), ['Home']);
      expect(top.items.map((i) => i.route).toList(), [AppRoutes.home]);
    });

    test('Workflow group contains the 3 pipeline steps routed correctly', () {
      final workflow = navigationTree.firstWhere((g) => g.label == 'Workflow');
      expect(workflow.items.map((i) => i.label).toList(),
          ['Detect', 'Translate', 'Publish']);
      expect(workflow.items.map((i) => i.route).toList(), [
        AppRoutes.mods,
        AppRoutes.projects,
        AppRoutes.steamPublish,
      ]);
    });

    test(
        'Tools group contains Glossary, Translation Memory, Game Files, '
        'Compile', () {
      final tools =
          navigationTree.firstWhere((g) => g.label == 'Tools');
      expect(tools.items.map((i) => i.label).toList(),
          ['Glossary', 'Translation Memory', 'Game Files', 'Compile']);
      expect(tools.items.last.route, AppRoutes.packCompilation);
    });

    test('System group keeps Settings only', () {
      final system = navigationTree.firstWhere((g) => g.label == 'System');
      expect(system.items.map((i) => i.label).toList(), ['Settings']);
    });

    test('no group is named Sources, Work or Publishing', () {
      final labels = navigationTree.map((g) => g.label).toSet();
      expect(labels, isNot(contains('Sources')));
      expect(labels, isNot(contains('Work')));
      expect(labels, isNot(contains('Publishing')));
    });
  });
}
