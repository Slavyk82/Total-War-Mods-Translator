import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/service_exception.dart';

void main() {
  group('ServiceException', () {
    test('is an Exception', () {
      expect(const ServiceException('boom'), isA<Exception>());
    });

    test('stores fields and defaults optionals to null', () {
      const ex = ServiceException('boom');
      expect(ex.message, 'boom');
      expect(ex.code, isNull);
      expect(ex.details, isNull);
      expect(ex.error, isNull);
      expect(ex.stackTrace, isNull);
    });

    test('stores all provided fields', () {
      final stack = StackTrace.current;
      final ex = ServiceException(
        'boom',
        code: 'E_BOOM',
        details: {'a': 1},
        error: 'inner',
        stackTrace: stack,
      );
      expect(ex.message, 'boom');
      expect(ex.code, 'E_BOOM');
      expect(ex.details, {'a': 1});
      expect(ex.error, 'inner');
      expect(ex.stackTrace, same(stack));
    });

    test('toString with message only', () {
      const ex = ServiceException('boom');
      expect(ex.toString(), 'ServiceException: boom');
    });

    test('toString with code', () {
      const ex = ServiceException('boom', code: 'E1');
      expect(ex.toString(), 'ServiceException: boom (code: E1)');
    });

    test('toString with details', () {
      const ex = ServiceException('boom', details: 'extra');
      expect(ex.toString(), 'ServiceException: boom\nDetails: extra');
    });

    test('toString with error', () {
      const ex = ServiceException('boom', error: 'cause');
      expect(ex.toString(), 'ServiceException: boom\nCaused by: cause');
    });

    test('toString with stackTrace', () {
      final stack = StackTrace.fromString('frame0\nframe1');
      final ex = ServiceException('boom', stackTrace: stack);
      expect(ex.toString(), 'ServiceException: boom\nframe0\nframe1');
    });

    test('toString with all fields', () {
      final stack = StackTrace.fromString('frameX');
      final ex = ServiceException(
        'boom',
        code: 'E1',
        details: 'd',
        error: 'cause',
        stackTrace: stack,
      );
      expect(
        ex.toString(),
        'ServiceException: boom (code: E1)\nDetails: d\nCaused by: cause\nframeX',
      );
    });
  });

  group('TWMTDatabaseException', () {
    test('is a ServiceException', () {
      expect(
        const TWMTDatabaseException('db'),
        isA<ServiceException>(),
      );
    });

    test('stores fields with and without optionals', () {
      const bare = TWMTDatabaseException('db');
      expect(bare.message, 'db');
      expect(bare.error, isNull);
      expect(bare.stackTrace, isNull);

      final stack = StackTrace.current;
      final full = TWMTDatabaseException('db', error: 'e', stackTrace: stack);
      expect(full.error, 'e');
      expect(full.stackTrace, same(stack));
    });

    test('toString', () {
      const ex = TWMTDatabaseException('db');
      expect(ex.toString(), 'TWMTDatabaseException: db');
      const withError = TWMTDatabaseException('db', error: 'cause');
      expect(withError.toString(), 'TWMTDatabaseException: db\nCaused by: cause');
    });
  });

  group('ValidationException', () {
    test('defaults fieldErrors to empty map', () {
      const ex = ValidationException('invalid');
      expect(ex.fieldErrors, isEmpty);
    });

    test('stores fieldErrors and optionals', () {
      final stack = StackTrace.current;
      final ex = ValidationException(
        'invalid',
        fieldErrors: const {
          'name': ['required'],
          'age': ['too small', 'not a number'],
        },
        error: 'e',
        stackTrace: stack,
      );
      expect(ex.fieldErrors['name'], ['required']);
      expect(ex.error, 'e');
      expect(ex.stackTrace, same(stack));
    });

    test('hasFieldError', () {
      const ex = ValidationException(
        'invalid',
        fieldErrors: {
          'name': ['required'],
        },
      );
      expect(ex.hasFieldError('name'), isTrue);
      expect(ex.hasFieldError('missing'), isFalse);
    });

    test('getFieldErrors returns errors or empty list', () {
      const ex = ValidationException(
        'invalid',
        fieldErrors: {
          'name': ['required', 'too short'],
        },
      );
      expect(ex.getFieldErrors('name'), ['required', 'too short']);
      expect(ex.getFieldErrors('missing'), isEmpty);
    });

    test('toString without field errors', () {
      const ex = ValidationException('invalid');
      expect(ex.toString(), 'ValidationException: invalid');
    });

    test('toString with field errors', () {
      const ex = ValidationException(
        'invalid',
        fieldErrors: {
          'name': ['required'],
          'age': ['too small', 'not a number'],
        },
      );
      expect(
        ex.toString(),
        'ValidationException: invalid\nField errors:'
        '\n  name: required'
        '\n  age: too small, not a number',
      );
    });
  });

  group('NetworkException', () {
    test('stores fields with and without optionals', () {
      const bare = NetworkException('net');
      expect(bare.statusCode, isNull);
      expect(bare.url, isNull);

      const full = NetworkException(
        'net',
        statusCode: 404,
        url: 'https://example.com',
      );
      expect(full.statusCode, 404);
      expect(full.url, 'https://example.com');
    });

    test('toString without optionals', () {
      const ex = NetworkException('net');
      expect(ex.toString(), 'NetworkException: net');
    });

    test('toString with statusCode only', () {
      const ex = NetworkException('net', statusCode: 500);
      expect(ex.toString(), 'NetworkException: net\nStatus code: 500');
    });

    test('toString with url only', () {
      const ex = NetworkException('net', url: 'http://x');
      expect(ex.toString(), 'NetworkException: net\nURL: http://x');
    });

    test('toString with all optionals', () {
      const ex = NetworkException('net', statusCode: 404, url: 'http://x');
      expect(
        ex.toString(),
        'NetworkException: net\nStatus code: 404\nURL: http://x',
      );
    });
  });

  group('LlmServiceException', () {
    test('stores fields with and without optionals', () {
      const bare = LlmServiceException('llm');
      expect(bare.provider, isNull);
      expect(bare.model, isNull);
      expect(bare.tokensUsed, isNull);

      const full = LlmServiceException(
        'llm',
        provider: 'anthropic',
        model: 'claude',
        tokensUsed: 42,
      );
      expect(full.provider, 'anthropic');
      expect(full.model, 'claude');
      expect(full.tokensUsed, 42);
    });

    test('toString without optionals', () {
      const ex = LlmServiceException('llm');
      expect(ex.toString(), 'LlmServiceException: llm');
    });

    test('toString with provider only', () {
      const ex = LlmServiceException('llm', provider: 'anthropic');
      expect(ex.toString(), 'LlmServiceException: llm\nProvider: anthropic');
    });

    test('toString with model only', () {
      const ex = LlmServiceException('llm', model: 'claude');
      expect(ex.toString(), 'LlmServiceException: llm\nModel: claude');
    });

    test('toString with tokensUsed only', () {
      const ex = LlmServiceException('llm', tokensUsed: 100);
      expect(ex.toString(), 'LlmServiceException: llm\nTokens used: 100');
    });

    test('toString with all optionals', () {
      const ex = LlmServiceException(
        'llm',
        provider: 'anthropic',
        model: 'claude',
        tokensUsed: 7,
      );
      expect(
        ex.toString(),
        'LlmServiceException: llm\nProvider: anthropic\nModel: claude\nTokens used: 7',
      );
    });
  });

  group('RpfmException', () {
    test('stores fields with and without optionals', () {
      const bare = RpfmException('rpfm');
      expect(bare.command, isNull);
      expect(bare.exitCode, isNull);

      const full = RpfmException('rpfm', command: 'extract', exitCode: 1);
      expect(full.command, 'extract');
      expect(full.exitCode, 1);
    });

    test('toString without optionals', () {
      const ex = RpfmException('rpfm');
      expect(ex.toString(), 'RpfmException: rpfm');
    });

    test('toString with command only', () {
      const ex = RpfmException('rpfm', command: 'extract');
      expect(ex.toString(), 'RpfmException: rpfm\nCommand: extract');
    });

    test('toString with exitCode only', () {
      const ex = RpfmException('rpfm', exitCode: 2);
      expect(ex.toString(), 'RpfmException: rpfm\nExit code: 2');
    });

    test('toString with all optionals', () {
      const ex = RpfmException('rpfm', command: 'extract', exitCode: 3);
      expect(
        ex.toString(),
        'RpfmException: rpfm\nCommand: extract\nExit code: 3',
      );
    });
  });

  group('SteamException', () {
    test('stores fields with and without optionals', () {
      const bare = SteamException('steam');
      expect(bare.workshopId, isNull);
      expect(bare.gameCode, isNull);

      const full = SteamException('steam', workshopId: '123', gameCode: 'wh3');
      expect(full.workshopId, '123');
      expect(full.gameCode, 'wh3');
    });

    test('toString without optionals', () {
      const ex = SteamException('steam');
      expect(ex.toString(), 'SteamException: steam');
    });

    test('toString with workshopId only', () {
      const ex = SteamException('steam', workshopId: '123');
      expect(ex.toString(), 'SteamException: steam\nWorkshop ID: 123');
    });

    test('toString with gameCode only', () {
      const ex = SteamException('steam', gameCode: 'wh3');
      expect(ex.toString(), 'SteamException: steam\nGame: wh3');
    });

    test('toString with all optionals', () {
      const ex = SteamException('steam', workshopId: '123', gameCode: 'wh3');
      expect(
        ex.toString(),
        'SteamException: steam\nWorkshop ID: 123\nGame: wh3',
      );
    });
  });

  group('TranslationException', () {
    test('stores fields with and without optionals', () {
      const bare = TranslationException('tr');
      expect(bare.unitId, isNull);
      expect(bare.languageCode, isNull);
      expect(bare.batchId, isNull);

      const full = TranslationException(
        'tr',
        unitId: 'u1',
        languageCode: 'fr',
        batchId: 'b1',
      );
      expect(full.unitId, 'u1');
      expect(full.languageCode, 'fr');
      expect(full.batchId, 'b1');
    });

    test('toString without optionals', () {
      const ex = TranslationException('tr');
      expect(ex.toString(), 'TranslationException: tr');
    });

    test('toString with unitId only', () {
      const ex = TranslationException('tr', unitId: 'u1');
      expect(ex.toString(), 'TranslationException: tr\nUnit ID: u1');
    });

    test('toString with languageCode only', () {
      const ex = TranslationException('tr', languageCode: 'fr');
      expect(ex.toString(), 'TranslationException: tr\nLanguage: fr');
    });

    test('toString with batchId only', () {
      const ex = TranslationException('tr', batchId: 'b1');
      expect(ex.toString(), 'TranslationException: tr\nBatch ID: b1');
    });

    test('toString with all optionals', () {
      const ex = TranslationException(
        'tr',
        unitId: 'u1',
        languageCode: 'fr',
        batchId: 'b1',
      );
      expect(
        ex.toString(),
        'TranslationException: tr\nUnit ID: u1\nLanguage: fr\nBatch ID: b1',
      );
    });
  });

  group('FileSystemException', () {
    test('stores fields with and without optionals', () {
      const bare = FileSystemException('fs');
      expect(bare.filePath, isNull);

      const full = FileSystemException('fs', filePath: '/tmp/x');
      expect(full.filePath, '/tmp/x');
    });

    test('toString without optionals', () {
      const ex = FileSystemException('fs');
      expect(ex.toString(), 'FileSystemException: fs');
    });

    test('toString with filePath', () {
      const ex = FileSystemException('fs', filePath: '/tmp/x');
      expect(ex.toString(), 'FileSystemException: fs\nFile path: /tmp/x');
    });
  });

  group('ConcurrencyException', () {
    test('stores fields with and without optionals', () {
      const bare = ConcurrencyException('lock');
      expect(bare.resourceId, isNull);
      expect(bare.lockHolderContext, isNull);

      const full = ConcurrencyException(
        'lock',
        resourceId: 'r1',
        lockHolderContext: 'worker-2',
      );
      expect(full.resourceId, 'r1');
      expect(full.lockHolderContext, 'worker-2');
    });

    test('toString without optionals', () {
      const ex = ConcurrencyException('lock');
      expect(ex.toString(), 'ConcurrencyException: lock');
    });

    test('toString with resourceId only', () {
      const ex = ConcurrencyException('lock', resourceId: 'r1');
      expect(ex.toString(), 'ConcurrencyException: lock\nResource ID: r1');
    });

    test('toString with lockHolderContext only', () {
      const ex = ConcurrencyException('lock', lockHolderContext: 'worker-2');
      expect(ex.toString(), 'ConcurrencyException: lock\nLocked by: worker-2');
    });

    test('toString with all optionals', () {
      const ex = ConcurrencyException(
        'lock',
        resourceId: 'r1',
        lockHolderContext: 'worker-2',
      );
      expect(
        ex.toString(),
        'ConcurrencyException: lock\nResource ID: r1\nLocked by: worker-2',
      );
    });
  });

  group('TranslationMemoryException', () {
    test('stores fields with and without optionals', () {
      const bare = TranslationMemoryException('tm');
      expect(bare.sourceHash, isNull);
      expect(bare.targetLanguageCode, isNull);

      const full = TranslationMemoryException(
        'tm',
        sourceHash: 'abc',
        targetLanguageCode: 'de',
      );
      expect(full.sourceHash, 'abc');
      expect(full.targetLanguageCode, 'de');
    });

    test('toString without optionals', () {
      const ex = TranslationMemoryException('tm');
      expect(ex.toString(), 'TranslationMemoryException: tm');
    });

    test('toString with sourceHash only', () {
      const ex = TranslationMemoryException('tm', sourceHash: 'abc');
      expect(ex.toString(), 'TranslationMemoryException: tm\nSource hash: abc');
    });

    test('toString with targetLanguageCode only', () {
      const ex = TranslationMemoryException('tm', targetLanguageCode: 'de');
      expect(
        ex.toString(),
        'TranslationMemoryException: tm\nTarget language: de',
      );
    });

    test('toString with all optionals', () {
      const ex = TranslationMemoryException(
        'tm',
        sourceHash: 'abc',
        targetLanguageCode: 'de',
      );
      expect(
        ex.toString(),
        'TranslationMemoryException: tm\nSource hash: abc\nTarget language: de',
      );
    });
  });

  group('ConfigurationException', () {
    test('stores fields with and without optionals', () {
      const bare = ConfigurationException('config');
      expect(bare.configKey, isNull);

      const full = ConfigurationException('config', configKey: 'api.key');
      expect(full.configKey, 'api.key');
    });

    test('toString without optionals', () {
      const ex = ConfigurationException('config');
      expect(ex.toString(), 'ConfigurationException: config');
    });

    test('toString with configKey', () {
      const ex = ConfigurationException('config', configKey: 'api.key');
      expect(ex.toString(), 'ConfigurationException: config\nConfig key: api.key');
    });
  });
}
