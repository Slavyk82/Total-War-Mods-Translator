import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/repositories/llm_custom_rule_repository.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements LlmCustomRuleRepository {}

LlmCustomRule _rule(
  String id,
  String text, {
  bool enabled = true,
  String? projectId,
}) =>
    LlmCustomRule(
      id: id,
      ruleText: text,
      isEnabled: enabled,
      projectId: projectId,
      createdAt: 0,
      updatedAt: 0,
    );

Ok<T, TWMTDatabaseException> _ok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _err<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() {
    registerFallbackValue(_rule('fallback', 'fallback'));
  });

  late _MockRepo repo;
  late LlmCustomRulesService service;

  setUp(() {
    repo = _MockRepo();
    service = LlmCustomRulesService(repository: repo, logging: FakeLogger());
  });

  group('addRule', () {
    test('rejects empty/whitespace text without touching the repo', () async {
      final r = await service.addRule('   ');
      expect(r.isErr, isTrue);
      verifyNever(() => repo.insert(any()));
    });

    test('inserts a trimmed, enabled rule with the next sort order', () async {
      when(() => repo.getNextSortOrder()).thenAnswer((_) async => _ok(7));
      when(() => repo.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as LlmCustomRule));

      final r = await service.addRule('  keep names  ');

      expect(r.isOk, isTrue);
      final captured =
          verify(() => repo.insert(captureAny())).captured.single as LlmCustomRule;
      expect(captured.ruleText, 'keep names');
      expect(captured.isEnabled, isTrue);
      expect(captured.sortOrder, 7);
    });

    test('falls back to sort order 0 when getNextSortOrder errors', () async {
      when(() => repo.getNextSortOrder()).thenAnswer((_) async => _err<int>('x'));
      when(() => repo.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as LlmCustomRule));

      await service.addRule('rule');

      final captured =
          verify(() => repo.insert(captureAny())).captured.single as LlmCustomRule;
      expect(captured.sortOrder, 0);
    });
  });

  group('updateRule', () {
    test('rejects empty text', () async {
      expect((await service.updateRule('id', '  ')).isErr, isTrue);
    });

    test('updates the existing rule with trimmed text', () async {
      when(() => repo.getById('id')).thenAnswer((_) async => _ok(_rule('id', 'old')));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as LlmCustomRule));

      await service.updateRule('id', '  new text  ');

      final captured =
          verify(() => repo.update(captureAny())).captured.single as LlmCustomRule;
      expect(captured.ruleText, 'new text');
    });

    test('propagates the error when the rule is missing', () async {
      when(() => repo.getById('id'))
          .thenAnswer((_) async => _err<LlmCustomRule>('not found'));

      expect((await service.updateRule('id', 'x')).isErr, isTrue);
      verifyNever(() => repo.update(any()));
    });
  });

  group('setProjectRule', () {
    test('rejects empty text', () async {
      expect((await service.setProjectRule('p', '')).isErr, isTrue);
    });

    test('updates when a project rule already exists', () async {
      when(() => repo.getRuleForProject('p'))
          .thenAnswer((_) async => _ok<LlmCustomRule?>(_rule('r', 'old', projectId: 'p')));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as LlmCustomRule));

      await service.setProjectRule('p', 'fresh');

      verify(() => repo.update(any())).called(1);
      verifyNever(() => repo.insert(any()));
    });

    test('inserts when no project rule exists yet', () async {
      when(() => repo.getRuleForProject('p'))
          .thenAnswer((_) async => _ok<LlmCustomRule?>(null));
      when(() => repo.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as LlmCustomRule));

      await service.setProjectRule('p', 'fresh');

      final captured =
          verify(() => repo.insert(captureAny())).captured.single as LlmCustomRule;
      expect(captured.projectId, 'p');
      expect(captured.ruleText, 'fresh');
    });
  });

  group('project rule helpers', () {
    test('deleteProjectRule maps ok to Ok(null)', () async {
      when(() => repo.deleteRulesForProject('p'))
          .thenAnswer((_) async => _ok(3));

      final r = await service.deleteProjectRule('p');
      expect(r.isOk, isTrue);
    });

    test('toggleProjectRuleEnabled returns null when no rule exists', () async {
      when(() => repo.getRuleForProject('p'))
          .thenAnswer((_) async => _ok<LlmCustomRule?>(null));

      final r = await service.toggleProjectRuleEnabled('p');
      expect(r.unwrap(), isNull);
      verifyNever(() => repo.toggleEnabled(any()));
    });

    test('toggleProjectRuleEnabled toggles an existing rule', () async {
      when(() => repo.getRuleForProject('p'))
          .thenAnswer((_) async => _ok<LlmCustomRule?>(_rule('r', 't', projectId: 'p')));
      when(() => repo.toggleEnabled('r'))
          .thenAnswer((_) async => _ok(_rule('r', 't', enabled: false)));

      final r = await service.toggleProjectRuleEnabled('p');
      expect(r.unwrap()?.isEnabled, isFalse);
    });
  });

  group('prompt building', () {
    test('getCombinedRulesText joins enabled rule texts', () async {
      when(() => repo.getEnabledRules()).thenAnswer(
          (_) async => _ok([_rule('1', 'first'), _rule('2', 'second')]));

      expect(await service.getCombinedRulesText(), 'first\nsecond');
    });

    test('getCombinedRulesText returns empty on error', () async {
      when(() => repo.getEnabledRules())
          .thenAnswer((_) async => _err<List<LlmCustomRule>>('boom'));

      expect(await service.getCombinedRulesText(), '');
    });

    test('getCombinedRulesTextForProject puts global rules before project rules',
        () async {
      when(() => repo.getEnabledRules())
          .thenAnswer((_) async => _ok([_rule('g', 'global')]));
      when(() => repo.getEnabledRulesForProject('p'))
          .thenAnswer((_) async => _ok([_rule('p1', 'project')]));

      expect(
        await service.getCombinedRulesTextForProject('p'),
        'global\nproject',
      );
    });
  });

  group('counts & flags', () {
    test('hasEnabledRules reflects a positive count', () async {
      when(() => repo.getEnabledCount()).thenAnswer((_) async => _ok(2));
      expect(await service.hasEnabledRules(), isTrue);
    });

    test('getEnabledCount returns 0 on error', () async {
      when(() => repo.getEnabledCount())
          .thenAnswer((_) async => _err<int>('boom'));
      expect(await service.getEnabledCount(), 0);
    });

    test('hasEnabledProjectRule is false when the rule is disabled', () async {
      when(() => repo.getRuleForProject('p')).thenAnswer(
          (_) async => _ok<LlmCustomRule?>(_rule('r', 't', enabled: false)));
      expect(await service.hasEnabledProjectRule('p'), isFalse);
    });
  });
}
