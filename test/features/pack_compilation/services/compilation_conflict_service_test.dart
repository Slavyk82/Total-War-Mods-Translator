// Regression coverage for [CompilationConflictService] translation-conflict
// detection (audit finding F5).
//
// Two projects sharing a key with IDENTICAL source text but DIFFERENT
// translations used to be silently auto-merged: `_detectConflicts` skipped
// every same-source pair, so `CompilationConflictType.translationConflict`
// was never produced and pack compilation resolved the key last-writer-wins,
// silently overwriting one project's translation. Same source AND same
// translation (or a missing translation on one side) stays auto-mergeable;
// different source text stays a key collision.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/services/compilation_conflict_service.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';

import '../../../helpers/test_database.dart';

const _languageId = 'lang-fr';

void main() {
  late Database db;
  late CompilationConflictService service;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    service = CompilationConflictService(TranslationUnitRepository());
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  /// Seed a project with its [_languageId] project_language row.
  Future<void> seedProject(String projectId) async {
    await db.insert('projects', {
      'id': projectId,
      'name': 'Project $projectId',
      'game_installation_id': 'install-wh3',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('project_languages', {
      'id': 'pl-$projectId',
      'project_id': projectId,
      'language_id': _languageId,
      'status': 'pending',
      'progress_percent': 0,
      'created_at': 0,
      'updated_at': 0,
    });
  }

  /// Seed a translation unit + its translation version for [projectId].
  Future<void> seedUnit({
    required String projectId,
    required String key,
    required String sourceText,
    String? translatedText,
  }) async {
    final unitId = 'unit-$projectId-$key';
    await db.insert('translation_units', {
      'id': unitId,
      'project_id': projectId,
      'key': key,
      'source_text': sourceText,
      'is_obsolete': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('translation_versions', {
      'id': 'tv-$projectId-$key',
      'unit_id': unitId,
      'project_language_id': 'pl-$projectId',
      'translated_text': translatedText,
      'status': 'translated',
      'created_at': 0,
      'updated_at': 0,
    });
  }

  test(
      'same key, same source, different translations is reported as a '
      'translationConflict (not silently merged)', () async {
    await seedProject('p1');
    await seedProject('p2');
    await seedUnit(
      projectId: 'p1',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Épée de Khaine',
    );
    await seedUnit(
      projectId: 'p2',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Lame de Khaine',
    );

    final result = await service.analyzeConflicts(
      projectIds: ['p1', 'p2'],
      languageId: _languageId,
    );

    expect(result.isOk, isTrue, reason: 'analysis must succeed: $result');
    final analysis = result.value;

    expect(analysis.conflicts, hasLength(1),
        reason: 'two projects translating the same source differently must '
            'surface a conflict instead of last-writer-wins at compile time');
    final conflict = analysis.conflicts.single;
    expect(conflict.conflictType, CompilationConflictType.translationConflict);
    expect(conflict.key, 'shared_key');
    expect(conflict.canAutoResolve, isFalse,
        reason: 'translation conflicts need a user decision and must gate '
            'compilation like key collisions do');
    expect(
      {conflict.firstEntry.translatedText, conflict.secondEntry.translatedText},
      {'Épée de Khaine', 'Lame de Khaine'},
    );
    expect(analysis.summary.translationConflictCount, 1);
    expect(analysis.summary.keyCollisionCount, 0);
    expect(analysis.summary.totalCount, 1);
  });

  test('same key, same source, same translation stays auto-mergeable',
      () async {
    await seedProject('p1');
    await seedProject('p2');
    await seedUnit(
      projectId: 'p1',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Épée de Khaine',
    );
    await seedUnit(
      projectId: 'p2',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Épée de Khaine',
    );

    final result = await service.analyzeConflicts(
      projectIds: ['p1', 'p2'],
      languageId: _languageId,
    );

    expect(result.isOk, isTrue);
    expect(result.value.conflicts, isEmpty);
    expect(result.value.summary.totalCount, 0);
  });

  test(
      'same key, same source, one side untranslated (null/empty) stays '
      'auto-mergeable', () async {
    await seedProject('p1');
    await seedProject('p2');
    await seedProject('p3');
    await seedUnit(
      projectId: 'p1',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Épée de Khaine',
    );
    await seedUnit(
      projectId: 'p2',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: null,
    );
    await seedUnit(
      projectId: 'p3',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: '',
    );

    final result = await service.analyzeConflicts(
      projectIds: ['p1', 'p2', 'p3'],
      languageId: _languageId,
    );

    expect(result.isOk, isTrue);
    expect(result.value.conflicts, isEmpty,
        reason: 'an untranslated side has nothing to conflict with — the '
            'translated side wins automatically');
  });

  test(
      'same key with different source text stays a '
      'keyCollisionDifferentSource conflict', () async {
    await seedProject('p1');
    await seedProject('p2');
    await seedUnit(
      projectId: 'p1',
      key: 'shared_key',
      sourceText: 'Sword of Khaine',
      translatedText: 'Épée de Khaine',
    );
    await seedUnit(
      projectId: 'p2',
      key: 'shared_key',
      sourceText: 'Widowmaker',
      translatedText: 'Faiseuse de veuves',
    );

    final result = await service.analyzeConflicts(
      projectIds: ['p1', 'p2'],
      languageId: _languageId,
    );

    expect(result.isOk, isTrue);
    final analysis = result.value;
    expect(analysis.conflicts, hasLength(1));
    expect(
      analysis.conflicts.single.conflictType,
      CompilationConflictType.keyCollisionDifferentSource,
    );
    expect(analysis.summary.keyCollisionCount, 1);
    expect(analysis.summary.translationConflictCount, 0);
  });
}
