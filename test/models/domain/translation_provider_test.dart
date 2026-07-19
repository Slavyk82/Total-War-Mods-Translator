import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_provider.dart';

void main() {
  TranslationProvider makeProvider({
    String id = 'tp-1',
    String code = 'anthropic',
    String name = 'Anthropic Claude',
    String? apiEndpoint,
    String? defaultModel,
    int? maxContextTokens,
    int maxBatchSize = 30,
    int? rateLimitRpm,
    int? rateLimitTpm,
    bool isActive = true,
    int createdAt = 100,
  }) {
    return TranslationProvider(
      id: id,
      code: code,
      name: name,
      apiEndpoint: apiEndpoint,
      defaultModel: defaultModel,
      maxContextTokens: maxContextTokens,
      maxBatchSize: maxBatchSize,
      rateLimitRpm: rateLimitRpm,
      rateLimitTpm: rateLimitTpm,
      isActive: isActive,
      createdAt: createdAt,
    );
  }

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const provider = TranslationProvider(
        id: 'id',
        code: 'deepl',
        name: 'DeepL',
        createdAt: 1,
      );
      expect(provider.apiEndpoint, isNull);
      expect(provider.defaultModel, isNull);
      expect(provider.maxContextTokens, isNull);
      expect(provider.maxBatchSize, 30);
      expect(provider.rateLimitRpm, isNull);
      expect(provider.rateLimitTpm, isNull);
      expect(provider.isActive, isTrue);
    });
  });

  group('computed getters', () {
    test('isEnabled mirrors isActive', () {
      expect(makeProvider(isActive: true).isEnabled, isTrue);
      expect(makeProvider(isActive: false).isEnabled, isFalse);
    });

    test('hasRateLimits when either limit is set', () {
      expect(makeProvider(rateLimitRpm: 60).hasRateLimits, isTrue);
      expect(makeProvider(rateLimitTpm: 10000).hasRateLimits, isTrue);
      expect(
        makeProvider(rateLimitRpm: 60, rateLimitTpm: 10000).hasRateLimits,
        isTrue,
      );
      expect(makeProvider().hasRateLimits, isFalse);
    });

    test('hasContextLimit requires positive maxContextTokens', () {
      expect(makeProvider(maxContextTokens: 200000).hasContextLimit, isTrue);
      expect(makeProvider(maxContextTokens: 0).hasContextLimit, isFalse);
      expect(makeProvider(maxContextTokens: null).hasContextLimit, isFalse);
    });

    test('displayNameWithModel includes model when set', () {
      expect(
        makeProvider(name: 'Claude', defaultModel: 'sonnet')
            .displayNameWithModel,
        'Claude (sonnet)',
      );
    });

    test('displayNameWithModel is plain name without model', () {
      expect(
        makeProvider(name: 'Claude', defaultModel: null).displayNameWithModel,
        'Claude',
      );
    });
  });

  group('copyWith', () {
    final base = makeProvider(
      id: 'a',
      code: 'c',
      name: 'n',
      apiEndpoint: 'https://api',
      defaultModel: 'model',
      maxContextTokens: 1000,
      maxBatchSize: 20,
      rateLimitRpm: 60,
      rateLimitTpm: 10000,
      isActive: true,
      createdAt: 100,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(code: 'z').code, 'z');
      expect(base.copyWith(name: 'z').name, 'z');
      expect(base.copyWith(apiEndpoint: 'z').apiEndpoint, 'z');
      expect(base.copyWith(defaultModel: 'z').defaultModel, 'z');
      expect(base.copyWith(maxContextTokens: 99).maxContextTokens, 99);
      expect(base.copyWith(maxBatchSize: 99).maxBatchSize, 99);
      expect(base.copyWith(rateLimitRpm: 99).rateLimitRpm, 99);
      expect(base.copyWith(rateLimitTpm: 99).rateLimitTpm, 99);
      expect(base.copyWith(isActive: false).isActive, isFalse);
      expect(base.copyWith(createdAt: 999).createdAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(name: 'other');
      expect(copy.id, base.id);
      expect(copy.code, base.code);
      expect(copy.apiEndpoint, base.apiEndpoint);
      expect(copy.defaultModel, base.defaultModel);
      expect(copy.maxContextTokens, base.maxContextTokens);
      expect(copy.maxBatchSize, base.maxBatchSize);
      expect(copy.rateLimitRpm, base.rateLimitRpm);
      expect(copy.rateLimitTpm, base.rateLimitTpm);
      expect(copy.isActive, base.isActive);
      expect(copy.createdAt, base.createdAt);
    });
  });

  group('JSON', () {
    final full = makeProvider(
      id: 'a',
      code: 'c',
      name: 'n',
      apiEndpoint: 'https://api',
      defaultModel: 'model',
      maxContextTokens: 1000,
      maxBatchSize: 20,
      rateLimitRpm: 60,
      rateLimitTpm: 10000,
      isActive: true,
      createdAt: 100,
    );

    test('toJson uses snake_case keys and int boolean', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['code'], 'c');
      expect(json['name'], 'n');
      expect(json['api_endpoint'], 'https://api');
      expect(json['default_model'], 'model');
      expect(json['max_context_tokens'], 1000);
      expect(json['max_batch_size'], 20);
      expect(json['rate_limit_rpm'], 60);
      expect(json['rate_limit_tpm'], 10000);
      expect(json['is_active'], 1);
      expect(json['created_at'], 100);

      expect(makeProvider(isActive: false).toJson()['is_active'], 0);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = TranslationProvider.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationProvider.fromJson({
        'id': 'a',
        'code': 'c',
        'name': 'n',
        'created_at': 1,
      });
      expect(decoded.maxBatchSize, 30);
      expect(decoded.isActive, isTrue);
      expect(decoded.apiEndpoint, isNull);
      expect(decoded.rateLimitRpm, isNull);
    });
  });

  group('equality and hashCode', () {
    final a = makeProvider(
      apiEndpoint: 'https://api',
      defaultModel: 'model',
      maxContextTokens: 1000,
      rateLimitRpm: 60,
      rateLimitTpm: 10000,
    );

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
      expect(a == a.copyWith(code: 'z'), isFalse);
      expect(a == a.copyWith(name: 'z'), isFalse);
      expect(a == a.copyWith(apiEndpoint: 'z'), isFalse);
      expect(a == a.copyWith(defaultModel: 'z'), isFalse);
      expect(a == a.copyWith(maxContextTokens: 99), isFalse);
      expect(a == a.copyWith(maxBatchSize: 99), isFalse);
      expect(a == a.copyWith(rateLimitRpm: 99), isFalse);
      expect(a == a.copyWith(rateLimitTpm: 99), isFalse);
      expect(a == a.copyWith(isActive: false), isFalse);
      expect(a == a.copyWith(createdAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes all fields', () {
      final provider = makeProvider(
        id: 'a',
        code: 'c',
        name: 'n',
        apiEndpoint: 'e',
        defaultModel: 'm',
        maxContextTokens: 1,
        maxBatchSize: 2,
        rateLimitRpm: 3,
        rateLimitTpm: 4,
        isActive: true,
        createdAt: 5,
      );
      expect(
        provider.toString(),
        'TranslationProvider(id: a, code: c, name: n, apiEndpoint: e, '
        'defaultModel: m, maxContextTokens: 1, maxBatchSize: 2, '
        'rateLimitRpm: 3, rateLimitTpm: 4, isActive: true, createdAt: 5)',
      );
    });
  });
}
