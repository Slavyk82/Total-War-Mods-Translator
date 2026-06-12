import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/settings/providers/ignored_source_texts_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/services/translation/ignored_source_text_service.dart';

class _MockService extends Mock implements IgnoredSourceTextService {}

IgnoredSourceText _text(String id, String source, {bool enabled = true}) =>
    IgnoredSourceText(
      id: id,
      sourceText: source,
      isEnabled: enabled,
      createdAt: 0,
      updatedAt: 0,
    );

Ok<T, TWMTDatabaseException> _ok<T>(T value) => Ok(value);

Err<T, TWMTDatabaseException> _err<T>(String message) =>
    Err(TWMTDatabaseException(message));

void main() {
  late _MockService service;

  setUp(() {
    service = _MockService();
    // Default build() dependency: empty list.
    when(() => service.getAll()).thenAnswer((_) async => _ok(const []));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        ignoredSourceTextServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('IgnoredSourceTexts.build', () {
    test('returns the texts from the service on success', () async {
      when(() => service.getAll())
          .thenAnswer((_) async => _ok([_text('1', 'foo'), _text('2', 'bar')]));

      final container = makeContainer();
      final result =
          await container.read(ignoredSourceTextsProvider.future);

      expect(result.map((t) => t.sourceText), ['foo', 'bar']);
    });

    test('falls back to an empty list when the service errors', () async {
      when(() => service.getAll())
          .thenAnswer((_) async => _err<List<IgnoredSourceText>>('db down'));

      final container = makeContainer();

      expect(await container.read(ignoredSourceTextsProvider.future), isEmpty);
    });
  });

  group('mutations return (success, errorMessage)', () {
    late ProviderContainer container;
    late IgnoredSourceTexts notifier;

    setUp(() async {
      container = makeContainer();
      await container.read(ignoredSourceTextsProvider.future);
      notifier = container.read(ignoredSourceTextsProvider.notifier);
    });

    test('addText: ok -> (true, null)', () async {
      when(() => service.add('hi'))
          .thenAnswer((_) async => _ok(_text('1', 'hi')));

      expect(await notifier.addText('hi'), (true, null));
      verify(() => service.add('hi')).called(1);
    });

    test('addText: err -> (false, message)', () async {
      when(() => service.add('dup'))
          .thenAnswer((_) async => _err<IgnoredSourceText>('duplicate'));

      expect(await notifier.addText('dup'), (false, 'duplicate'));
    });

    test('updateText: ok -> (true, null)', () async {
      when(() => service.update('1', 'new'))
          .thenAnswer((_) async => _ok(_text('1', 'new')));

      expect(await notifier.updateText('1', 'new'), (true, null));
    });

    test('updateText: err -> (false, message)', () async {
      when(() => service.update('1', 'bad'))
          .thenAnswer((_) async => _err<IgnoredSourceText>('invalid'));

      expect(await notifier.updateText('1', 'bad'), (false, 'invalid'));
    });

    test('deleteText: ok -> (true, null)', () async {
      when(() => service.delete('1')).thenAnswer((_) async => _ok<void>(null));

      expect(await notifier.deleteText('1'), (true, null));
    });

    test('deleteText: err -> (false, message)', () async {
      when(() => service.delete('1'))
          .thenAnswer((_) async => _err<void>('missing'));

      expect(await notifier.deleteText('1'), (false, 'missing'));
    });

    test('toggleEnabled: ok -> (true, null)', () async {
      when(() => service.toggleEnabled('1'))
          .thenAnswer((_) async => _ok(_text('1', 'foo', enabled: false)));

      expect(await notifier.toggleEnabled('1'), (true, null));
    });

    test('toggleEnabled: err -> (false, message)', () async {
      when(() => service.toggleEnabled('1'))
          .thenAnswer((_) async => _err<IgnoredSourceText>('nope'));

      expect(await notifier.toggleEnabled('1'), (false, 'nope'));
    });

    test('resetToDefaults: ok -> (true, null)', () async {
      when(() => service.resetToDefaults())
          .thenAnswer((_) async => _ok([_text('1', 'd')]));

      expect(await notifier.resetToDefaults(), (true, null));
    });

    test('resetToDefaults: err -> (false, message)', () async {
      when(() => service.resetToDefaults())
          .thenAnswer((_) async => _err<List<IgnoredSourceText>>('failed'));

      expect(await notifier.resetToDefaults(), (false, 'failed'));
    });
  });

  group('enabledIgnoredTextsCountProvider', () {
    test('returns the enabled count from the service', () async {
      when(() => service.getEnabledCount()).thenAnswer((_) async => 7);

      final container = makeContainer();

      expect(await container.read(enabledIgnoredTextsCountProvider.future), 7);
    });
  });
}
