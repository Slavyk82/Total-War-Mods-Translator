import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/setting.dart';

void main() {
  Setting makeSetting({
    String id = 's-1',
    String key = 'app.theme',
    String value = 'dark',
    SettingValueType valueType = SettingValueType.string,
    int updatedAt = 100,
  }) {
    return Setting(
      id: id,
      key: key,
      value: value,
      valueType: valueType,
      updatedAt: updatedAt,
    );
  }

  group('SettingValueType enum', () {
    test('has all four values', () {
      expect(SettingValueType.values, hasLength(4));
      expect(
        SettingValueType.values,
        containsAll([
          SettingValueType.string,
          SettingValueType.integer,
          SettingValueType.boolean,
          SettingValueType.json,
        ]),
      );
    });
  });

  group('type boolean getters', () {
    test('isString / isInteger / isBoolean / isJson', () {
      final string = makeSetting(valueType: SettingValueType.string);
      expect(string.isString, isTrue);
      expect(string.isInteger, isFalse);
      expect(string.isBoolean, isFalse);
      expect(string.isJson, isFalse);

      expect(makeSetting(valueType: SettingValueType.integer).isInteger,
          isTrue);
      expect(makeSetting(valueType: SettingValueType.boolean).isBoolean,
          isTrue);
      expect(makeSetting(valueType: SettingValueType.json).isJson, isTrue);
    });
  });

  group('intValue', () {
    test('parses integer values', () {
      expect(
        makeSetting(value: '42', valueType: SettingValueType.integer).intValue,
        42,
      );
    });

    test('returns null for unparseable value', () {
      expect(
        makeSetting(value: 'abc', valueType: SettingValueType.integer)
            .intValue,
        isNull,
      );
    });

    test('returns null when type is not integer', () {
      expect(
        makeSetting(value: '42', valueType: SettingValueType.string).intValue,
        isNull,
      );
    });
  });

  group('boolValue', () {
    Setting boolSetting(String value) =>
        makeSetting(value: value, valueType: SettingValueType.boolean);

    test('parses true variants', () {
      expect(boolSetting('true').boolValue, isTrue);
      expect(boolSetting('TRUE').boolValue, isTrue);
      expect(boolSetting('1').boolValue, isTrue);
    });

    test('parses false variants', () {
      expect(boolSetting('false').boolValue, isFalse);
      expect(boolSetting('False').boolValue, isFalse);
      expect(boolSetting('0').boolValue, isFalse);
    });

    test('returns null for unparseable value', () {
      expect(boolSetting('yes').boolValue, isNull);
    });

    test('returns null when type is not boolean', () {
      expect(
        makeSetting(value: 'true', valueType: SettingValueType.string)
            .boolValue,
        isNull,
      );
    });
  });

  group('display getters', () {
    test('stringValue always returns raw value', () {
      expect(makeSetting(value: 'raw').stringValue, 'raw');
    });

    test('valueTypeDisplay maps each type', () {
      expect(
        makeSetting(valueType: SettingValueType.string).valueTypeDisplay,
        'Text',
      );
      expect(
        makeSetting(valueType: SettingValueType.integer).valueTypeDisplay,
        'Number',
      );
      expect(
        makeSetting(valueType: SettingValueType.boolean).valueTypeDisplay,
        'Yes/No',
      );
      expect(
        makeSetting(valueType: SettingValueType.json).valueTypeDisplay,
        'JSON',
      );
    });

    test('displayValue for booleans', () {
      expect(
        makeSetting(value: 'true', valueType: SettingValueType.boolean)
            .displayValue,
        'Yes',
      );
      expect(
        makeSetting(value: 'false', valueType: SettingValueType.boolean)
            .displayValue,
        'No',
      );
      // Unparseable boolean falls back to 'No'
      expect(
        makeSetting(value: 'garbage', valueType: SettingValueType.boolean)
            .displayValue,
        'No',
      );
    });

    test('displayValue for integers', () {
      expect(
        makeSetting(value: '42', valueType: SettingValueType.integer)
            .displayValue,
        '42',
      );
      // Unparseable integer falls back to raw value
      expect(
        makeSetting(value: 'abc', valueType: SettingValueType.integer)
            .displayValue,
        'abc',
      );
    });

    test('displayValue for string and json returns raw value', () {
      expect(
        makeSetting(value: 'txt', valueType: SettingValueType.string)
            .displayValue,
        'txt',
      );
      expect(
        makeSetting(value: '{"a":1}', valueType: SettingValueType.json)
            .displayValue,
        '{"a":1}',
      );
    });

    test('getValuePreview truncates long values', () {
      expect(makeSetting(value: 'short').getValuePreview(), 'short');
      final longValue = 'x' * 60;
      expect(
        makeSetting(value: longValue).getValuePreview(),
        '${'x' * 50}...',
      );
      expect(
        makeSetting(value: 'abcdefgh').getValuePreview(4),
        'abcd...',
      );
    });

    test('updatedAtAsDateTime converts unix seconds', () {
      expect(
        makeSetting(updatedAt: 1000).updatedAtAsDateTime,
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );
    });
  });

  group('named factories', () {
    test('Setting.string', () {
      final setting = Setting.string(
        id: 'a',
        key: 'k',
        value: 'v',
        updatedAt: 1,
      );
      expect(setting.valueType, SettingValueType.string);
      expect(setting.value, 'v');
    });

    test('Setting.integer stores value as string', () {
      final setting = Setting.integer(
        id: 'a',
        key: 'k',
        value: 42,
        updatedAt: 1,
      );
      expect(setting.valueType, SettingValueType.integer);
      expect(setting.value, '42');
      expect(setting.intValue, 42);
    });

    test('Setting.boolean stores true/false strings', () {
      final yes = Setting.boolean(id: 'a', key: 'k', value: true, updatedAt: 1);
      expect(yes.valueType, SettingValueType.boolean);
      expect(yes.value, 'true');
      expect(yes.boolValue, isTrue);

      final no = Setting.boolean(id: 'a', key: 'k', value: false, updatedAt: 1);
      expect(no.value, 'false');
      expect(no.boolValue, isFalse);
    });

    test('Setting.json', () {
      final setting = Setting.json(
        id: 'a',
        key: 'k',
        value: '{"a":1}',
        updatedAt: 1,
      );
      expect(setting.valueType, SettingValueType.json);
      expect(setting.value, '{"a":1}');
    });
  });

  group('copyWith', () {
    final base = makeSetting(
      id: 'a',
      key: 'k',
      value: 'v',
      valueType: SettingValueType.string,
      updatedAt: 100,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(key: 'z').key, 'z');
      expect(base.copyWith(value: 'z').value, 'z');
      expect(
        base.copyWith(valueType: SettingValueType.json).valueType,
        SettingValueType.json,
      );
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(value: 'other');
      expect(copy.id, base.id);
      expect(copy.key, base.key);
      expect(copy.valueType, base.valueType);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('JSON', () {
    final full = makeSetting(
      id: 'a',
      key: 'k',
      value: 'v',
      valueType: SettingValueType.boolean,
      updatedAt: 100,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['key'], 'k');
      expect(json['value'], 'v');
      expect(json['value_type'], 'boolean');
      expect(json['updated_at'], 100);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          Setting.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes each value_type', () {
      for (final entry in {
        'string': SettingValueType.string,
        'integer': SettingValueType.integer,
        'boolean': SettingValueType.boolean,
        'json': SettingValueType.json,
      }.entries) {
        final decoded = Setting.fromJson({
          'id': 'a',
          'key': 'k',
          'value': 'v',
          'value_type': entry.key,
          'updated_at': 1,
        });
        expect(decoded.valueType, entry.value);
      }
    });

    test('fromJson applies default value_type when missing', () {
      final decoded = Setting.fromJson({
        'id': 'a',
        'key': 'k',
        'value': 'v',
        'updated_at': 1,
      });
      expect(decoded.valueType, SettingValueType.string);
    });
  });

  group('equality and hashCode', () {
    final a = makeSetting();

    test('identical instance is equal', () {
      expect(a == a, isTrue);
    });

    test('equal field-for-field copies are equal with same hashCode', () {
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(key: 'z'), isFalse);
      expect(a == a.copyWith(value: 'z'), isFalse);
      expect(a == a.copyWith(valueType: SettingValueType.json), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, key, value, valueType and updatedAt', () {
      final setting = makeSetting(
        id: 'a',
        key: 'k',
        value: 'v',
        valueType: SettingValueType.string,
        updatedAt: 100,
      );
      expect(
        setting.toString(),
        'Setting(id: a, key: k, value: v, '
        'valueType: SettingValueType.string, updatedAt: 100)',
      );
    });
  });
}
