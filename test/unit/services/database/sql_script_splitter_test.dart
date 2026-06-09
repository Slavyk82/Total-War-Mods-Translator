import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/database/migration_service.dart';

/// Tests for [MigrationService.splitSqlScriptForTesting] (the BEGIN/END/CASE
/// aware SQL script splitter used to install schema.sql into a database).
///
/// Regression guard for the bug where `CASE ... END` expressions inside a
/// `CREATE VIEW` decremented the BEGIN...END nesting counter below zero, after
/// which no `;` was treated as a terminator and every remaining statement was
/// merged into one giant blob.
void main() {
  group('splitSqlScriptForTesting', () {
    test('splits real schema.sql with v_project_language_stats isolated', () {
      final schema = File('lib/database/schema.sql').readAsStringSync();
      final statements = MigrationService.splitSqlScriptForTesting(schema)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // The stats view (which contains several CASE WHEN ... END) must be its
      // OWN statement, not merged with whatever follows it.
      final viewStatements = statements
          .where((s) => s.contains('CREATE VIEW IF NOT EXISTS v_project_language_stats'))
          .toList();
      expect(viewStatements, hasLength(1),
          reason: 'The stats view must appear in exactly one statement');

      final viewStatement = viewStatements.single;

      // The view statement must not have absorbed the next CREATE VIEW, any
      // triggers, or the seed INSERTs.
      expect(viewStatement.contains('v_translations_needing_review'), isFalse,
          reason: 'Stats view must not be merged with the next view');
      expect(viewStatement.contains('CREATE TRIGGER'), isFalse,
          reason: 'Stats view must not be merged with subsequent triggers');
      expect(viewStatement.contains('INSERT OR IGNORE INTO languages'), isFalse,
          reason: 'Stats view must not be merged with seed INSERTs');

      // A statement AFTER the stats view must appear as its own element.
      final viewIndex = statements.indexOf(viewStatement);
      expect(viewIndex, greaterThanOrEqualTo(0));

      final after = statements.sublist(viewIndex + 1);
      expect(
        after.any((s) => s.contains('CREATE TRIGGER')),
        isTrue,
        reason: 'A CREATE TRIGGER after the stats view must be its own element',
      );
      expect(
        after.any((s) => s.contains('INSERT OR IGNORE INTO languages')),
        isTrue,
        reason: 'A seed INSERT after the stats view must be its own element',
      );

      // Sanity: the second stats view (needing_review) is also isolated.
      expect(
        statements
            .where((s) =>
                s.contains('CREATE VIEW IF NOT EXISTS v_translations_needing_review'))
            .length,
        1,
      );
    });

    test('CREATE VIEW with CASE WHEN END then CREATE TABLE splits into 2', () {
      const script = '''
CREATE VIEW v_demo AS
SELECT
  id,
  COUNT(CASE WHEN status = 'a' THEN 1 END) AS a_count,
  COUNT(CASE WHEN status = 'b' THEN 1 END) AS b_count
FROM things
GROUP BY id;
CREATE TABLE x (id TEXT PRIMARY KEY, name TEXT);
''';

      final statements = MigrationService.splitSqlScriptForTesting(script)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      expect(statements, hasLength(2));
      expect(statements[0], startsWith('CREATE VIEW v_demo'));
      expect(statements[0], contains('CASE WHEN'));
      expect(statements[1], startsWith('CREATE TABLE x'));
    });

    test('CREATE TRIGGER body is kept intact (inner ; does not split)', () {
      const script = '''
CREATE TRIGGER trg_demo AFTER INSERT ON things BEGIN
  INSERT INTO log(msg) VALUES ('inserted');
  UPDATE counters SET n = n + 1 WHERE id = 1;
END;
CREATE TABLE y (id TEXT PRIMARY KEY);
''';

      final statements = MigrationService.splitSqlScriptForTesting(script)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      expect(statements, hasLength(2));
      // The two inner `;` must NOT have split the trigger body.
      expect(statements[0], startsWith('CREATE TRIGGER trg_demo'));
      expect(statements[0], contains("INSERT INTO log"));
      expect(statements[0], contains('UPDATE counters'));
      expect(statements[0], endsWith('END'));
      expect(statements[1], startsWith('CREATE TABLE y'));
    });

    test('CASE inside a trigger body does not break depth tracking', () {
      const script = '''
CREATE TRIGGER trg_case AFTER UPDATE ON things BEGIN
  UPDATE agg SET total = (
    SELECT COUNT(CASE WHEN t.flag = 1 THEN 1 END) FROM things t
  ) WHERE id = NEW.id;
END;
CREATE TABLE z (id TEXT PRIMARY KEY);
''';

      final statements = MigrationService.splitSqlScriptForTesting(script)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      expect(statements, hasLength(2));
      expect(statements[0], startsWith('CREATE TRIGGER trg_case'));
      expect(statements[0], contains('CASE WHEN'));
      expect(statements[0], endsWith('END'));
      expect(statements[1], startsWith('CREATE TABLE z'));
    });
  });
}
