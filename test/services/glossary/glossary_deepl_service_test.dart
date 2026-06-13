import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

// Characterisation tests for GlossaryDeepLService.
//
// The service's HTTP client (Dio) IS injectable via the constructor, so we mock
// Dio directly and feed canned Response/DioException objects. This lets us drive
// every create/list/delete happy + failure path without any real network access.
//
// GlossaryRepository is a concrete class (no abstract interface) but mocktail can
// still subclass it. FlutterSecureStorage is mocked to control the API key gate.

class _MockDio extends Mock implements Dio {}

class _MockRepo extends Mock implements GlossaryRepository {}

class _MockStorage extends Mock implements FlutterSecureStorage {}

Glossary _glossary({String id = 'g1', String name = 'MyGloss'}) => Glossary(
      id: id,
      name: name,
      gameCode: 'warhammer3',
      targetLanguageId: 'fr',
      createdAt: 1,
      updatedAt: 1,
    );

GlossaryEntry _entry({
  String source = 'Sword',
  String target = 'Epee',
  String lang = 'fr',
}) =>
    GlossaryEntry(
      id: 'e-$source',
      glossaryId: 'g1',
      targetLanguageCode: lang,
      sourceTerm: source,
      targetTerm: target,
      createdAt: 1,
      updatedAt: 1,
    );

Response<dynamic> _resp(dynamic body, {int status = 200, String path = '/glossaries'}) =>
    Response<dynamic>(
      data: body,
      statusCode: status,
      requestOptions: RequestOptions(path: path),
    );

DioException _dioErr({
  int? statusCode,
  dynamic data,
  DioExceptionType type = DioExceptionType.badResponse,
  String? message,
}) {
  final reqOpts = RequestOptions(path: '/glossaries');
  return DioException(
    requestOptions: reqOpts,
    type: type,
    message: message,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            data: data,
            statusCode: statusCode,
            requestOptions: reqOpts,
          ),
  );
}

/// Dio.options is mutated by _updateBaseUrl(); stub it so the mock doesn't throw.
void _stubOptions(_MockDio dio) {
  when(() => dio.options)
      .thenReturn(BaseOptions(baseUrl: 'https://api-free.deepl.com/v2'));
}

void _stubApiKey(_MockStorage storage, String? key) {
  when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => key);
}

