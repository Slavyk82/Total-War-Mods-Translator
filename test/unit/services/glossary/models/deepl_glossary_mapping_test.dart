import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/glossary/models/deepl_glossary_mapping.dart';

DeepLGlossaryMapping _mapping({String status = 'synced'}) => DeepLGlossaryMapping(
      id: 'm1',
      twmtGlossaryId: 'g1',
      sourceLanguageCode: 'en',
      targetLanguageCode: 'fr',
      deeplGlossaryId: 'deepl-1',
      deeplGlossaryName: 'EN→FR',
      entryCount: 12,
      syncStatus: status,
      syncedAt: 100,
      createdAt: 1,
      updatedAt: 2,
    );

void main() {
  group('status getters', () {
    test('reflect the syncStatus value', () {
      expect(_mapping(status: 'synced').isSynced, isTrue);
      expect(_mapping(status: 'synced').hasError, isFalse);
      expect(_mapping(status: 'error').hasError, isTrue);
      expect(_mapping(status: 'pending').isPending, isTrue);
    });

    test('languagePair formats source and target', () {
      expect(_mapping().languagePair, 'en → fr');
    });
  });

  group('copyWith / equality / json', () {
    test('copyWith overrides only the targeted field', () {
      final m = _mapping();
      expect(m.copyWith(entryCount: 99).entryCount, 99);
      expect(m.copyWith(entryCount: 99).id, 'm1');
    });

    test('equality keys on the identity fields', () {
      expect(_mapping(), equals(_mapping()));
      expect(_mapping().hashCode, _mapping().hashCode);
      expect(_mapping(status: 'pending'), equals(_mapping())); // status not in ==
    });

    test('json round-trip', () {
      final restored = DeepLGlossaryMapping.fromJson(_mapping().toJson());
      expect(restored.id, 'm1');
      expect(restored.deeplGlossaryId, 'deepl-1');
      expect(restored.entryCount, 12);
      expect(restored.syncStatus, 'synced');
    });
  });
}
