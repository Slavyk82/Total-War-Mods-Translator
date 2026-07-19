import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project_language.dart';

void main() {
  ProjectLanguage makeLanguage({
    String id = 'pl-1',
    String projectId = 'p-1',
    String languageId = 'lang_fr',
    ProjectLanguageStatus status = ProjectLanguageStatus.pending,
    double progressPercent = 0.0,
    int createdAt = 100,
    int updatedAt = 200,
  }) {
    return ProjectLanguage(
      id: id,
      projectId: projectId,
      languageId: languageId,
      status: status,
      progressPercent: progressPercent,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('ProjectLanguageStatus enum', () {
    test('has all four values', () {
      expect(ProjectLanguageStatus.values, hasLength(4));
      expect(
        ProjectLanguageStatus.values,
        containsAll([
          ProjectLanguageStatus.pending,
          ProjectLanguageStatus.translating,
          ProjectLanguageStatus.completed,
          ProjectLanguageStatus.error,
        ]),
      );
    });
  });

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const language = ProjectLanguage(
        id: 'id',
        projectId: 'p',
        languageId: 'l',
        createdAt: 1,
        updatedAt: 2,
      );
      expect(language.status, ProjectLanguageStatus.pending);
      expect(language.progressPercent, 0.0);
    });
  });

  group('status boolean getters', () {
    test('isPending', () {
      expect(
        makeLanguage(status: ProjectLanguageStatus.pending).isPending,
        isTrue,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.translating).isPending,
        isFalse,
      );
    });

    test('isTranslating and isActive', () {
      final translating =
          makeLanguage(status: ProjectLanguageStatus.translating);
      expect(translating.isTranslating, isTrue);
      expect(translating.isActive, isTrue);

      final pending = makeLanguage(status: ProjectLanguageStatus.pending);
      expect(pending.isTranslating, isFalse);
      expect(pending.isActive, isFalse);
    });

    test('isCompleted', () {
      expect(
        makeLanguage(status: ProjectLanguageStatus.completed).isCompleted,
        isTrue,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.pending).isCompleted,
        isFalse,
      );
    });

    test('hasError', () {
      expect(
        makeLanguage(status: ProjectLanguageStatus.error).hasError,
        isTrue,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.pending).hasError,
        isFalse,
      );
    });

    test('isFinished is true for completed/error only', () {
      expect(
        makeLanguage(status: ProjectLanguageStatus.completed).isFinished,
        isTrue,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.error).isFinished,
        isTrue,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.pending).isFinished,
        isFalse,
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.translating).isFinished,
        isFalse,
      );
    });
  });

  group('progress getters', () {
    test('progressPercentInt rounds', () {
      expect(makeLanguage(progressPercent: 45.4).progressPercentInt, 45);
      expect(makeLanguage(progressPercent: 45.5).progressPercentInt, 46);
    });

    test('hasStarted', () {
      expect(makeLanguage(progressPercent: 0).hasStarted, isFalse);
      expect(makeLanguage(progressPercent: 0.1).hasStarted, isTrue);
    });

    test('isPartiallyComplete', () {
      expect(makeLanguage(progressPercent: 0).isPartiallyComplete, isFalse);
      expect(makeLanguage(progressPercent: 50).isPartiallyComplete, isTrue);
      expect(makeLanguage(progressPercent: 100).isPartiallyComplete, isFalse);
    });

    test('isFullyComplete', () {
      expect(makeLanguage(progressPercent: 99.9).isFullyComplete, isFalse);
      expect(makeLanguage(progressPercent: 100).isFullyComplete, isTrue);
    });

    test('progressDisplay formats rounded percent', () {
      expect(makeLanguage(progressPercent: 45.6).progressDisplay, '46%');
    });
  });

  group('statusDisplay', () {
    test('maps each status', () {
      expect(
        makeLanguage(status: ProjectLanguageStatus.pending).statusDisplay,
        'Pending',
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.translating).statusDisplay,
        'Translating',
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.completed).statusDisplay,
        'Completed',
      );
      expect(
        makeLanguage(status: ProjectLanguageStatus.error).statusDisplay,
        'Error',
      );
    });
  });

  group('copyWith', () {
    final base = makeLanguage(
      id: 'a',
      projectId: 'p',
      languageId: 'l',
      status: ProjectLanguageStatus.translating,
      progressPercent: 42.0,
      createdAt: 100,
      updatedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(languageId: 'z').languageId, 'z');
      expect(
        base.copyWith(status: ProjectLanguageStatus.error).status,
        ProjectLanguageStatus.error,
      );
      expect(base.copyWith(progressPercent: 99.0).progressPercent, 99.0);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(progressPercent: 50.0);
      expect(copy.id, base.id);
      expect(copy.projectId, base.projectId);
      expect(copy.languageId, base.languageId);
      expect(copy.status, base.status);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('JSON', () {
    final full = makeLanguage(
      id: 'a',
      projectId: 'p',
      languageId: 'l',
      status: ProjectLanguageStatus.translating,
      progressPercent: 42.5,
      createdAt: 100,
      updatedAt: 200,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['project_id'], 'p');
      expect(json['language_id'], 'l');
      expect(json['status'], 'translating');
      expect(json['progress_percent'], 42.5);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          ProjectLanguage.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = ProjectLanguage.fromJson({
        'id': 'a',
        'project_id': 'p',
        'language_id': 'l',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.status, ProjectLanguageStatus.pending);
      expect(decoded.progressPercent, 0.0);
    });

    test('fromJson decodes each status value', () {
      for (final entry in {
        'pending': ProjectLanguageStatus.pending,
        'translating': ProjectLanguageStatus.translating,
        'completed': ProjectLanguageStatus.completed,
        'error': ProjectLanguageStatus.error,
      }.entries) {
        final decoded = ProjectLanguage.fromJson({
          'id': 'a',
          'project_id': 'p',
          'language_id': 'l',
          'created_at': 1,
          'updated_at': 2,
          'status': entry.key,
        });
        expect(decoded.status, entry.value);
      }
    });
  });

  group('equality and hashCode', () {
    final a = makeLanguage(
      id: 'a',
      status: ProjectLanguageStatus.translating,
      progressPercent: 42.0,
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
      expect(a == a.copyWith(languageId: 'z'), isFalse);
      expect(a == a.copyWith(status: ProjectLanguageStatus.error), isFalse);
      expect(a == a.copyWith(progressPercent: 99.0), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, projectId, languageId, status and progress', () {
      final language = makeLanguage(
        id: 'a',
        projectId: 'p',
        languageId: 'l',
        status: ProjectLanguageStatus.translating,
        progressPercent: 42.5,
      );
      expect(
        language.toString(),
        'ProjectLanguage(id: a, projectId: p, languageId: l, '
        'status: ProjectLanguageStatus.translating, progress: 43%)',
      );
    });
  });
}