void main() {
  late _MockDio dio;
  late _MockRepo repo;
  late _MockStorage storage;
  late GlossaryDeepLService service;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/glossaries'));
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    repo = _MockRepo();
    storage = _MockStorage();
    _stubOptions(dio);
    service = GlossaryDeepLService(
      glossaryRepository: repo,
      secureStorage: storage,
      dio: dio,
    );
  });

  // --------------------------------------------------------------------------
  // createDeepLGlossary
  // --------------------------------------------------------------------------
  group('createDeepLGlossary', () {
    test('returns GlossaryNotFoundException when glossary is missing', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<GlossaryNotFoundException>());
      verifyNever(() => dio.post(any(), data: any(named: 'data'), options: any(named: 'options')));
    });

    test('returns InvalidGlossaryDataException when there are no entries',
        () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => <GlossaryEntry>[]);

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<InvalidGlossaryDataException>());
    });

    test('returns DeepLGlossaryException when API key is empty', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      _stubApiKey(storage, ''); // empty key

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isErr, isTrue);
      final err = result.error as DeepLGlossaryException;
      expect(err.message, contains('not configured'));
    });

    test('treats null stored key as empty (early return)', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      _stubApiKey(storage, null);

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.error, isA<DeepLGlossaryException>());
    });

    test('happy path: posts payload and returns DeepL glossary id (FREE key)',
        () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry(), _entry(source: 'Shield', target: 'Bouclier')]);
      _stubApiKey(storage, 'free-key:fx');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _resp({'glossary_id': 'deepl-123'}));

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isOk, isTrue);
      expect(result.value, 'deepl-123');

      // Verify the posted payload shape + endpoint.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/glossaries');
      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['name'], 'MyGloss_en_fr');
      expect(payload['source_lang'], 'EN');
      expect(payload['target_lang'], 'FR');
      expect(payload['entries_format'], 'tsv');
      expect(payload['entries'], 'Sword\tEpee\nShield\tBouclier\n');

      // FREE key (':fx') -> free base url applied.
      expect(dio.options.baseUrl, contains('api-free.deepl.com'));
    });

    test('PRO key updates base url to api.deepl.com', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      _stubApiKey(storage, 'pro-key-no-suffix');
      when(() => dio.post(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async => _resp({'glossary_id': 'deepl-pro'}));

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.value, 'deepl-pro');
      expect(dio.options.baseUrl, 'https://api.deepl.com/v2');
    });

    test('maps DioException (403) to DeepLGlossaryException', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      _stubApiKey(storage, 'key:fx');
      when(() => dio.post(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_dioErr(statusCode: 403, data: {'message': 'bad key'}));

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      final err = result.error as DeepLGlossaryException;
      expect(err.statusCode, 403);
      expect(err.message, contains('Invalid API key'));
      expect(err.message, contains('bad key'));
    });

    test('wraps non-Dio exception (e.g. response not a Map) in '
        'DeepLGlossaryException', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      _stubApiKey(storage, 'key:fx');
      // Response data is a String -> the `as Map` cast throws a generic error.
      when(() => dio.post(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async => _resp('not-a-map'));

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      final err = result.error as DeepLGlossaryException;
      expect(err.message, contains('Failed to create DeepL glossary'));
    });

    test('wraps a repository throw in DeepLGlossaryException', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenThrow(StateError('db down'));

      final result = await service.createDeepLGlossary(
        glossaryId: 'g1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.error, isA<DeepLGlossaryException>());
    });
  });

  // --------------------------------------------------------------------------
  // deleteDeepLGlossary
  // --------------------------------------------------------------------------
  group('deleteDeepLGlossary', () {
    test('returns error when API key missing', () async {
      _stubApiKey(storage, '');

      final result = await service.deleteDeepLGlossary('deepl-123');

      expect(result.isErr, isTrue);
      final err = result.error as DeepLGlossaryException;
      expect(err.message, contains('not configured'));
      verifyNever(() => dio.delete(any(), options: any(named: 'options')));
    });

    test('happy path: issues DELETE and returns Ok(null)', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.delete(any(), options: any(named: 'options')))
          .thenAnswer((_) async => _resp(null, status: 204));

      final result = await service.deleteDeepLGlossary('deepl-123');

      expect(result.isOk, isTrue);
      final captured = verify(() => dio.delete(
            captureAny(),
            options: any(named: 'options'),
          )).captured;
      expect(captured.single, '/glossaries/deepl-123');
    });

    test('maps DioException (404) to DeepLGlossaryException', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.delete(any(), options: any(named: 'options')))
          .thenThrow(_dioErr(statusCode: 404, data: {'message': 'gone'}));

      final result = await service.deleteDeepLGlossary('deepl-123');

      final err = result.error as DeepLGlossaryException;
      expect(err.statusCode, 404);
      expect(err.message, contains('not found'));
    });

    test('wraps non-Dio throw in DeepLGlossaryException', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.delete(any(), options: any(named: 'options')))
          .thenThrow(StateError('boom'));

      final result = await service.deleteDeepLGlossary('deepl-123');

      final err = result.error as DeepLGlossaryException;
      expect(err.message, contains('Failed to delete DeepL glossary'));
    });
  });

  // --------------------------------------------------------------------------
  // listDeepLGlossaries
  // --------------------------------------------------------------------------
  group('listDeepLGlossaries', () {
    test('returns error when API key missing', () async {
      _stubApiKey(storage, '');

      final result = await service.listDeepLGlossaries();

      expect(result.isErr, isTrue);
      expect(result.error, isA<DeepLGlossaryException>());
      verifyNever(() => dio.get(any(), options: any(named: 'options')));
    });

    test('happy path: parses glossaries array', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => _resp({
          'glossaries': [
            {'glossary_id': 'a', 'name': 'GA'},
            {'glossary_id': 'b', 'name': 'GB'},
          ],
        }),
      );

      final result = await service.listDeepLGlossaries();

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(2));
      expect(result.value.first['glossary_id'], 'a');

      final captured =
          verify(() => dio.get(captureAny(), options: any(named: 'options')))
              .captured;
      expect(captured.single, '/glossaries');
    });

    test('maps DioException (456 quota) to DeepLGlossaryException', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenThrow(_dioErr(statusCode: 456, data: {'message': 'over'}));

      final result = await service.listDeepLGlossaries();

      final err = result.error as DeepLGlossaryException;
      expect(err.statusCode, 456);
      expect(err.message, contains('Quota exceeded'));
    });

    test('wraps non-Dio throw (response missing glossaries key) in '
        'DeepLGlossaryException', () async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenAnswer((_) async => _resp({'unexpected': true}));

      final result = await service.listDeepLGlossaries();

      final err = result.error as DeepLGlossaryException;
      expect(err.message, contains('Failed to list DeepL glossaries'));
    });
  });

  // --------------------------------------------------------------------------
  // _handleDioException — exercise the remaining status-code / type branches
  // via listDeepLGlossaries (GET is the simplest carrier).
  // --------------------------------------------------------------------------
  group('Dio exception mapping (all branches)', () {
    Future<DeepLGlossaryException> mapViaList(DioException ex) async {
      _stubApiKey(storage, 'key:fx');
      when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(ex);
      final result = await service.listDeepLGlossaries();
      return result.error as DeepLGlossaryException;
    }

    test('429 -> Too many requests', () async {
      final err = await mapViaList(
          _dioErr(statusCode: 429, data: {'message': 'slow down'}));
      expect(err.statusCode, 429);
      expect(err.message, contains('Too many requests'));
    });

    test('400 -> Invalid request', () async {
      final err = await mapViaList(
          _dioErr(statusCode: 400, data: {'message': 'bad'}));
      expect(err.message, contains('Invalid request'));
    });

    test('other 4xx (422) -> raw message', () async {
      final err = await mapViaList(
          _dioErr(statusCode: 422, data: {'message': 'unprocessable'}));
      expect(err.statusCode, 422);
      expect(err.message, 'unprocessable');
    });

    test('5xx -> Server error', () async {
      final err = await mapViaList(
          _dioErr(statusCode: 503, data: {'message': 'down'}));
      expect(err.message, contains('Server error'));
    });

    test('timeout type -> Request timeout', () async {
      final err = await mapViaList(_dioErr(
        type: DioExceptionType.connectionTimeout,
        message: 'timed out',
      ));
      expect(err.message, contains('Request timeout'));
      expect(err.statusCode, isNull);
    });

    test('connectionError -> Connection failed', () async {
      final err = await mapViaList(_dioErr(
        type: DioExceptionType.connectionError,
        message: 'no route',
      ));
      expect(err.message, contains('Connection failed'));
    });

    test('unknown type with no response -> Network error', () async {
      final err = await mapViaList(_dioErr(
        type: DioExceptionType.unknown,
        message: 'mystery',
      ));
      expect(err.message, contains('Network error'));
    });

    test('String response body is used directly as error message', () async {
      final err = await mapViaList(_dioErr(
        statusCode: 400,
        data: 'plain string error',
      ));
      expect(err.message, contains('plain string error'));
    });

    test('non-map/non-string response body -> "Unknown error"', () async {
      final err = await mapViaList(_dioErr(
        statusCode: 400,
        data: 12345, // neither Map nor String
      ));
      expect(err.message, contains('Unknown error'));
    });
  });

  // --------------------------------------------------------------------------
  // glossaryEntriesToDeepLTsv — pure helper
  // --------------------------------------------------------------------------
  group('glossaryEntriesToDeepLTsv', () {
    test('emits source\\ttarget\\n lines', () {
      final tsv = glossaryEntriesToDeepLTsv([
        _entry(source: 'A', target: '1'),
        _entry(source: 'B', target: '2'),
      ]);
      expect(tsv, 'A\t1\nB\t2\n');
    });

    test('skips entries with empty source or target', () {
      final tsv = glossaryEntriesToDeepLTsv([
        _entry(source: '  ', target: 'x'),
        _entry(source: 'y', target: '   '),
        _entry(source: 'keep', target: 'me'),
      ]);
      expect(tsv, 'keep\tme\n');
    });

    test('dedupes by trimmed source term (first wins)', () {
      final tsv = glossaryEntriesToDeepLTsv([
        _entry(source: 'Foo', target: 'first'),
        _entry(source: 'Foo', target: 'second'),
      ]);
      expect(tsv, 'Foo\tfirst\n');
    });

    test('escapes embedded tabs and newlines and trims', () {
      final tsv = glossaryEntriesToDeepLTsv([
        _entry(source: ' a\tb ', target: 'c\nd'),
      ]);
      expect(tsv, 'a b\tc d\n');
    });
  });
}
