import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/settings/providers/llm_custom_rules_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';

class _MockService extends Mock implements LlmCustomRulesService {}

/// Regression test: LlmCustomRules mutations only called ref.invalidateSelf().
/// enabledRulesCountProvider / hasEnabledRulesProvider do NOT watch the
/// notifier, so the accordion's "active count" badge stayed stale after an
/// add/delete/toggle. Mutations must invalidate the derived providers too.
void main() {
  late _MockService service;
  late ProviderContainer container;
  late int enabledCount;

  const rule = LlmCustomRule(
    id: 'r1',
    ruleText: 'be concise',
    isEnabled: true,
    sortOrder: 0,
    createdAt: 0,
    updatedAt: 0,
  );

  setUp(() {
    service = _MockService();
    enabledCount = 0;

    when(() => service.getAllRules())
        .thenAnswer((_) async => const Ok(<LlmCustomRule>[]));
    when(() => service.getEnabledCount()).thenAnswer((_) async => enabledCount);
    when(() => service.hasEnabledRules())
        .thenAnswer((_) async => enabledCount > 0);
    when(() => service.addRule(any())).thenAnswer((_) async {
      enabledCount++;
      return const Ok(rule);
    });

    container = ProviderContainer(overrides: [
      llmCustomRulesServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
  });

  test('adding a rule refreshes enabledRulesCountProvider (no stale badge)',
      () async {
    expect(await container.read(enabledRulesCountProvider.future), 0);

    final (ok, _) =
        await container.read(llmCustomRulesProvider.notifier).addRule('x');
    expect(ok, isTrue);

    expect(
      await container.read(enabledRulesCountProvider.future),
      1,
      reason: 'the count provider must be invalidated after a mutation, '
          'otherwise the accordion active-count badge stays stale',
    );
  });
}
