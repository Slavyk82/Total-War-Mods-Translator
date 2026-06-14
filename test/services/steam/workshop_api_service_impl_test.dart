import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/workshop_api_service_impl.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';

import '../../helpers/noop_logger.dart';

// ---------------------------------------------------------------------------
// dart:io HttpClient fakes
//
// WorkshopApiServiceImpl builds its Dio client internally (private final), so
// it cannot be injected. Instead we intercept the layer Dio's IOHttpClientAdapter
// actually uses — dart:io's HttpClient — via HttpOverrides. This lets us drive
// the network/parse branches with canned responses without any real I/O.
// ---------------------------------------------------------------------------

/// Mutable canned response read by the fakes for the current test.
class _Canned {
  static int statusCode = 200;
  static Map<String, dynamic> body = const {};
  static bool throwOnConnect = false;

  static void reset() {
    statusCode = 200;
    body = const {};
    throwOnConnect = false;
  }
}

class _FakeOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 3);
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (_Canned.throwOnConnect) {
      throw const SocketException('connection refused');
    }
    return _FakeRequest();
  }

  @override
  void close({bool force = false}) {}
}

class _FakeRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    // Drain the request body so the stream completes.
    await stream.drain<void>();
  }

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    final bytes = utf8.encode(jsonEncode(_Canned.body));
    return _FakeResponse(_Canned.statusCode, Uint8List.fromList(bytes));
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

/// Dio's IOHttpClientAdapter only calls `cast()`, `headers.forEach`,
/// `statusCode`, `isRedirect`, `redirects` and `reasonPhrase` on the response,
/// so a Fake implementing just those is enough.
class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this.statusCode, this._bytes);

  final Uint8List _bytes;

  @override
  final int statusCode;

  @override
  Stream<R> cast<R>() => Stream<List<int>>.value(_bytes).cast<R>();

  @override
  String get reasonPhrase => 'OK';

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  int get contentLength => -1;
}

/// Minimal HttpHeaders that reports a JSON content-type so Dio decodes the
/// body into a Map.
class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) =>
      name.toLowerCase() == HttpHeaders.contentTypeHeader
          ? 'application/json; charset=utf-8'
          : null;

  @override
  List<String>? operator [](String name) {
    final v = value(name);
    return v == null ? null : [v];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    action(HttpHeaders.contentTypeHeader, ['application/json; charset=utf-8']);
  }
}

