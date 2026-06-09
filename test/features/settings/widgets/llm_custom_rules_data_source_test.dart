import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/llm_custom_rules_data_source.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

LlmCustomRule _rule(String id, String text, {bool enabled = true}) =>
    LlmCustomRule(
      id: id,
      ruleText: text,
      isEnabled: enabled,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  testWidgets(
    'toggling the second of two identical-text rows targets the correct id',
    (tester) async {
      LlmCustomRule? toggled;
      final rules = [
        _rule('id-1', 'Same rule text'),
        _rule('id-2', 'Same rule text'), // duplicate ruleText, distinct id
      ];

      final source = LlmCustomRulesDataSource(
        rules: rules,
        tokens: slateTokens,
        onEdit: (_) {},
        onDelete: (_) {},
        onToggleEnabled: (r) => toggled = r,
      );

      // Sanity: both rows carry their own model in the 'actions' cell.
      expect(source.rows[0].getCells()[2].value, rules[0]);
      expect(source.rows[1].getCells()[2].value, rules[1]);

      // Tap the enabled cell of the SECOND row.
      final adapter = source.buildRow(source.rows[1]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: adapter.cells.first)),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(toggled, isNotNull);
      expect(toggled!.id, 'id-2',
          reason: 'Must resolve by carried model, not by non-unique ruleText');
    },
  );

  testWidgets('toggling the first row targets the first id', (tester) async {
    LlmCustomRule? toggled;
    final rules = [
      _rule('id-1', 'Same rule text'),
      _rule('id-2', 'Same rule text'),
    ];

    final source = LlmCustomRulesDataSource(
      rules: rules,
      tokens: slateTokens,
      onEdit: (_) {},
      onDelete: (_) {},
      onToggleEnabled: (r) => toggled = r,
    );

    final adapter = source.buildRow(source.rows[0]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: adapter.cells.first))),
    );
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(toggled?.id, 'id-1');
  });
}
