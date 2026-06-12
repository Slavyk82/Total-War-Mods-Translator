import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/settings/widgets/llm_custom_rules_datagrid.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/providers/llm_custom_rules_providers.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _FakeLlmRules extends LlmCustomRules {
  _FakeLlmRules(this._build);

  final Future<List<LlmCustomRule>> Function() _build;

  @override
  Future<List<LlmCustomRule>> build() => _build();
}

LlmCustomRule _rule(String text) => LlmCustomRule(
      id: 'id-$text',
      ruleText: text,
      isEnabled: true,
      createdAt: 0,
      updatedAt: 0,
    );

Future<void> _pump(
  WidgetTester tester,
  Future<List<LlmCustomRule>> Function() build,
) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        llmCustomRulesProvider.overrideWith(() => _FakeLlmRules(build)),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(body: LlmCustomRulesDataGrid()),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while loading', (tester) async {
    final never = Completer<List<LlmCustomRule>>();
    await _pump(tester, () => never.future);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error state when loading fails', (tester) async {
    await _pump(tester, () async => throw Exception('boom'));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.customRules.grid.errorTitle), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no rules', (tester) async {
    await _pump(tester, () async => <LlmCustomRule>[]);
    await tester.pumpAndSettle();

    expect(find.text(t.settings.customRules.grid.emptyTitle), findsOneWidget);
  });

  testWidgets('renders the grid with column headers when rules exist',
      (tester) async {
    await _pump(tester, () async => [_rule('keep names'), _rule('formal tone')]);
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.text(t.settings.customRules.grid.columnRuleText), findsOneWidget);
  });
}
