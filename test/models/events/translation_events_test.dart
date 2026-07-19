import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/translation_events.dart';

void main() {
  group('TranslationAddedEvent', () {
    TranslationAddedEvent makeEvent({String? providerId}) =>
        TranslationAddedEvent(
          versionId: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl1',
          translatedText: 'Bonjour',
          providerId: providerId,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent(providerId: 'anthropic');
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.translatedText, 'Bonjour');
      expect(event.providerId, 'anthropic');

      // Inherited from DomainEvent.now()
      expect(event.eventId, isNotEmpty);
      expect(event.timestamp, isA<DateTime>());
      expect(event.eventType, 'TranslationAddedEvent');
      expect(event.occurredAt, event.timestamp);
    });

    test('isProviderGenerated', () {
      expect(makeEvent(providerId: 'anthropic').isProviderGenerated, isTrue);
      expect(makeEvent(providerId: null).isProviderGenerated, isFalse);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes versionId and provider', () {
      expect(
        makeEvent(providerId: 'anthropic').toString(),
        'TranslationAddedEvent(versionId: v1, provider: anthropic)',
      );
    });
  });

  group('TranslationEditedEvent', () {
    TranslationEditedEvent makeEvent({String? reason}) =>
        TranslationEditedEvent(
          versionId: 'v1',
          unitId: 'u1',
          oldTranslation: 'Salut',
          newTranslation: 'Bonjour',
          editedBy: 'user',
          reason: reason,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent(reason: 'typo');
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.oldTranslation, 'Salut');
      expect(event.newTranslation, 'Bonjour');
      expect(event.editedBy, 'user');
      expect(event.reason, 'typo');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes reason or N/A', () {
      expect(
        makeEvent(reason: 'typo').toString(),
        'TranslationEditedEvent(versionId: v1, by: user, reason: typo)',
      );
      expect(
        makeEvent(reason: null).toString(),
        'TranslationEditedEvent(versionId: v1, by: user, reason: N/A)',
      );
    });
  });

  group('TranslationValidatedEvent', () {
    TranslationValidatedEvent makeEvent({
      String status = 'translated',
      List<String>? validationIssues,
    }) =>
        TranslationValidatedEvent(
          versionId: 'v1',
          unitId: 'u1',
          status: status,
          validatedBy: 'validator',
          validationIssues: validationIssues,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent(validationIssues: ['issue1']);
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.status, 'translated');
      expect(event.validatedBy, 'validator');
      expect(event.validationIssues, ['issue1']);
    });

    test('isTranslated', () {
      expect(makeEvent(status: 'translated').isTranslated, isTrue);
      expect(makeEvent(status: 'needs_review').isTranslated, isFalse);
    });

    test('hasIssues', () {
      expect(makeEvent(validationIssues: ['a']).hasIssues, isTrue);
      expect(makeEvent(validationIssues: []).hasIssues, isFalse);
      expect(makeEvent(validationIssues: null).hasIssues, isFalse);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes status and issue count', () {
      expect(
        makeEvent(validationIssues: ['a', 'b']).toString(),
        'TranslationValidatedEvent(versionId: v1, status: translated, '
        'by: validator, issues: 2)',
      );
      expect(
        makeEvent(validationIssues: null).toString(),
        'TranslationValidatedEvent(versionId: v1, status: translated, '
        'by: validator, issues: 0)',
      );
    });
  });

  group('TranslationDeletedEvent', () {
    TranslationDeletedEvent makeEvent() => TranslationDeletedEvent(
          versionId: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl1',
          deletedBy: 'user',
          reason: 'obsolete',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.deletedBy, 'user');
      expect(event.reason, 'obsolete');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes deletedBy and reason', () {
      expect(
        makeEvent().toString(),
        'TranslationDeletedEvent(versionId: v1, by: user, reason: obsolete)',
      );
    });
  });

  group('TranslationStatusChangedEvent', () {
    TranslationStatusChangedEvent makeEvent({String? changedBy}) =>
        TranslationStatusChangedEvent(
          versionId: 'v1',
          unitId: 'u1',
          oldStatus: 'pending',
          newStatus: 'translated',
          changedBy: changedBy,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent(changedBy: 'user');
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.oldStatus, 'pending');
      expect(event.newStatus, 'translated');
      expect(event.changedBy, 'user');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes transition and changedBy or system', () {
      expect(
        makeEvent(changedBy: 'user').toString(),
        'TranslationStatusChangedEvent(versionId: v1, '
        'pending -> translated, by: user)',
      );
      expect(
        makeEvent(changedBy: null).toString(),
        'TranslationStatusChangedEvent(versionId: v1, '
        'pending -> translated, by: system)',
      );
    });
  });

  group('TranslationQualityIssueDetectedEvent', () {
    TranslationQualityIssueDetectedEvent makeEvent({
      List<String> issues = const ['missing variable', 'markup mismatch'],
      bool requiresReview = true,
    }) =>
        TranslationQualityIssueDetectedEvent(
          versionId: 'v1',
          unitId: 'u1',
          issues: issues,
          requiresReview: requiresReview,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.issues, ['missing variable', 'markup mismatch']);
      expect(event.requiresReview, isTrue);
    });

    test('issueCount', () {
      expect(makeEvent().issueCount, 2);
      expect(makeEvent(issues: const []).issueCount, 0);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes issue count and requiresReview', () {
      expect(
        makeEvent().toString(),
        'TranslationQualityIssueDetectedEvent(versionId: v1, issues: 2, '
        'requiresReview: true)',
      );
    });
  });
}
