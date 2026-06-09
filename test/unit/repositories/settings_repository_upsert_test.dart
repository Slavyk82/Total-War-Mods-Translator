import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/setting.dart';
import 'package:twmt/repositories/settings_repository.dart';

import '../../helpers/test_database.dart';

/// Tests for the atomic upsert behavior of [SettingsRepository.setValue].
///
/// `setValue` must be a single, atomic INSERT ... ON CONFLICT(key) DO UPDATE
/// so that concurrent calls for the same new key cannot both INSERT and
/// violate the UNIQUE(key) constraint.
void main() {
  late Database db;
  late SettingsRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = SettingsRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('SettingsRepository.setValue upsert', () {
    test('inserts a new key', () async {
      final result = await repository.setValue(
        'upsert.new',
        'first',
        SettingValueType.string,
      );

      expect(result.isOk, isTrue);
      expect(result.value.key, equals('upsert.new'));
      expect(result.value.value, equals('first'));
      expect(result.value.id, isNotEmpty);

      // Exactly one row in the database for the key.
      final maps = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['upsert.new'],
      );
      expect(maps.length, equals(1));
      expect(maps.first['value'], equals('first'));
      expect(maps.first['value_type'], equals('string'));
    });

    test('updates an existing key without a UNIQUE failure', () async {
      final first = await repository.setValue(
        'upsert.existing',
        'value1',
        SettingValueType.string,
      );
      expect(first.isOk, isTrue);
      final firstId = first.value.id;

      final second = await repository.setValue(
        'upsert.existing',
        'value2',
        SettingValueType.integer,
      );

      expect(second.isOk, isTrue);
      expect(second.value.value, equals('value2'));
      expect(second.value.valueType, equals(SettingValueType.integer));
      // The row id is preserved across the update (no new row created).
      expect(second.value.id, equals(firstId));

      // Still exactly one row.
      final maps = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['upsert.existing'],
      );
      expect(maps.length, equals(1));
      expect(maps.first['value'], equals('value2'));
      expect(maps.first['value_type'], equals('integer'));
    });

    test('two concurrent setValue calls for the same new key both succeed',
        () async {
      final results = await Future.wait([
        repository.setValue('upsert.race', 'A', SettingValueType.string),
        repository.setValue('upsert.race', 'B', SettingValueType.string),
      ]);

      // Neither call fails with a UNIQUE constraint violation.
      expect(results[0].isOk, isTrue);
      expect(results[1].isOk, isTrue);

      // Exactly one row persisted, value is one of the two writes.
      final maps = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['upsert.race'],
      );
      expect(maps.length, equals(1));
      expect(maps.first['value'], anyOf(equals('A'), equals('B')));

      final finalValue = await repository.getValue('upsert.race');
      expect(finalValue.isOk, isTrue);
      expect(finalValue.value, anyOf(equals('A'), equals('B')));
    });
  });
}
