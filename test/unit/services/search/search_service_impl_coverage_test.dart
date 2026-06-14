import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common/src/exception.dart' show SqfliteDatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/search/models/search_exceptions.dart';
import 'package:twmt/services/search/models/search_result.dart';
import 'package:twmt/services/search/search_service_impl.dart';

/// Line-coverage tests for [SearchServiceImpl].
///
/// The service reads `DatabaseService.database` (a static getter) and runs
/// raw FTS5 SQL through it, then maps rows to [SearchResult] objects. These
/// tests inject a mocktail [Database] via [DatabaseService.setDatabase] so we
/// can drive every branch deterministically: each search scope, the empty
/// query guard, result mapping (matched-field detection, timestamp parsing,
/// context extraction, highlighting), pagination passthrough, no-result sets,
/// and both the `DatabaseException` and generic-`catch` error branches.
class _MockDatabase extends Mock implements Database {}

void main() {
  late _MockDatabase db;
  late SearchServiceImpl service;

  setUpAll(() {
    registerFallbackValue(<Object?>[]);
  });

  setUp(() {
    db = _MockDatabase();
    DatabaseService.setDatabase(db);
    service = SearchServiceImpl();
  });

  tearDown(() {
    DatabaseService.resetTestDatabase();
  });

  // Stub the single-arg rawQuery(sql) call the service issues.
  void stubRows(List<Map<String, Object?>> rows) {
    when(() => db.rawQuery(any())).thenAnswer((_) async => rows);
  }

  void stubThrow(Object error) {
    when(() => db.rawQuery(any())).thenThrow(error);
  }

  // A DatabaseException is the only error type caught specifically; build a
  // concrete instance (the base class is abstract).
  SqfliteDatabaseException dbException() =>
      SqfliteDatabaseException('boom', null);

  group('searchTranslationUnits', () {
    test('maps a full row including key/source/timestamps and ranking',
        () async {
      stubRows([
        {
          'id': 'u1',
          'project_id': 'p1',
          'project_name': 'Project One',
          'key': 'unit.key.one',
          'source_text': 'heavy cavalry charge bonus',
          'file_name': 'units.loc',
          'highlighted': '<mark>cavalry</mark>',
          'rank': -2.5,
          'created_at': 1700000000000,
          'updated_at': 1700000001000,
        },
      ]);

      final result =
          await service.searchTranslationUnits('cavalry', limit: 10, offset: 0);

      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.id, 'u1');
      expect(r.type, SearchResultType.translationUnit);
      expect(r.projectId, 'p1');
      expect(r.projectName, 'Project One');
      expect(r.key, 'unit.key.one');
      expect(r.matchedField, 'key'); // _detectMatchedField: key present first
      expect(r.highlightedText, '<mark>cavalry</mark>');
      // rank negated: -(-2.5) = 2.5
      expect(r.relevanceScore, 2.5);
      // context is extracted around the (case-insensitive) match
      expect(r.context, contains('cavalry'));
      expect(r.createdAt, isNotNull);
      expect(r.updatedAt, isNotNull);
    });

    test('null rank/highlight default and matched field falls back to source',
        () async {
      stubRows([
        {
          'id': 'u2',
          'project_id': null,
          'project_name': null,
          'key': null, // no key -> _detectMatchedField falls to source_text
          'source_text': 'archers volley',
          'file_name': null,
          'highlighted': null, // -> '' default
          'rank': null, // -> 0.0 -> negated 0.0
          'created_at': null, // _parseTimestamp(null) -> null
          'updated_at': 'not-an-int', // non-int -> null
        },
      ]);

      final result = await service.searchTranslationUnits('archers');

      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.matchedField, 'source_text');
      expect(r.highlightedText, '');
      expect(r.relevanceScore, 0.0);
      expect(r.createdAt, isNull);
      expect(r.updatedAt, isNull);
    });

    test('empty (whitespace) query short-circuits with InvalidSearchQuery',
        () async {
      final result = await service.searchTranslationUnits('   ');
      expect(result.isErr, isTrue);
      expect(result.error, isA<InvalidSearchQueryException>());
      verifyNever(() => db.rawQuery(any()));
    });

    test('no rows yields an empty Ok list', () async {
      stubRows([]);
      final result = await service.searchTranslationUnits('zzz');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('DatabaseException maps to SearchDatabaseException', () async {
      stubThrow(dbException());
      final result = await service.searchTranslationUnits('cavalry');
      expect(result.isErr, isTrue);
      expect(result.error, isA<SearchDatabaseException>());
    });

    test('generic error maps to SearchDatabaseException', () async {
      stubThrow(StateError('unexpected'));
      final result = await service.searchTranslationUnits('cavalry');
      expect(result.isErr, isTrue);
      expect(result.error, isA<SearchDatabaseException>());
    });

    test('filter + pagination args are accepted (offset > 0)', () async {
      stubRows([]);
      final result = await service.searchTranslationUnits(
        'cavalry',
        filter: const SearchFilter(projectIds: ['p1']),
        limit: 5,
        offset: 5,
      );
      expect(result.isOk, isTrue);
    });
  });

  group('searchTranslationVersions', () {
    test('maps translated text, language, status and negated rank', () async {
      stubRows([
        {
          'id': 'v1',
          'project_id': 'p1',
          'project_name': 'Proj',
          'language_code': 'fr',
          'language_name': 'French',
          'key': 'k1',
          'source_text': 'cavalry',
          'translated_text': 'cavalerie lourde',
          'status': 'translated',
          'highlighted': '<mark>cavalerie</mark>',
          'rank': -1.0,
          'created_at': 1700000000000,
          'updated_at': 1700000002000,
        },
      ]);

      final result = await service.searchTranslationVersions(
        'cavalerie',
        filter: const SearchFilter(languageCodes: ['fr']),
        limit: 10,
      );

      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.type, SearchResultType.translationVersion);
      expect(r.languageCode, 'fr');
      expect(r.languageName, 'French');
      expect(r.translatedText, 'cavalerie lourde');
      expect(r.matchedField, 'translated_text');
      expect(r.status, 'translated');
      expect(r.relevanceScore, 1.0);
      expect(r.context, contains('cavalerie'));
    });

    test('empty query short-circuits', () async {
      final result = await service.searchTranslationVersions('');
      expect(result.isErr, isTrue);
      expect(result.error, isA<InvalidSearchQueryException>());
    });

    test('DatabaseException branch', () async {
      stubThrow(dbException());
      final result = await service.searchTranslationVersions('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });

    test('generic error branch', () async {
      stubThrow(Exception('weird'));
      final result = await service.searchTranslationVersions('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });
  });

  group('searchTranslationMemory', () {
    test('maps TM row with target language and last_used_at', () async {
      stubRows([
        {
          'id': 'tm1',
          'target_language': 'de',
          'source_text': 'cavalry unit',
          'target_text': 'Kavallerieeinheit',
          'key': null,
          'translated_text': null,
          'highlighted': '<mark>Kavallerie</mark>',
          'rank': -3.0,
          'created_at': 1700000000000,
          'last_used_at': 1700000005000,
        },
      ]);

      final result = await service.searchTranslationMemory(
        'cavalry',
        targetLanguage: 'de',
        limit: 20,
        offset: 0,
      );

      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.type, SearchResultType.translationMemory);
      expect(r.languageCode, 'de');
      expect(r.translatedText, 'Kavallerieeinheit');
      // _detectMatchedField: key null, source_text present -> 'source_text'
      expect(r.matchedField, 'source_text');
      expect(r.relevanceScore, 3.0);
      expect(r.updatedAt, isNotNull); // from last_used_at
    });

    test('matched field unknown when key/source/translated all null',
        () async {
      stubRows([
        {
          'id': 'tm2',
          'target_language': 'de',
          'source_text': null,
          'target_text': 'X',
          'key': null,
          'translated_text': null,
          'highlighted': null,
          'rank': null,
          'created_at': null,
          'last_used_at': null,
        },
      ]);

      final result = await service.searchTranslationMemory('cavalry');
      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.matchedField, 'unknown');
      expect(r.highlightedText, '');
      expect(r.context, ''); // _extractContext(null, ...) -> ''
    });

    test('empty query short-circuits', () async {
      final result = await service.searchTranslationMemory('  ');
      expect(result.error, isA<InvalidSearchQueryException>());
    });

    test('DatabaseException branch', () async {
      stubThrow(dbException());
      final result = await service.searchTranslationMemory('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });

    test('generic error branch', () async {
      stubThrow(ArgumentError('bad'));
      final result = await service.searchTranslationMemory('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });
  });

  group('searchGlossary', () {
    test('maps glossary row with highlight and category', () async {
      stubRows([
        {
          'id': 'g1',
          'term': 'Cavalry',
          'translation': 'Cavalerie',
          'category': 'Military',
          'notes': 'mounted troops',
          'created_at': 1700000000000,
          'updated_at': 1700000001000,
        },
      ]);

      final result = await service.searchGlossary(
        'cavalry',
        glossaryId: 'gl1',
        category: 'Military',
        limit: 10,
      );

      expect(result.isOk, isTrue);
      final r = result.value.single;
      expect(r.type, SearchResultType.glossaryEntry);
      expect(r.sourceText, 'Cavalry');
      expect(r.translatedText, 'Cavalerie');
      expect(r.matchedField, 'term');
      expect(r.category, 'Military');
      expect(r.context, 'mounted troops'); // notes
      expect(r.relevanceScore, 1.0); // fixed for LIKE queries
      // _highlightText wraps the (case-insensitive) match in <mark>
      expect(r.highlightedText, contains('<mark>'));
    });

    test('null term produces empty highlight', () async {
      stubRows([
        {
          'id': 'g2',
          'term': null,
          'translation': null,
          'category': null,
          'notes': null,
          'created_at': null,
          'updated_at': null,
        },
      ]);

      final result = await service.searchGlossary('cavalry');
      expect(result.isOk, isTrue);
      expect(result.value.single.highlightedText, '');
    });

    test('empty query short-circuits', () async {
      final result = await service.searchGlossary('');
      expect(result.error, isA<InvalidSearchQueryException>());
    });

    test('DatabaseException branch', () async {
      stubThrow(dbException());
      final result = await service.searchGlossary('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });

    test('generic error branch', () async {
      stubThrow(StateError('x'));
      final result = await service.searchGlossary('cavalry');
      expect(result.error, isA<SearchDatabaseException>());
    });
  });

  group('searchAll', () {
    test('merges, ranks (desc) and paginates across sources', () async {
      // All three sub-searches issue rawQuery(sql); return distinct rows by
      // matching on the SQL text so the merged ranking has a known order.
      when(() => db.rawQuery(any())).thenAnswer((invocation) async {
        final sql = invocation.positionalArguments.first as String;
        if (sql.contains('translation_units_fts')) {
          return [
            {
              'id': 'u1',
              'project_id': 'p1',
              'project_name': 'P',
              'key': 'k',
              'source_text': 'alpha',
              'file_name': null,
              'highlighted': '',
              'rank': -5.0, // best -> relevance 5.0
              'created_at': null,
              'updated_at': null,
            },
          ];
        }
        if (sql.contains('translation_versions_fts')) {
          return [
            {
              'id': 'v1',
              'project_id': 'p1',
              'project_name': 'P',
              'language_code': 'fr',
              'language_name': 'French',
              'key': 'k',
              'source_text': 'alpha',
              'translated_text': 'alpha-fr',
              'status': 'translated',
              'highlighted': '',
              'rank': -1.0, // relevance 1.0
              'created_at': null,
              'updated_at': null,
            },
          ];
        }
        // translation_memory
        return [
          {
            'id': 'tm1',
            'target_language': 'de',
            'source_text': 'alpha',
            'target_text': 'alpha-de',
            'key': null,
            'translated_text': null,
            'highlighted': '',
            'rank': -3.0, // relevance 3.0
            'created_at': null,
            'last_used_at': null,
          },
        ];
      });

      final result = await service.searchAll('alpha', limit: 10);
      expect(result.isOk, isTrue);
      final ids = result.value.map((r) => r.id).toList();
      // Sorted by relevance desc: 5.0 (u1), 3.0 (tm1), 1.0 (v1)
      expect(ids, ['u1', 'tm1', 'v1']);
    });

    test('offset slices the merged window', () async {
      when(() => db.rawQuery(any())).thenAnswer((invocation) async {
        final sql = invocation.positionalArguments.first as String;
        if (sql.contains('translation_units_fts')) {
          return [
            for (var i = 0; i < 3; i++)
              {
                'id': 'u$i',
                'project_id': 'p',
                'project_name': 'P',
                'key': 'k$i',
                'source_text': 'alpha',
                'file_name': null,
                'highlighted': '',
                'rank': -(10.0 - i), // u0 best, u2 worst
                'created_at': null,
                'updated_at': null,
              },
          ];
        }
        return <Map<String, Object?>>[];
      });

      final page2 = await service.searchAll('alpha', limit: 1, offset: 1);
      expect(page2.isOk, isTrue);
      expect(page2.value.single.id, 'u1');
    });

    test('empty query short-circuits before any query', () async {
      final result = await service.searchAll('   ');
      expect(result.error, isA<InvalidSearchQueryException>());
      verifyNever(() => db.rawQuery(any()));
    });

    test('failing sub-searches are skipped; outer stays Ok', () async {
      // Every sub-query throws a DatabaseException -> each returns an Err,
      // which searchAll filters out, leaving an empty merged Ok list.
      stubThrow(dbException());
      final result = await service.searchAll('alpha');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('validateFtsQuery', () {
    test('returns Ok(true) for a valid query', () async {
      final result = await service.validateFtsQuery('cavalry AND unit');
      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('ArgumentError (unbalanced quotes) maps to FtsQuerySyntaxException',
        () async {
      final result = await service.validateFtsQuery('cavalry "unit');
      expect(result.isErr, isTrue);
      expect(result.error, isA<FtsQuerySyntaxException>());
    });

    test('empty query throws ArgumentError -> FtsQuerySyntaxException',
        () async {
      final result = await service.validateFtsQuery('   ');
      expect(result.isErr, isTrue);
      expect(result.error, isA<FtsQuerySyntaxException>());
    });
  });
}
