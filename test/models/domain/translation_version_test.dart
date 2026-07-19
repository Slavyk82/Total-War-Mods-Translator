import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_version.dart';

void main() {
  TranslationVersion makeVersion({
    String id = 'tv-1',
    String unitId = 'u-1',
    String projectLanguageId = 'pl-1',
    String? translatedText,
    bool isManuallyEdited = false,
    TranslationVersionStatus status = TranslationVersionStatus.pending,
    TranslationSource translationSource = TranslationSource.unknown,
    String? validationIssues,
    int validationSchemaVersion = 0,
    int createdAt = 100,
    int updatedAt = 200,
  }) {
    return TranslationVersion(
      id: id,
      unitId: unitId,
      projectLanguageId: projectLanguageId,
      translatedText: translatedText,
      isManuallyEdited: isManuallyEdited,
      status: status,
      translationSource: translationSource,
      validationIssues: validationIssues,
      validationSchemaVersion: validationSchemaVersion,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('TranslationVersionStatus.toDbValue', () {
    test('maps each status to its DB string', () {
      expect(TranslationVersionStatus.pending.toDbValue, 'pending');
      expect(TranslationVersionStatus.translated.toDbValue, 'translated');
      expect(TranslationVersionStatus.needsReview.toDbValue, 'needs_review');
    });
  });

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const version = TranslationVersion(
        id: 'id',
        unitId: 'u',
        projectLanguageId: 'pl',
        createdAt: 1,
        updatedAt: 2,
      );
      expect(version.translatedText, isNull);
      expect(version.isManuallyEdited, isFalse);
      expect(version.status, TranslationVersionStatus.pending);
      expect(version.translationSource, TranslationSource.unknown);
      expect(version.validationIssues, isNull);
      expect(version.validationSchemaVersion, 0);
    });
  });

  group('status boolean getters', () {
    test('isPending', () {
      expect(
        makeVersion(status: TranslationVersionStatus.pending).isPending,
        isTrue,
      );
      expect(
        makeVersion(status: TranslationVersionStatus.translated).isPending,
        isFalse,
      );
    });

    test('isTranslated and isComplete', () {
      final translated =
          makeVersion(status: TranslationVersionStatus.translated);
      expect(translated.isTranslated, isTrue);
      expect(translated.isComplete, isTrue);

      final pending = makeVersion(status: TranslationVersionStatus.pending);
      expect(pending.isTranslated, isFalse);
      expect(pending.isComplete, isFalse);
    });

    test('needsReview', () {
      expect(
        makeVersion(status: TranslationVersionStatus.needsReview).needsReview,
        isTrue,
      );
      expect(
        makeVersion(status: TranslationVersionStatus.pending).needsReview,
        isFalse,
      );
    });
  });

  group('validation getters', () {
    test('hasValidationIssues', () {
      expect(makeVersion(validationIssues: '[]').hasValidationIssues, isTrue);
      expect(
        makeVersion(validationIssues: null).hasValidationIssues,
        isFalse,
      );
      expect(makeVersion(validationIssues: '').hasValidationIssues, isFalse);
    });

    test('isReadyForUse requires translated, no issues and text', () {
      expect(
        makeVersion(
          status: TranslationVersionStatus.translated,
          translatedText: 'Bonjour',
        ).isReadyForUse,
        isTrue,
      );
      expect(
        makeVersion(
          status: TranslationVersionStatus.pending,
          translatedText: 'Bonjour',
        ).isReadyForUse,
        isFalse,
      );
      expect(
        makeVersion(
          status: TranslationVersionStatus.translated,
          translatedText: 'Bonjour',
          validationIssues: '[]',
        ).isReadyForUse,
        isFalse,
      );
      expect(
        makeVersion(
          status: TranslationVersionStatus.translated,
          translatedText: null,
        ).isReadyForUse,
        isFalse,
      );
    });
  });

  group('display getters', () {
    test('displayText falls back to placeholder', () {
      expect(makeVersion(translatedText: 'Bonjour').displayText, 'Bonjour');
      expect(makeVersion(translatedText: null).displayText,
          '(Not translated)');
    });

    test('statusDisplay maps each status', () {
      expect(
        makeVersion(status: TranslationVersionStatus.pending).statusDisplay,
        'Pending',
      );
      expect(
        makeVersion(status: TranslationVersionStatus.translated).statusDisplay,
        'Translated',
      );
      expect(
        makeVersion(status: TranslationVersionStatus.needsReview)
            .statusDisplay,
        'Needs Review',
      );
    });
  });

  group('copyWith', () {
    final base = makeVersion(
      id: 'a',
      unitId: 'u',
      projectLanguageId: 'pl',
      translatedText: 'Bonjour',
      isManuallyEdited: true,
      status: TranslationVersionStatus.translated,
      translationSource: TranslationSource.llm,
      validationIssues: '[]',
      validationSchemaVersion: 2,
      createdAt: 100,
      updatedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(unitId: 'z').unitId, 'z');
      expect(base.copyWith(projectLanguageId: 'z').projectLanguageId, 'z');
      expect(base.copyWith(translatedText: 'z').translatedText, 'z');
      expect(base.copyWith(isManuallyEdited: false).isManuallyEdited, isFalse);
      expect(
        base.copyWith(status: TranslationVersionStatus.needsReview).status,
        TranslationVersionStatus.needsReview,
      );
      expect(
        base.copyWith(translationSource: TranslationSource.manual)
            .translationSource,
        TranslationSource.manual,
      );
      expect(base.copyWith(validationIssues: 'x').validationIssues, 'x');
      expect(
        base.copyWith(validationSchemaVersion: 3).validationSchemaVersion,
        3,
      );
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('clearTranslatedText clears while plain null keeps', () {
      expect(base.copyWith(clearTranslatedText: true).translatedText, isNull);
      expect(base.copyWith(translatedText: null).translatedText, 'Bonjour');
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(updatedAt: 999);
      expect(copy.id, base.id);
      expect(copy.unitId, base.unitId);
      expect(copy.projectLanguageId, base.projectLanguageId);
      expect(copy.translatedText, base.translatedText);
      expect(copy.isManuallyEdited, base.isManuallyEdited);
      expect(copy.status, base.status);
      expect(copy.translationSource, base.translationSource);
      expect(copy.validationIssues, base.validationIssues);
      expect(copy.validationSchemaVersion, base.validationSchemaVersion);
      expect(copy.createdAt, base.createdAt);
    });
  });

  group('JSON', () {
    final full = makeVersion(
      id: 'a',
      unitId: 'u',
      projectLanguageId: 'pl',
      translatedText: 'Bonjour',
      isManuallyEdited: true,
      status: TranslationVersionStatus.needsReview,
      translationSource: TranslationSource.tmFuzzy,
      validationIssues: '[]',
      validationSchemaVersion: 2,
      createdAt: 100,
      updatedAt: 200,
    );

    test('toJson uses snake_case keys and serialized enums', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['unit_id'], 'u');
      expect(json['project_language_id'], 'pl');
      expect(json['translated_text'], 'Bonjour');
      expect(json['is_manually_edited'], 1);
      expect(json['status'], 'needs_review');
      expect(json['translation_source'], 'tm_fuzzy');
      expect(json['validation_issues'], '[]');
      expect(json['validation_schema_version'], 2);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = TranslationVersion.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes each translation_source value', () {
      for (final entry in {
        'unknown': TranslationSource.unknown,
        'manual': TranslationSource.manual,
        'tm_exact': TranslationSource.tmExact,
        'tm_fuzzy': TranslationSource.tmFuzzy,
        'llm': TranslationSource.llm,
      }.entries) {
        final decoded = TranslationVersion.fromJson({
          'id': 'a',
          'unit_id': 'u',
          'project_language_id': 'pl',
          'created_at': 1,
          'updated_at': 2,
          'translation_source': entry.key,
        });
        expect(decoded.translationSource, entry.value);
      }
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationVersion.fromJson({
        'id': 'a',
        'unit_id': 'u',
        'project_language_id': 'pl',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.translatedText, isNull);
      expect(decoded.isManuallyEdited, isFalse);
      expect(decoded.status, TranslationVersionStatus.pending);
      expect(decoded.translationSource, TranslationSource.unknown);
      expect(decoded.validationSchemaVersion, 0);
    });
  });

  group('equality and hashCode', () {
    final a = makeVersion(
      translatedText: 'Bonjour',
      isManuallyEdited: true,
      status: TranslationVersionStatus.translated,
      translationSource: TranslationSource.llm,
      validationIssues: '[]',
      validationSchemaVersion: 2,
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
      expect(a == a.copyWith(unitId: 'z'), isFalse);
      expect(a == a.copyWith(projectLanguageId: 'z'), isFalse);
      expect(a == a.copyWith(translatedText: 'z'), isFalse);
      expect(a == a.copyWith(isManuallyEdited: false), isFalse);
      expect(
        a == a.copyWith(status: TranslationVersionStatus.needsReview),
        isFalse,
      );
      expect(
        a == a.copyWith(translationSource: TranslationSource.manual),
        isFalse,
      );
      expect(a == a.copyWith(validationIssues: 'x'), isFalse);
      expect(a == a.copyWith(validationSchemaVersion: 9), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, unitId, status and isManuallyEdited', () {
      final version = makeVersion(
        id: 'a',
        unitId: 'u',
        status: TranslationVersionStatus.translated,
        isManuallyEdited: true,
      );
      expect(
        version.toString(),
        'TranslationVersion(id: a, unitId: u, '
        'status: TranslationVersionStatus.translated, isManuallyEdited: true)',
      );
    });
  });
}
