import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';

void main() {
  LlmProviderModel makeModel({
    String id = 'm-1',
    String providerCode = 'anthropic',
    String modelId = 'claude-3-5-sonnet-20241022',
    String? displayName,
    bool isEnabled = false,
    bool isDefault = false,
    bool isArchived = false,
    int createdAt = 100,
    int updatedAt = 200,
    int lastFetchedAt = 300,
  }) {
    return LlmProviderModel(
      id: id,
      providerCode: providerCode,
      modelId: modelId,
      displayName: displayName,
      isEnabled: isEnabled,
      isDefault: isDefault,
      isArchived: isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastFetchedAt: lastFetchedAt,
    );
  }

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const model = LlmProviderModel(
        id: 'id',
        providerCode: 'openai',
        modelId: 'gpt-4',
        createdAt: 1,
        updatedAt: 2,
        lastFetchedAt: 3,
      );
      expect(model.displayName, isNull);
      expect(model.isEnabled, isFalse);
      expect(model.isDefault, isFalse);
      expect(model.isArchived, isFalse);
    });
  });

  group('computed getters', () {
    test('friendlyName prefers displayName', () {
      expect(
        makeModel(displayName: 'Claude Sonnet').friendlyName,
        'Claude Sonnet',
      );
    });

    test('friendlyName falls back to modelId', () {
      expect(
        makeModel(displayName: null, modelId: 'gpt-4').friendlyName,
        'gpt-4',
      );
    });

    test('isAvailable / canBeEnabled / canBeDefault when not archived', () {
      final model = makeModel(isArchived: false);
      expect(model.isAvailable, isTrue);
      expect(model.canBeEnabled, isTrue);
      expect(model.canBeDefault, isTrue);
    });

    test('archived models are unavailable and locked', () {
      final model = makeModel(isArchived: true);
      expect(model.isAvailable, isFalse);
      expect(model.canBeEnabled, isFalse);
      expect(model.canBeDefault, isFalse);
    });
  });

  group('copyWith', () {
    final base = makeModel(
      id: 'a',
      providerCode: 'anthropic',
      modelId: 'model',
      displayName: 'name',
      isEnabled: true,
      isDefault: true,
      isArchived: false,
      createdAt: 100,
      updatedAt: 200,
      lastFetchedAt: 300,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(providerCode: 'z').providerCode, 'z');
      expect(base.copyWith(modelId: 'z').modelId, 'z');
      expect(base.copyWith(displayName: 'z').displayName, 'z');
      expect(base.copyWith(isEnabled: false).isEnabled, isFalse);
      expect(base.copyWith(isDefault: false).isDefault, isFalse);
      expect(base.copyWith(isArchived: true).isArchived, isTrue);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
      expect(base.copyWith(lastFetchedAt: 999).lastFetchedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(isArchived: true);
      expect(copy.id, base.id);
      expect(copy.providerCode, base.providerCode);
      expect(copy.modelId, base.modelId);
      expect(copy.displayName, base.displayName);
      expect(copy.isEnabled, base.isEnabled);
      expect(copy.isDefault, base.isDefault);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
      expect(copy.lastFetchedAt, base.lastFetchedAt);
    });
  });

  group('JSON', () {
    final full = makeModel(
      id: 'a',
      providerCode: 'anthropic',
      modelId: 'model',
      displayName: 'name',
      isEnabled: true,
      isDefault: true,
      isArchived: false,
      createdAt: 100,
      updatedAt: 200,
      lastFetchedAt: 300,
    );

    test('toJson uses snake_case keys and int booleans', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['provider_code'], 'anthropic');
      expect(json['model_id'], 'model');
      expect(json['display_name'], 'name');
      expect(json['is_enabled'], 1);
      expect(json['is_default'], 1);
      expect(json['is_archived'], 0);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);
      expect(json['last_fetched_at'], 300);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = LlmProviderModel.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes int booleans', () {
      final decoded = LlmProviderModel.fromJson({
        'id': 'a',
        'provider_code': 'p',
        'model_id': 'm',
        'is_enabled': 1,
        'is_default': 0,
        'is_archived': 1,
        'created_at': 1,
        'updated_at': 2,
        'last_fetched_at': 3,
      });
      expect(decoded.isEnabled, isTrue);
      expect(decoded.isDefault, isFalse);
      expect(decoded.isArchived, isTrue);
    });
  });

  group('equality and hashCode', () {
    final a = makeModel(displayName: 'name', isEnabled: true);

    test('identical instance is equal', () {
      expect(a == a, isTrue);
    });

    test('equal field-for-field copies are equal with same hashCode', () {
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copies without displayName share hashCode too', () {
      final x = makeModel(displayName: null);
      final y = makeModel(displayName: null);
      expect(x, y);
      expect(x.hashCode, y.hashCode);
    });

    test('differs when any field differs', () {
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(providerCode: 'z'), isFalse);
      expect(a == a.copyWith(modelId: 'z'), isFalse);
      expect(a == a.copyWith(displayName: 'z'), isFalse);
      expect(a == a.copyWith(isEnabled: false), isFalse);
      expect(a == a.copyWith(isDefault: true), isFalse);
      expect(a == a.copyWith(isArchived: true), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
      expect(a == a.copyWith(lastFetchedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes all fields', () {
      final model = makeModel(
        id: 'a',
        providerCode: 'anthropic',
        modelId: 'model',
        displayName: 'name',
        isEnabled: true,
        isDefault: false,
        isArchived: false,
        createdAt: 100,
        updatedAt: 200,
        lastFetchedAt: 300,
      );
      expect(
        model.toString(),
        'LlmProviderModel('
        'id: a, '
        'providerCode: anthropic, '
        'modelId: model, '
        'displayName: name, '
        'isEnabled: true, '
        'isDefault: false, '
        'isArchived: false, '
        'createdAt: 100, '
        'updatedAt: 200, '
        'lastFetchedAt: 300'
        ')',
      );
    });
  });
}
