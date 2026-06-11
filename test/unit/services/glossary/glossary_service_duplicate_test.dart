import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_service_impl.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

import '../../../helpers/test_database.dart';

/// Duplicate-detection tests for GlossaryServiceImpl.addEntry, proving the
/// check honors case_sensitive semantics. The rules mirror the migration's
/// dedup logic (GlossaryMigrationService._mergeEntriesDedup) and the schema's
/// UNIQUE(glossary_id, target_language_code, source_term, case_sensitive):
/// - entries only conflict within the same case_sensitive group;
/// - case-sensitive entries conflict only on an exact (trimmed) match;
/// - case-insensitive entries conflict on LOWER(TRIM()).
void main() {
  late Database db;
  late GlossaryRepository repository;
  late GlossaryServiceImpl glossaryService;

  const glossaryId = 'g-dup';
  const targetLanguageCode = 'fr';

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = GlossaryRepository(logger: LoggingService.instance);
    glossaryService = GlossaryServiceImpl(
      repository: repository,
      logger: LoggingService.instance,
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await repository.insertGlossary(Glossary(
      id: glossaryId,
      name: 'Duplicate semantics',
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
      createdAt: now,
      updatedAt: now,
    ));
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<dynamic> add(String sourceTerm, {required bool caseSensitive}) {
    return glossaryService.addEntry(
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm,
      targetTerm: 'Attaque',
      caseSensitive: caseSensitive,
    );
  }

  group('GlossaryServiceImpl.addEntry duplicate detection', () {
    test(
        "case-sensitive 'ATTACK' is allowed when case-sensitive 'Attack' "
        'exists', () async {
      expect((await add('Attack', caseSensitive: true)).isOk, isTrue);

      final result = await add('ATTACK', caseSensitive: true);

      expect(result.isOk, isTrue,
          reason: 'case-sensitive entries only conflict on an exact '
              '(trimmed) match');
    });

    test(
        "case-sensitive 'Attack' (and ' Attack ') is a duplicate of "
        "case-sensitive 'Attack'", () async {
      expect((await add('Attack', caseSensitive: true)).isOk, isTrue);

      final exact = await add('Attack', caseSensitive: true);
      expect(exact.isErr, isTrue);
      expect(exact.error, isA<DuplicateGlossaryEntryException>());

      final padded = await add(' Attack ', caseSensitive: true);
      expect(padded.isErr, isTrue);
      expect(padded.error, isA<DuplicateGlossaryEntryException>());
    });

    test(
        "case-insensitive 'ATTACK' is a duplicate of case-insensitive "
        "'attack'", () async {
      expect((await add('attack', caseSensitive: false)).isOk, isTrue);

      final result = await add('ATTACK', caseSensitive: false);

      expect(result.isErr, isTrue);
      expect(result.error, isA<DuplicateGlossaryEntryException>());
    });

    test(
        "case-sensitive 'Attack' is allowed when case-insensitive 'attack' "
        'exists (different case_sensitive group)', () async {
      expect((await add('attack', caseSensitive: false)).isOk, isTrue);

      final result = await add('Attack', caseSensitive: true);

      expect(result.isOk, isTrue,
          reason: 'migration semantics: the UNIQUE key includes '
              'case_sensitive, so groups never conflict with each other');
    });

    test(
        "case-insensitive 'attack' is allowed when case-sensitive 'Attack' "
        'exists (different case_sensitive group)', () async {
      expect((await add('Attack', caseSensitive: true)).isOk, isTrue);

      final result = await add('attack', caseSensitive: false);

      expect(result.isOk, isTrue,
          reason: 'migration semantics: the UNIQUE key includes '
              'case_sensitive, so groups never conflict with each other');
    });
  });
}
