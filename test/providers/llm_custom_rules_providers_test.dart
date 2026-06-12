import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/providers/llm_custom_rules_providers.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';

class _MockService extends Mock implements LlmCustomRulesService {}

LlmCustomRule _rule({
  String id = 'r1',
  String ruleText = 'be concise',
  bool isEnabled = true,
  int sortOrder = 0,
  String? projectId,
}) {
  return LlmCustomRule(
    id: id,
    ruleText: ruleText,
    isEnabled: isEnabled,
    sortOrder: sortOrder,
    projectId: projectId,
    createdAt: 0,
    updatedAt: 0,
  );
}

/// Permissive stubs so every notifier `build()` can complete without a
/// MissingStubError. Individual tests override the specific method they assert.
void _stubReads(_MockService service) {
  when(() => service.getAllRules())
      .thenAnswer((_) async => const Ok(<LlmCustomRule>[]));
  when(() => service.getEnabledCount()).thenAnswer((_) async => 0);
  when(() => service.hasEnabledRules()).thenAnswer((_) async => false);
  when(() => service.getRuleForProject(any()))
      .thenAnswer((_) async => const Ok<LlmCustomRule?, TWMTDatabaseException>(null));
  when(() => service.hasEnabledProjectRule(any()))
      .thenAnswer((_) async => false);
}

