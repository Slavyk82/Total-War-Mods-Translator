import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';

void main() {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  TranslationMemoryEntry makeEntry({
    String id = 'tm-1',
    String sourceText = 'Hello world',
    String sourceHash = 'hash-1',
    String sourceLanguageId = 'lang_en',
    String targetLanguageId = 'lang_fr',
    String translatedText = 'Bonjour le monde',
    String? translationProviderId,
    int usageCount = 0,
    int? createdAt,
    int? lastUsedAt,
    int? updatedAt,
  }) {
    return TranslationMemoryEntry(
      id: id,
      sourceText: sourceText,
      sourceHash: sourceHash,
      sourceLanguageId: sourceLanguageId,
      targetLanguageId: targetLanguageId,
      translatedText: translatedText,
      translationProviderId: translationProviderId,
      usageCount: usageCount,
      createdAt: createdAt ?? nowSec - 100,
      lastUsedAt: lastUsedAt ?? nowSec,
      updatedAt: updatedAt ?? nowSec,
    );
  }

  group('boolean getters', () {
    test('isFrequentlyUsed requires more than 5 uses', () {
      expect(makeEntry(usageCount: 5).isFrequentlyUsed, isFalse);
      expect(makeEntry(usageCount: 6).isFrequentlyUsed, isTrue);
    });

    test('hasProvider', () {
      expect(makeEntry(translationProviderId: 'prov').hasProvider, isTrue);
      expect(makeEntry(translationProviderId: null).hasProvider, isFalse);
      expect(makeEntry(translationProviderId: '').hasProvider, isFalse);
    });
  });

  group('recency getters', () {
    test('daysSinceLastUse computes elapsed days', () {
      final entry = makeEntry(lastUsedAt: nowSec - 5 * 86400);
      expect(entry.daysSinceLastUse, 5);
    });

    test('isRecentlyUsed within 30 days', () {
      expect(makeEntry(lastUsedAt: nowSec - 10 * 86400).isRecentlyUsed, isTrue);
      expect(
        makeEntry(lastUsedAt: nowSec - 40 * 86400).isRecentlyUsed,
        isFalse,
      );
    });

    test('isStale after 180 days', () {
      expect(makeEntry(lastUsedAt: nowSec - 200 * 86400).isStale, isTrue);
      expect(makeEntry(lastUsedAt: nowSec - 100 * 86400).isStale, isFalse);
    });
  });

  group('text previews', () {
    test('getSourceTextPreview returns full text when short', () {
      expect(makeEntry(sourceText: 'short').getSourceTextPreview(), 'short');
    });

    test('getSourceTextPreview truncates long text with ellipsis', () {
      final longText = 'a' * 60;
      expect(
        makeEntry(sourceText: longText).getSourceTextPreview(),
        '${'a' * 50}...',
      );
    });

    test('getSourceTextPreview honors custom maxLength', () {
      expect(
        makeEntry(sourceText: 'abcdefghij').getSourceTextPreview(4),
        'abcd...',
      );
    });

    test('getTranslatedTextPreview returns full text when short', () {
      expect(
        makeEntry(translatedText: 'court').getTranslatedTextPreview(),
        'court',
      );
    });

    test('getTranslatedTextPreview truncates long text', () {
      final longText = 'b' * 60;
      expect(
        makeEntry(translatedText: longText).getTranslatedTextPreview(10),
        '${'b' * 10}...',
      );
    });
  });

  group('usageDisplay', () {
    test('never used', () {
      expect(makeEntry(usageCount: 0).usageDisplay, 'Never used');
    });

    test('used once', () {
      expect(makeEntry(usageCount: 1).usageDisplay, 'Used once');
    });

    test('used n times', () {
      expect(makeEntry(usageCount: 7).usageDisplay, 'Used 7 times');
    });
  });

  group('copyWith', () {
    final base = makeEntry(
      id: 'a',
      translationProviderId: 'prov',
      usageCount: 3,
      createdAt: 100,
      lastUsedAt: 200,
      updatedAt: 300,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(sourceText: 'z').sourceText, 'z');
      expect(base.copyWith(sourceHash: 'z').sourceHash, 'z');
      expect(base.copyWith(sourceLanguageId: 'z').sourceLanguageId, 'z');
      expect(base.copyWith(targetLanguageId: 'z').targetLanguageId, 'z');
      expect(base.copyWith(translatedText: 'z').translatedText, 'z');
      expect(
        base.copyWith(translationProviderId: 'z').translationProviderId,
        'z',
      );
      expect(base.copyWith(usageCount: 9).usageCount, 9);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(lastUsedAt: 999).lastUsedAt, 999);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(usageCount: 9);
      expect(copy.id, base.id);
      expect(copy.sourceText, base.sourceText);
      expect(copy.sourceHash, base.sourceHash);
      expect(copy.translationProviderId, base.translationProviderId);
      expect(copy.createdAt, base.createdAt);
      expect(copy.lastUsedAt, base.lastUsedAt);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('JSON', () {
    final full = makeEntry(
      id: 'a',
      sourceText: 'Hello',
      sourceHash: 'h',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: 'Bonjour',
      translationProviderId: 'prov',
      usageCount: 3,
      createdAt: 100,
      lastUsedAt: 200,
      updatedAt: 300,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['source_text'], 'Hello');
      expect(json['source_hash'], 'h');
      expect(json['source_language_id'], 'lang_en');
      expect(json['target_language_id'], 'lang_fr');
      expect(json['translated_text'], 'Bonjour');
      expect(json['translation_provider_id'], 'prov');
      expect(json['usage_count'], 3);
      expect(json['created_at'], 100);
      expect(json['last_used_at'], 200);
      expect(json['updated_at'], 300);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = TranslationMemoryEntry.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationMemoryEntry.fromJson({
        'id': 'a',
        'source_text': 's',
        'source_hash': 'h',
        'source_language_id': 'en',
        'target_language_id': 'fr',
        'translated_text': 't',
        'created_at': 1,
        'last_used_at': 2,
        'updated_at': 3,
      });
      expect(decoded.translationProviderId, isNull);
      expect(decoded.usageCount, 0);
    });
  });

  group('equality and hashCode', () {
    final a = makeEntry(
      id: 'a',
      translationProviderId: 'prov',
      usageCount: 3,
      createdAt: 100,
      lastUsedAt: 200,
      updatedAt: 300,
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
      expect(a == a.copyWith(sourceText: 'z'), isFalse);
      expect(a == a.copyWith(sourceHash: 'z'), isFalse);
      expect(a == a.copyWith(sourceLanguageId: 'z'), isFalse);
      expect(a == a.copyWith(targetLanguageId: 'z'), isFalse);
      expect(a == a.copyWith(translatedText: 'z'), isFalse);
      expect(a == a.copyWith(translationProviderId: 'z'), isFalse);
      expect(a == a.copyWith(usageCount: 9), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(lastUsedAt: 999), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, sourceHash and usageCount', () {
      final entry = makeEntry(id: 'a', sourceHash: 'h', usageCount: 3);
      expect(
        entry.toString(),
        'TranslationMemoryEntry(id: a, sourceHash: h, usageCount: 3)',
      );
    });
  });
}