void main() {
  late WorkshopApiServiceImpl service;
  HttpOverrides? previous;

  setUp(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _FakeOverrides();
    _Canned.reset();
    service = WorkshopApiServiceImpl(logger: NoopLogger());
  });

  tearDown(() {
    HttpOverrides.global = previous;
  });

  // -------------------------------------------------------------------------
  // Validation / no-network branches
  // -------------------------------------------------------------------------
  group('getModInfo validation', () {
    test('rejects a non-numeric Workshop ID', () async {
      final result = await service.getModInfo(workshopId: 'abc', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
      expect((result.error as InvalidWorkshopIdException).invalidId, 'abc');
    });

    test('rejects an empty Workshop ID', () async {
      final result = await service.getModInfo(workshopId: '', appId: 1142710);

      expect(result.error, isA<InvalidWorkshopIdException>());
    });
  });

  group('getMultipleModInfo validation', () {
    test('rejects when any ID is invalid', () async {
      final result = await service.getMultipleModInfo(
        workshopIds: ['123', 'not-a-number'],
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
    });

    test('rejects more than 100 items', () async {
      final ids = List.generate(101, (i) => '$i');

      final result = await service.getMultipleModInfo(
        workshopIds: ids,
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect(result.error.message, contains('100'));
    });
  });

  group('searchMods', () {
    test('is unsupported and returns an explanatory error', () async {
      final result = await service.searchMods(query: 'orcs', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect(result.error.message, contains('Search not implemented'));
    });
  });

  group('checkForUpdates', () {
    test('returns an empty map when no mods are supplied', () async {
      final result = await service.checkForUpdates(
        modsWithTimestamps: {},
        appId: 1142710,
      );

      expect(result, isA<Ok>());
      expect(result.value, isEmpty);
    });

    test('propagates a getMultipleModInfo validation error', () async {
      final result = await service.checkForUpdates(
        modsWithTimestamps: {'not-a-number': 10},
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
    });
  });

  // -------------------------------------------------------------------------
  // Network / parse branches (driven through HttpOverrides)
  // -------------------------------------------------------------------------
  group('getModInfo over the (faked) network', () {
    test('parses a successful response into WorkshopModInfo', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {
              'result': 1,
              'publishedfileid': '123',
              'title': 'Cool Mod',
              'file_size': 123.0, // double -> _parseInt double branch
              'time_updated': 1700000000, // int branch
              'time_created': '1699000000', // String-int branch
              'subscriptions': '7.5', // String-double branch
              'tags': [
                {'tag': 'units'},
                {'tag': ''}, // filtered out
                {'no_tag': 'x'}, // -> '' -> filtered out
              ],
            }
          ]
        }
      };

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      expect(result, isA<Ok>());
      final info = (result as Ok).value as WorkshopModInfo;
      expect(info.title, 'Cool Mod');
      expect(info.workshopId, '123');
      expect(info.fileSize, 123);
      expect(info.timeUpdated, 1700000000);
      expect(info.timeCreated, 1699000000);
      expect(info.subscriptions, 7);
      expect(info.tags, ['units']);
    });

    test('defaults the title and tolerates missing numeric fields', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {'result': 1, 'publishedfileid': '123'}
          ]
        }
      };

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      final info = (result as Ok).value as WorkshopModInfo;
      expect(info.title, 'Unknown');
      expect(info.fileSize, isNull);
      expect(info.tags, isNull);
    });

    test('returns WorkshopApiException on a non-200 status', () async {
      _Canned.statusCode = 500;
      _Canned.body = const {};

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect((result.error as WorkshopApiException).statusCode, 500);
    });

    test('returns WorkshopApiException on a malformed response', () async {
      _Canned.body = const {'response': null};

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error.message, contains('Invalid API response format'));
    });

    test('returns WorkshopModNotFoundException when result != 1', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {'result': 9, 'publishedfileid': '123'}
          ]
        }
      };

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopModNotFoundException>());
    });

    test('wraps a network failure in WorkshopApiException', () async {
      _Canned.throwOnConnect = true;

      final result = await service.getModInfo(workshopId: '123', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<WorkshopApiException>());
      expect(result.error.message, contains('Network error'));
    });
  });

  group('getMultipleModInfo over the (faked) network', () {
    test('parses multiple items and skips failed ones', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {'result': 1, 'publishedfileid': '111', 'title': 'A'},
            {'result': 9, 'publishedfileid': '222'}, // skipped
            {'result': 1, 'publishedfileid': '333', 'title': 'C'},
          ]
        }
      };

      final result = await service.getMultipleModInfo(
        workshopIds: ['111', '222', '333'],
        appId: 1142710,
      );

      expect(result, isA<Ok>());
      final list = (result as Ok).value as List<WorkshopModInfo>;
      expect(list.map((m) => m.workshopId), ['111', '333']);
    });

    test('returns WorkshopApiException on a non-200 status', () async {
      _Canned.statusCode = 503;

      final result = await service.getMultipleModInfo(
        workshopIds: ['111'],
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect((result.error as WorkshopApiException).statusCode, 503);
    });

    test('returns WorkshopApiException on a malformed response', () async {
      _Canned.body = const {'foo': 'bar'};

      final result = await service.getMultipleModInfo(
        workshopIds: ['111'],
        appId: 1142710,
      );

      expect(result, isA<Err>());
      expect(result.error.message, contains('Invalid API response format'));
    });
  });

  group('modExists', () {
    test('returns true when the mod is found', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {'result': 1, 'publishedfileid': '123', 'title': 'X'}
          ]
        }
      };

      final result = await service.modExists(workshopId: '123', appId: 1142710);

      expect(result, isA<Ok>());
      expect(result.value, isTrue);
    });

    test('returns false when the mod is not found', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {'result': 9, 'publishedfileid': '123'}
          ]
        }
      };

      final result = await service.modExists(workshopId: '123', appId: 1142710);

      expect(result, isA<Ok>());
      expect(result.value, isFalse);
    });

    test('propagates other errors', () async {
      final result = await service.modExists(workshopId: 'bad', appId: 1142710);

      expect(result, isA<Err>());
      expect(result.error, isA<InvalidWorkshopIdException>());
    });
  });

  group('checkForUpdates over the (faked) network', () {
    test('flags mods whose remote timestamp is newer', () async {
      _Canned.body = {
        'response': {
          'publishedfiledetails': [
            {
              'result': 1,
              'publishedfileid': '111',
              'title': 'Newer',
              'time_updated': 2000,
            },
            {
              'result': 1,
              'publishedfileid': '222',
              'title': 'Older',
              'time_updated': 50,
            },
            {
              'result': 1,
              'publishedfileid': '333',
              'title': 'NoRemoteTs',
              // no time_updated -> null -> not updated
            },
          ]
        }
      };

      final result = await service.checkForUpdates(
        modsWithTimestamps: {'111': 1000, '222': 1000, '333': 1000, '444': 1000},
        appId: 1142710,
      );

      expect(result, isA<Ok>());
      final map = (result as Ok).value as Map<String, bool>;
      expect(map['111'], isTrue); // remote 2000 > local 1000
      expect(map['222'], isFalse); // remote 50 < local 1000
      expect(map['333'], isFalse); // no remote timestamp
      expect(map['444'], isFalse); // missing from API response
    });
  });
}