void main() {
  late _MockService service;
  late ProviderContainer container;

  setUp(() {
    service = _MockService();
    _stubReads(service);
    container = ProviderContainer(overrides: [
      // The codegen `llmCustomRulesServiceProvider` (in the providers file) is
      // the single dependency of every provider/notifier under test. Overriding
      // it with a mock service replaces the whole bridge -> GetIt graph.
      llmCustomRulesServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
  });

  // --------------------------------------------------------------------------
  // llmCustomRulesServiceProvider (the bridge provider itself)
  // --------------------------------------------------------------------------
  group('llmCustomRulesServiceProvider', () {
    test('can be overridden with a mock service', () {
      expect(container.read(llmCustomRulesServiceProvider), same(service));
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.build()
  // --------------------------------------------------------------------------
  group('LlmCustomRules build()', () {
    test('returns the rules from the service (Ok)', () async {
      final rules = [_rule(id: 'a'), _rule(id: 'b', sortOrder: 1)];
      when(() => service.getAllRules()).thenAnswer((_) async => Ok(rules));

      final result = await container.read(llmCustomRulesProvider.future);

      expect(result, rules);
      verify(() => service.getAllRules()).called(1);
    });

    test('returns an empty list when the service errors (Err)', () async {
      when(() => service.getAllRules())
          .thenAnswer((_) async => Err(TWMTDatabaseException('boom')));

      final result = await container.read(llmCustomRulesProvider.future);

      expect(result, isEmpty);
    });

    test('returns an empty list when the service has no rules', () async {
      final result = await container.read(llmCustomRulesProvider.future);
      expect(result, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.addRule()
  // --------------------------------------------------------------------------
  group('LlmCustomRules addRule()', () {
    test('Ok returns (true, null) and invalidates the derived providers',
        () async {
      var count = 0;
      when(() => service.getEnabledCount()).thenAnswer((_) async => count);
      when(() => service.hasEnabledRules()).thenAnswer((_) async => count > 0);
      when(() => service.addRule(any())).thenAnswer((_) async {
        count++;
        return Ok(_rule());
      });

      // Prime the derived caches.
      expect(await container.read(enabledRulesCountProvider.future), 0);
      expect(await container.read(hasEnabledRulesProvider.future), isFalse);

      final (ok, err) =
          await container.read(llmCustomRulesProvider.notifier).addRule('hi');

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.addRule('hi')).called(1);

      // Derived providers were invalidated => recomputed with the new count.
      expect(await container.read(enabledRulesCountProvider.future), 1);
      expect(await container.read(hasEnabledRulesProvider.future), isTrue);
    });

    test('Err returns (false, message) and does not invalidate', () async {
      when(() => service.addRule(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('text empty')));

      final (ok, err) =
          await container.read(llmCustomRulesProvider.notifier).addRule('');

      expect(ok, isFalse);
      expect(err, 'text empty');
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.updateRule()
  // --------------------------------------------------------------------------
  group('LlmCustomRules updateRule()', () {
    test('Ok returns (true, null) and forwards id + text', () async {
      when(() => service.updateRule(any(), any()))
          .thenAnswer((_) async => Ok(_rule(ruleText: 'new')));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .updateRule('r1', 'new');

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.updateRule('r1', 'new')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.updateRule(any(), any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('not found')));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .updateRule('missing', 'x');

      expect(ok, isFalse);
      expect(err, 'not found');
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.deleteRule()
  // --------------------------------------------------------------------------
  group('LlmCustomRules deleteRule()', () {
    test('Ok returns (true, null) and forwards id', () async {
      when(() => service.deleteRule(any()))
          .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .deleteRule('r1');

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.deleteRule('r1')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.deleteRule(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('delete failed')));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .deleteRule('r1');

      expect(ok, isFalse);
      expect(err, 'delete failed');
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.toggleEnabled()
  // --------------------------------------------------------------------------
  group('LlmCustomRules toggleEnabled()', () {
    test('Ok returns (true, null) and forwards id', () async {
      when(() => service.toggleEnabled(any()))
          .thenAnswer((_) async => Ok(_rule(isEnabled: false)));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .toggleEnabled('r1');

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.toggleEnabled('r1')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.toggleEnabled(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('toggle failed')));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .toggleEnabled('r1');

      expect(ok, isFalse);
      expect(err, 'toggle failed');
    });
  });

  // --------------------------------------------------------------------------
  // LlmCustomRules.reorderRules()
  // --------------------------------------------------------------------------
  group('LlmCustomRules reorderRules()', () {
    test('Ok returns (true, null) and forwards the id list', () async {
      when(() => service.reorderRules(any()))
          .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .reorderRules(['b', 'a']);

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.reorderRules(['b', 'a'])).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.reorderRules(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('reorder failed')));

      final (ok, err) = await container
          .read(llmCustomRulesProvider.notifier)
          .reorderRules(['a']);

      expect(ok, isFalse);
      expect(err, 'reorder failed');
    });
  });

  // --------------------------------------------------------------------------
  // enabledRulesCountProvider
  // --------------------------------------------------------------------------
  group('enabledRulesCountProvider', () {
    test('exposes the count returned by the service', () async {
      when(() => service.getEnabledCount()).thenAnswer((_) async => 7);
      expect(await container.read(enabledRulesCountProvider.future), 7);
      verify(() => service.getEnabledCount()).called(1);
    });

    test('exposes zero by default', () async {
      expect(await container.read(enabledRulesCountProvider.future), 0);
    });
  });

  // --------------------------------------------------------------------------
  // hasEnabledRulesProvider
  // --------------------------------------------------------------------------
  group('hasEnabledRulesProvider', () {
    test('true when the service reports enabled rules', () async {
      when(() => service.hasEnabledRules()).thenAnswer((_) async => true);
      expect(await container.read(hasEnabledRulesProvider.future), isTrue);
      verify(() => service.hasEnabledRules()).called(1);
    });

    test('false when the service reports none', () async {
      expect(await container.read(hasEnabledRulesProvider.future), isFalse);
    });
  });

  // --------------------------------------------------------------------------
  // ProjectCustomRuleNotifier.build()
  // --------------------------------------------------------------------------
  group('ProjectCustomRuleNotifier build()', () {
    test('returns the project rule (Ok)', () async {
      final rule = _rule(id: 'p1', projectId: 'proj-1');
      when(() => service.getRuleForProject('proj-1'))
          .thenAnswer((_) async => Ok(rule));

      final result =
          await container.read(projectCustomRuleProvider('proj-1').future);

      expect(result, rule);
      verify(() => service.getRuleForProject('proj-1')).called(1);
    });

    test('returns null when no rule exists (Ok null)', () async {
      final result =
          await container.read(projectCustomRuleProvider('proj-1').future);
      expect(result, isNull);
    });

    test('returns null when the service errors (Err)', () async {
      when(() => service.getRuleForProject('proj-1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('boom')));

      final result =
          await container.read(projectCustomRuleProvider('proj-1').future);
      expect(result, isNull);
    });
  });

  // --------------------------------------------------------------------------
  // ProjectCustomRuleNotifier.setRule()
  // --------------------------------------------------------------------------
  group('ProjectCustomRuleNotifier setRule()', () {
    test('Ok returns (true, null) and forwards projectId + text', () async {
      when(() => service.setProjectRule(any(), any()))
          .thenAnswer((_) async => Ok(_rule(projectId: 'proj-1')));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .setRule('do this');

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.setProjectRule('proj-1', 'do this')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.setProjectRule(any(), any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('set failed')));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .setRule('x');

      expect(ok, isFalse);
      expect(err, 'set failed');
    });
  });

  // --------------------------------------------------------------------------
  // ProjectCustomRuleNotifier.deleteRule()
  // --------------------------------------------------------------------------
  group('ProjectCustomRuleNotifier deleteRule()', () {
    test('Ok returns (true, null) and forwards projectId', () async {
      when(() => service.deleteProjectRule(any()))
          .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .deleteRule();

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.deleteProjectRule('proj-1')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.deleteProjectRule(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('del failed')));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .deleteRule();

      expect(ok, isFalse);
      expect(err, 'del failed');
    });
  });

  // --------------------------------------------------------------------------
  // ProjectCustomRuleNotifier.toggleEnabled()
  // --------------------------------------------------------------------------
  group('ProjectCustomRuleNotifier toggleEnabled()', () {
    test('Ok returns (true, null) and forwards projectId', () async {
      when(() => service.toggleProjectRuleEnabled(any())).thenAnswer(
          (_) async => Ok(_rule(projectId: 'proj-1', isEnabled: false)));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .toggleEnabled();

      expect(ok, isTrue);
      expect(err, isNull);
      verify(() => service.toggleProjectRuleEnabled('proj-1')).called(1);
    });

    test('Err returns (false, message)', () async {
      when(() => service.toggleProjectRuleEnabled(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('toggle failed')));

      final (ok, err) = await container
          .read(projectCustomRuleProvider('proj-1').notifier)
          .toggleEnabled();

      expect(ok, isFalse);
      expect(err, 'toggle failed');
    });
  });

  // --------------------------------------------------------------------------
  // hasProjectRuleProvider
  // --------------------------------------------------------------------------
  group('hasProjectRuleProvider', () {
    test('true when the service reports an enabled project rule', () async {
      when(() => service.hasEnabledProjectRule('proj-1'))
          .thenAnswer((_) async => true);

      expect(await container.read(hasProjectRuleProvider('proj-1').future),
          isTrue);
      verify(() => service.hasEnabledProjectRule('proj-1')).called(1);
    });

    test('false when the service reports none', () async {
      expect(await container.read(hasProjectRuleProvider('proj-1').future),
          isFalse);
    });
  });
}
