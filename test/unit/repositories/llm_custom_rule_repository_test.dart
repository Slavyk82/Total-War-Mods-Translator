import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/repositories/llm_custom_rule_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late LlmCustomRuleRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = LlmCustomRuleRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('LlmCustomRuleRepository', () {
    // The llm_custom_rules table has CHECK (is_enabled IN (0, 1)) but no
    // created_at <= updated_at constraint. FK to projects is OFF, so we can
    // freely reference project ids that do not exist.
    LlmCustomRule createTestRule({
      String? id,
      String? ruleText,
      bool isEnabled = true,
      int sortOrder = 0,
      String? projectId,
      int? createdAt,
      int? updatedAt,
    }) {
      return LlmCustomRule(
        id: id ?? 'rule-id',
        ruleText: ruleText ?? 'Always translate faction names literally.',
        isEnabled: isEnabled,
        sortOrder: sortOrder,
        projectId: projectId,
        createdAt: createdAt ?? 1000,
        updatedAt: updatedAt ?? 2000,
      );
    }

    group('insert', () {
      test('should insert a rule successfully', () async {
        final rule = createTestRule();

        final result = await repository.insert(rule);

        expect(result.isOk, isTrue);
        expect(result.value, equals(rule));

        final maps =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: [rule.id]);
        expect(maps.length, equals(1));
        expect(maps.first['rule_text'], equals(rule.ruleText));
        expect(maps.first['is_enabled'], equals(1));
      });

      test('should persist project_id when provided', () async {
        final rule = createTestRule(id: 'r-proj', projectId: 'project-42');

        final result = await repository.insert(rule);

        expect(result.isOk, isTrue);
        final maps = await db
            .query('llm_custom_rules', where: 'id = ?', whereArgs: ['r-proj']);
        expect(maps.first['project_id'], equals('project-42'));
      });

      test('should fail when inserting duplicate ID', () async {
        final rule = createTestRule();
        await repository.insert(rule);

        final duplicate = createTestRule(ruleText: 'different text');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when is_enabled violates CHECK constraint is impossible '
          'via model (bool), so persists disabled as 0', () async {
        final rule = createTestRule(id: 'r-disabled', isEnabled: false);

        final result = await repository.insert(rule);

        expect(result.isOk, isTrue);
        final maps = await db
            .query('llm_custom_rules', where: 'id = ?', whereArgs: ['r-disabled']);
        expect(maps.first['is_enabled'], equals(0));
      });
    });

    group('getById', () {
      test('should return rule when found', () async {
        final rule = createTestRule();
        await repository.insert(rule);

        final result = await repository.getById(rule.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(rule.id));
        expect(result.value.ruleText, equals(rule.ruleText));
      });

      test('should return error when rule not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll (delegates to getGlobalRules)', () {
      test('should return empty list when no rules exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only global rules ordered by sort_order ASC', () async {
        await repository.insert(createTestRule(id: 'g1', sortOrder: 2));
        await repository.insert(createTestRule(id: 'g2', sortOrder: 0));
        await repository.insert(createTestRule(id: 'g3', sortOrder: 1));
        // A project rule that must be excluded.
        await repository
            .insert(createTestRule(id: 'p1', projectId: 'proj-a', sortOrder: 0));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('g2'));
        expect(result.value[1].id, equals('g3'));
        expect(result.value[2].id, equals('g1'));
      });
    });

    group('update', () {
      test('should update rule successfully', () async {
        final rule = createTestRule();
        await repository.insert(rule);

        final updated = rule.copyWith(ruleText: 'updated rule', sortOrder: 5);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.ruleText, equals('updated rule'));

        final getResult = await repository.getById(rule.id);
        expect(getResult.value.ruleText, equals('updated rule'));
        expect(getResult.value.sortOrder, equals(5));
      });

      test('should return error when rule not found', () async {
        final rule = createTestRule(id: 'non-existent');

        final result = await repository.update(rule);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete rule successfully', () async {
        final rule = createTestRule();
        await repository.insert(rule);

        final result = await repository.delete(rule.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(rule.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when rule not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getEnabledRules', () {
      test('should return empty list when no enabled global rules exist', () async {
        await repository.insert(createTestRule(id: 'd1', isEnabled: false));

        final result = await repository.getEnabledRules();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only enabled global rules ordered by sort_order', () async {
        await repository.insert(createTestRule(id: 'e1', sortOrder: 1));
        await repository
            .insert(createTestRule(id: 'e2', sortOrder: 0, isEnabled: true));
        await repository
            .insert(createTestRule(id: 'd1', sortOrder: 0, isEnabled: false));
        // Enabled but project-specific -> excluded.
        await repository.insert(
            createTestRule(id: 'p1', projectId: 'proj-a', isEnabled: true));

        final result = await repository.getEnabledRules();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('e2'));
        expect(result.value[1].id, equals('e1'));
      });
    });

    group('getGlobalRules', () {
      test('should return empty list when only project rules exist', () async {
        await repository.insert(createTestRule(id: 'p1', projectId: 'proj-a'));

        final result = await repository.getGlobalRules();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return global rules (enabled and disabled) ordered', () async {
        await repository
            .insert(createTestRule(id: 'g1', sortOrder: 1, isEnabled: false));
        await repository.insert(createTestRule(id: 'g2', sortOrder: 0));

        final result = await repository.getGlobalRules();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('g2'));
        expect(result.value[1].id, equals('g1'));
      });
    });

    group('getRulesForProject', () {
      test('should return empty list when project has no rules', () async {
        await repository.insert(createTestRule(id: 'g1'));

        final result = await repository.getRulesForProject('proj-x');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only rules for the given project, ordered', () async {
        await repository.insert(
            createTestRule(id: 'a1', projectId: 'proj-a', sortOrder: 1));
        await repository.insert(
            createTestRule(id: 'a2', projectId: 'proj-a', sortOrder: 0));
        await repository
            .insert(createTestRule(id: 'b1', projectId: 'proj-b'));
        await repository.insert(createTestRule(id: 'g1'));

        final result = await repository.getRulesForProject('proj-a');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('a2'));
        expect(result.value[1].id, equals('a1'));
      });
    });

    group('getEnabledRulesForProject', () {
      test('should return empty list when project has no enabled rules', () async {
        await repository.insert(createTestRule(
            id: 'a1', projectId: 'proj-a', isEnabled: false));

        final result = await repository.getEnabledRulesForProject('proj-a');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only enabled rules for the project, ordered', () async {
        await repository.insert(createTestRule(
            id: 'a1', projectId: 'proj-a', sortOrder: 1, isEnabled: true));
        await repository.insert(createTestRule(
            id: 'a2', projectId: 'proj-a', sortOrder: 0, isEnabled: true));
        await repository.insert(createTestRule(
            id: 'a3', projectId: 'proj-a', isEnabled: false));
        await repository.insert(createTestRule(
            id: 'b1', projectId: 'proj-b', isEnabled: true));

        final result = await repository.getEnabledRulesForProject('proj-a');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('a2'));
        expect(result.value[1].id, equals('a1'));
      });
    });

    group('getRuleForProject', () {
      test('should return null when project has no rule', () async {
        final result = await repository.getRuleForProject('proj-none');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });

      test('should return the rule when one exists for the project', () async {
        await repository.insert(createTestRule(id: 'a1', projectId: 'proj-a'));

        final result = await repository.getRuleForProject('proj-a');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('a1'));
        expect(result.value!.projectId, equals('proj-a'));
      });
    });

    group('toggleEnabled', () {
      test('should toggle an enabled rule to disabled', () async {
        // created_at far in the past so the bumped updated_at is always larger
        // (and no created_at <= updated_at constraint exists anyway).
        final rule = createTestRule(
            id: 't1', isEnabled: true, createdAt: 1000, updatedAt: 1000);
        await repository.insert(rule);

        final result = await repository.toggleEnabled('t1');

        expect(result.isOk, isTrue);
        expect(result.value.isEnabled, isFalse);

        final maps =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: ['t1']);
        expect(maps.first['is_enabled'], equals(0));
      });

      test('should toggle a disabled rule to enabled and bump updated_at', () async {
        final rule = createTestRule(
            id: 't2', isEnabled: false, createdAt: 1000, updatedAt: 1000);
        await repository.insert(rule);

        final result = await repository.toggleEnabled('t2');

        expect(result.isOk, isTrue);
        expect(result.value.isEnabled, isTrue);
        expect(result.value.updatedAt, greaterThanOrEqualTo(rule.updatedAt));
      });

      test('should return error when rule not found', () async {
        final result = await repository.toggleEnabled('missing');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('reorderRules', () {
      test('should assign sort_order by index for given ids', () async {
        await repository
            .insert(createTestRule(id: 'r1', sortOrder: 9, createdAt: 1000, updatedAt: 1000));
        await repository
            .insert(createTestRule(id: 'r2', sortOrder: 9, createdAt: 1000, updatedAt: 1000));
        await repository
            .insert(createTestRule(id: 'r3', sortOrder: 9, createdAt: 1000, updatedAt: 1000));

        final result = await repository.reorderRules(['r3', 'r1', 'r2']);

        expect(result.isOk, isTrue);

        final r3 =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: ['r3']);
        final r1 =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: ['r1']);
        final r2 =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: ['r2']);
        expect(r3.first['sort_order'], equals(0));
        expect(r1.first['sort_order'], equals(1));
        expect(r2.first['sort_order'], equals(2));
      });

      test('should succeed (no-op) for an empty id list', () async {
        await repository.insert(createTestRule(id: 'r1', sortOrder: 5));

        final result = await repository.reorderRules([]);

        expect(result.isOk, isTrue);
        final r1 =
            await db.query('llm_custom_rules', where: 'id = ?', whereArgs: ['r1']);
        expect(r1.first['sort_order'], equals(5));
      });
    });

    group('getEnabledCount', () {
      test('should return 0 when no enabled global rules', () async {
        await repository.insert(createTestRule(id: 'd1', isEnabled: false));
        await repository
            .insert(createTestRule(id: 'p1', projectId: 'proj-a', isEnabled: true));

        final result = await repository.getEnabledCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should count only enabled global rules', () async {
        await repository.insert(createTestRule(id: 'e1', isEnabled: true));
        await repository.insert(createTestRule(id: 'e2', isEnabled: true));
        await repository.insert(createTestRule(id: 'd1', isEnabled: false));
        await repository
            .insert(createTestRule(id: 'p1', projectId: 'proj-a', isEnabled: true));

        final result = await repository.getEnabledCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });
    });

    group('getTotalCount', () {
      test('should return 0 when no global rules', () async {
        await repository.insert(createTestRule(id: 'p1', projectId: 'proj-a'));

        final result = await repository.getTotalCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should count all global rules (enabled and disabled)', () async {
        await repository.insert(createTestRule(id: 'e1', isEnabled: true));
        await repository.insert(createTestRule(id: 'd1', isEnabled: false));
        await repository
            .insert(createTestRule(id: 'p1', projectId: 'proj-a'));

        final result = await repository.getTotalCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });
    });

    group('getNextSortOrder', () {
      test('should return 0 when no global rules exist', () async {
        // Only a project rule exists -> ignored by the global query.
        await repository.insert(
            createTestRule(id: 'p1', projectId: 'proj-a', sortOrder: 7));

        final result = await repository.getNextSortOrder();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should return max global sort_order + 1', () async {
        await repository.insert(createTestRule(id: 'g1', sortOrder: 3));
        await repository.insert(createTestRule(id: 'g2', sortOrder: 7));
        // Higher sort_order on a project rule must not influence the result.
        await repository.insert(
            createTestRule(id: 'p1', projectId: 'proj-a', sortOrder: 99));

        final result = await repository.getNextSortOrder();

        expect(result.isOk, isTrue);
        expect(result.value, equals(8));
      });
    });

    group('deleteRulesForProject', () {
      test('should return 0 when project has no rules', () async {
        await repository.insert(createTestRule(id: 'g1'));

        final result = await repository.deleteRulesForProject('proj-none');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));

        // Global rule untouched.
        final all = await repository.getGlobalRules();
        expect(all.value.length, equals(1));
      });

      test('should delete all rules for the project and return the count', () async {
        await repository.insert(createTestRule(id: 'a1', projectId: 'proj-a'));
        await repository.insert(createTestRule(id: 'a2', projectId: 'proj-a'));
        await repository.insert(createTestRule(id: 'b1', projectId: 'proj-b'));
        await repository.insert(createTestRule(id: 'g1'));

        final result = await repository.deleteRulesForProject('proj-a');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));

        final remaining = await repository.getRulesForProject('proj-a');
        expect(remaining.value, isEmpty);
        // Other project + global rules survive.
        final projB = await repository.getRulesForProject('proj-b');
        expect(projB.value.length, equals(1));
        final globals = await repository.getGlobalRules();
        expect(globals.value.length, equals(1));
      });
    });

    group('round-trip fromMap/toMap', () {
      test('should preserve all fields through insert and getById', () async {
        final rule = createTestRule(
          id: 'rt1',
          ruleText: 'Keep <tags> intact and unicode 中文 untouched.',
          isEnabled: false,
          sortOrder: 4,
          projectId: 'proj-z',
          createdAt: 1500,
          updatedAt: 1600,
        );

        await repository.insert(rule);
        final result = await repository.getById('rt1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(rule));
      });
    });
  });
}
