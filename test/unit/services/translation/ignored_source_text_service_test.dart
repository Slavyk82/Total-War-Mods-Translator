import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/repositories/ignored_source_text_repository.dart';
import 'package:twmt/services/translation/ignored_source_text_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements IgnoredSourceTextRepository {}

IgnoredSourceText _text(String source, {bool enabled = true}) =>
    IgnoredSourceText(
      id: 'id-$source',
      sourceText: source,
      isEnabled: enabled,
      createdAt: 0,
      updatedAt: 0,
    );

Ok<T, TWMTDatabaseException> _ok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _err<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() => registerFallbackValue(_text('fallback')));

  late _MockRepo repo;
  late IgnoredSourceTextService service;

  setUp(() {
    repo = _MockRepo();
    service = IgnoredSourceTextService(repository: repo, logging: FakeLogger());
    when(() => repo.getEnabledTexts())
        .thenAnswer((_) async => _ok([_text('placeholder')]));
  });

  group('cache + shouldSkip', () {
    test('shouldSkip is false before the cache is loaded', () {
      expect(service.shouldSkip('placeholder'), isFalse);
    });

    test('after loading, shouldSkip matches case-insensitively and trimmed',
        () async {
      await service.ensureCacheLoaded();
      expect(service.shouldSkip('  PLACEHOLDER '), isTrue);
      expect(service.shouldSkip('other'), isFalse);
    });

    test('a repository error yields an empty cache', () async {
      when(() => repo.getEnabledTexts())
          .thenAnswer((_) async => _err<List<IgnoredSourceText>>('boom'));
      await service.refreshCache();
      expect(service.shouldSkip('placeholder'), isFalse);
    });
  });

  group('getSqlCondition', () {
    test('builds a LOWER(TRIM(...)) IN clause and escapes quotes', () async {
      when(() => repo.getEnabledTexts())
          .thenAnswer((_) async => _ok([_text("o'brien"), _text('x')]));
      await service.refreshCache();

      final sql = service.getSqlCondition();
      expect(sql, contains("LOWER(TRIM(tu.source_text)) IN ("));
      expect(sql, contains("o''brien")); // single quote escaped
    });

    test('falls back to default texts when nothing is cached', () {
      final sql = service.getSqlCondition();
      expect(sql, contains('LOWER(TRIM(tu.source_text)) IN ('));
    });
  });

  group('add', () {
    test('rejects empty text', () async {
      expect((await service.add('   ')).isErr, isTrue);
      verifyNever(() => repo.insert(any()));
    });

    test('rejects a case-insensitive duplicate', () async {
      when(() => repo.existsByText('dup')).thenAnswer((_) async => _ok(true));
      expect((await service.add('dup')).isErr, isTrue);
      verifyNever(() => repo.insert(any()));
    });

    test('inserts a trimmed enabled entry and refreshes the cache', () async {
      when(() => repo.existsByText(any())).thenAnswer((_) async => _ok(false));
      when(() => repo.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as IgnoredSourceText));

      final r = await service.add('  needle  ');

      expect(r.isOk, isTrue);
      final row = verify(() => repo.insert(captureAny())).captured.single
          as IgnoredSourceText;
      expect(row.sourceText, 'needle');
      expect(row.isEnabled, isTrue);
    });
  });

  group('update', () {
    test('rejects empty text', () async {
      expect((await service.update('id', '  ')).isErr, isTrue);
    });

    test('rejects a duplicate (excluding self)', () async {
      when(() => repo.existsByTextExcludingId('dup', 'id'))
          .thenAnswer((_) async => _ok(true));
      expect((await service.update('id', 'dup')).isErr, isTrue);
    });

    test('updates the stored entity with trimmed text', () async {
      when(() => repo.existsByTextExcludingId(any(), any()))
          .thenAnswer((_) async => _ok(false));
      when(() => repo.getById('id')).thenAnswer((_) async => _ok(_text('old')));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as IgnoredSourceText));

      await service.update('id', '  fresh  ');

      final row = verify(() => repo.update(captureAny())).captured.single
          as IgnoredSourceText;
      expect(row.sourceText, 'fresh');
    });
  });

  group('delegating CRUD + counts', () {
    test('delete delegates and returns the repo result', () async {
      when(() => repo.delete('id')).thenAnswer((_) async => _ok(null));
      expect((await service.delete('id')).isOk, isTrue);
    });

    test('getEnabledCount returns 0 on error', () async {
      when(() => repo.getEnabledCount())
          .thenAnswer((_) async => _err<int>('boom'));
      expect(await service.getEnabledCount(), 0);
    });

    test('getTotalCount returns the repo count', () async {
      when(() => repo.getTotalCount()).thenAnswer((_) async => _ok(11));
      expect(await service.getTotalCount(), 11);
    });

    test('resetToDefaults delegates to the repo', () async {
      when(() => repo.resetToDefaults())
          .thenAnswer((_) async => _ok([_text('placeholder')]));
      expect((await service.resetToDefaults()).isOk, isTrue);
    });
  });
}
