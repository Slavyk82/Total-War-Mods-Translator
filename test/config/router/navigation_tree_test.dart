import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/config/router/navigation_tree.dart';

void main() {
  group('navigationTree', () {
    test('has 4 groups in the new order', () {
      expect(navigationTree.map((g) => g.label).toList(),
          ['Workflow', 'Work', 'Resources', 'System']);
    });

    test('Workflow group contains the 4 pipeline steps routed correctly', () {
      final workflow = navigationTree.firstWhere((g) => g.label == 'Workflow');
      expect(workflow.items.map((i) => i.label).toList(),
          ['Detect', 'Translate', 'Compile', 'Publish']);
      expect(workflow.items.map((i) => i.route).toList(), [
        AppRoutes.mods,
        AppRoutes.projects,
        AppRoutes.packCompilation,
        AppRoutes.steamPublish,
      ]);
    });

    test('Work group only contains Home', () {
      final work = navigationTree.firstWhere((g) => g.label == 'Work');
      expect(work.items.map((i) => i.label).toList(), ['Home']);
    });

    test('Resources group contains Glossary, Translation Memory, Game Files',
        () {
      final resources =
          navigationTree.firstWhere((g) => g.label == 'Resources');
      expect(resources.items.map((i) => i.label).toList(),
          ['Glossary', 'Translation Memory', 'Game Files']);
    });

    test('System group keeps Settings and Help', () {
      final system = navigationTree.firstWhere((g) => g.label == 'System');
      expect(system.items.map((i) => i.label).toList(),
          ['Settings', 'Help']);
    });

    test('no group is named Sources or Publishing', () {
      final labels = navigationTree.map((g) => g.label).toSet();
      expect(labels, isNot(contains('Sources')));
      expect(labels, isNot(contains('Publishing')));
    });
  });
}
