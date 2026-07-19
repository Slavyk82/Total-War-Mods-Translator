import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_unit.dart';

void main() {
  TranslationUnit makeUnit({
    String id = 'tu-1',
    String projectId = 'p-1',
    String key = 'ui_text_key',
    String sourceText = 'Hello world',
    String? context,
    String? notes,
    String? sourceLocFile,
    bool isObsolete = false,
    int createdAt = 100,
    int updatedAt = 200,
  }) {
    return TranslationUnit(
      id: id,
      projectId: projectId,
      key: key,
      sourceText: sourceText,
      context: context,
      notes: notes,
      sourceLocFile: sourceLocFile,
      isObsolete: isObsolete,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('boolean getters', () {
    test('isActive is the inverse of isObsolete', () {
      expect(makeUnit(isObsolete: false).isActive, isTrue);
      expect(makeUnit(isObsolete: true).isActive, isFalse);
    });

    test('hasContext', () {
      expect(makeUnit(context: 'ctx').hasContext, isTrue);
      expect(makeUnit(context: null).hasContext, isFalse);
      expect(makeUnit(context: '').hasContext, isFalse);
    });

    test('hasNotes', () {
      expect(makeUnit(notes: 'note').hasNotes, isTrue);
      expect(makeUnit(notes: null).hasNotes, isFalse);
      expect(makeUnit(notes: '').hasNotes, isFalse);
    });

    test('hasAdditionalInfo', () {
      expect(makeUnit(context: 'ctx').hasAdditionalInfo, isTrue);
      expect(makeUnit(notes: 'note').hasAdditionalInfo, isTrue);
      expect(makeUnit().hasAdditionalInfo, isFalse);
    });

    test('hasSourceLocFile', () {
      expect(makeUnit(sourceLocFile: 'text/db/x.loc').hasSourceLocFile,
          isTrue);
      expect(makeUnit(sourceLocFile: null).hasSourceLocFile, isFalse);
      expect(makeUnit(sourceLocFile: '').hasSourceLocFile, isFalse);
    });
  });

  group('getSourceTextPreview', () {
    test('returns full text when short', () {
      expect(makeUnit(sourceText: 'short').getSourceTextPreview(), 'short');
    });

    test('truncates long text with ellipsis', () {
      final longText = 'a' * 150;
      expect(
        makeUnit(sourceText: longText).getSourceTextPreview(),
        '${'a' * 100}...',
      );
    });

    test('honors custom maxLength', () {
      expect(
        makeUnit(sourceText: 'abcdefghij').getSourceTextPreview(4),
        'abcd...',
      );
    });
  });

  group('combinedInfo', () {
    test('is null when no context or notes', () {
      expect(makeUnit().combinedInfo, isNull);
    });

    test('includes context only', () {
      expect(makeUnit(context: 'ctx').combinedInfo, 'Context: ctx');
    });

    test('includes notes only', () {
      expect(makeUnit(notes: 'note').combinedInfo, 'Notes: note');
    });

    test('joins context and notes with newline', () {
      expect(
        makeUnit(context: 'ctx', notes: 'note').combinedInfo,
        'Context: ctx\nNotes: note',
      );
    });
  });

  group('copyWith', () {
    final base = makeUnit(
      id: 'a',
      projectId: 'p',
      key: 'k',
      sourceText: 's',
      context: 'ctx',
      notes: 'note',
      sourceLocFile: 'loc',
      isObsolete: false,
      createdAt: 100,
      updatedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(key: 'z').key, 'z');
      expect(base.copyWith(sourceText: 'z').sourceText, 'z');
      expect(base.copyWith(context: 'z').context, 'z');
      expect(base.copyWith(notes: 'z').notes, 'z');
      expect(base.copyWith(sourceLocFile: 'z').sourceLocFile, 'z');
      expect(base.copyWith(isObsolete: true).isObsolete, isTrue);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(sourceText: 'other');
      expect(copy.id, base.id);
      expect(copy.projectId, base.projectId);
      expect(copy.key, base.key);
      expect(copy.context, base.context);
      expect(copy.notes, base.notes);
      expect(copy.sourceLocFile, base.sourceLocFile);
      expect(copy.isObsolete, base.isObsolete);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('JSON', () {
    final full = makeUnit(
      id: 'a',
      projectId: 'p',
      key: 'k',
      sourceText: 's',
      context: 'ctx',
      notes: 'note',
      sourceLocFile: 'text/db/x.loc',
      isObsolete: true,
      createdAt: 100,
      updatedAt: 200,
    );

    test('toJson uses snake_case keys and serializes is_obsolete as int', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['project_id'], 'p');
      expect(json['key'], 'k');
      expect(json['source_text'], 's');
      expect(json['context'], 'ctx');
      expect(json['notes'], 'note');
      expect(json['source_loc_file'], 'text/db/x.loc');
      expect(json['is_obsolete'], 1);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);

      expect(makeUnit(isObsolete: false).toJson()['is_obsolete'], 0);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          TranslationUnit.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes is_obsolete from int and bool', () {
      TranslationUnit decode(dynamic raw) => TranslationUnit.fromJson({
            'id': 'a',
            'project_id': 'p',
            'key': 'k',
            'source_text': 's',
            'created_at': 1,
            'updated_at': 2,
            'is_obsolete': raw,
          });
      expect(decode(1).isObsolete, isTrue);
      expect(decode(0).isObsolete, isFalse);
      expect(decode(true).isObsolete, isTrue);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationUnit.fromJson({
        'id': 'a',
        'project_id': 'p',
        'key': 'k',
        'source_text': 's',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.context, isNull);
      expect(decoded.notes, isNull);
      expect(decoded.sourceLocFile, isNull);
      expect(decoded.isObsolete, isFalse);
    });
  });

  group('equality and hashCode', () {
    final a = makeUnit(
      id: 'a',
      context: 'ctx',
      notes: 'note',
      sourceLocFile: 'loc',
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
      expect(a == a.copyWith(projectId: 'z'), isFalse);
      expect(a == a.copyWith(key: 'z'), isFalse);
      expect(a == a.copyWith(sourceText: 'z'), isFalse);
      expect(a == a.copyWith(context: 'z'), isFalse);
      expect(a == a.copyWith(notes: 'z'), isFalse);
      expect(a == a.copyWith(sourceLocFile: 'z'), isFalse);
      expect(a == a.copyWith(isObsolete: true), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, key, projectId and isObsolete', () {
      final unit = makeUnit(id: 'a', key: 'k', projectId: 'p');
      expect(
        unit.toString(),
        'TranslationUnit(id: a, key: k, projectId: p, isObsolete: false)',
      );
    });
  });
}
