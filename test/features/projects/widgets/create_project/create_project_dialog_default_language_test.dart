// Regression tests for [resolveDefaultTargetLanguage].
//
// The Create-Project wizard auto-picks a target language at creation time
// (Task 6, Plan 5d): the user's configured `default_target_language` wins
// when it exists AND is active, otherwise the first active language is used,
// and when no active language is available the resolver must throw a
// user-actionable message that surfaces in the dialog's error banner.
//
// The resolver lives at the top level of
// `create_project_dialog.dart` — exposed specifically so these tests can
// exercise the four branches without pumping the full wizard widget tree.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart'
    show resolveDefaultTargetLanguage;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockSettingsService extends Mock implements SettingsService {}

Language _lang({
  required String id,
  required String code,
  bool isActive = true,
}) {
  return Language(
    id: id,
    code: code,
    name: code.toUpperCase(),
    nativeName: code,
    isActive: isActive,
  );
}

void main() {
  late _MockLanguageRepository langRepo;
  late _MockSettingsService settings;

  setUp(() {
    langRepo = _MockLanguageRepository();
    settings = _MockSettingsService();
  });

  group('resolveDefaultTargetLanguage', () {
    test(
      'returns the configured default when it exists and is active',
      () async {
        when(() => settings.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'de');
        when(() => langRepo.getByCode('de')).thenAnswer(
          (_) async => Ok<Language, TWMTDatabaseException>(
            _lang(id: 'lang-de', code: 'de'),
          ),
        );

        final target = await resolveDefaultTargetLanguage(settings, langRepo);

        expect(target.id, 'lang-de');
        expect(target.code, 'de');
        // The fast path must not consult `getActive()` when the direct
        // lookup wins — otherwise we pay a needless extra DB round-trip.
        verifyNever(() => langRepo.getActive());
      },
    );

    test(
      'falls back to the first active language when the configured default '
      'is missing',
      () async {
        when(() => settings.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'xx');
        when(() => langRepo.getByCode('xx')).thenAnswer(
          (_) async => Err<Language, TWMTDatabaseException>(
            TWMTDatabaseException('Language not found with code: xx'),
          ),
        );
        when(() => langRepo.getActive()).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([
            _lang(id: 'lang-en', code: 'en'),
            _lang(id: 'lang-fr', code: 'fr'),
          ]),
        );

        final target = await resolveDefaultTargetLanguage(settings, langRepo);

        expect(target.id, 'lang-en');
        expect(target.code, 'en');
      },
    );

    test(
      'falls back to the first active language when the configured default '
      'exists but is inactive',
      () async {
        when(() => settings.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'legacy');
        when(() => langRepo.getByCode('legacy')).thenAnswer(
          (_) async => Ok<Language, TWMTDatabaseException>(
            _lang(id: 'lang-legacy', code: 'legacy', isActive: false),
          ),
        );
        when(() => langRepo.getActive()).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([
            _lang(id: 'lang-en', code: 'en'),
          ]),
        );

        final target = await resolveDefaultTargetLanguage(settings, langRepo);

        expect(target.id, 'lang-en');
      },
    );

    test(
      'throws a user-actionable message when no active language is available',
      () async {
        when(() => settings.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'xx');
        when(() => langRepo.getByCode('xx')).thenAnswer(
          (_) async => Err<Language, TWMTDatabaseException>(
            TWMTDatabaseException('Language not found with code: xx'),
          ),
        );
        when(() => langRepo.getActive()).thenAnswer(
          (_) async =>
              Ok<List<Language>, TWMTDatabaseException>(const <Language>[]),
        );

        // The resolver must throw. The outer try/catch in
        // `_createProject` converts this into the dialog's error banner, so
        // the message must be user-facing — no raw exception leak.
        await expectLater(
          () => resolveDefaultTargetLanguage(settings, langRepo),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('No active target language'),
                contains('Settings > General'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'also throws with the user-actionable message when getActive fails',
      () async {
        when(() => settings.getString(
              any(),
              defaultValue: any(named: 'defaultValue'),
            )).thenAnswer((_) async => 'xx');
        when(() => langRepo.getByCode('xx')).thenAnswer(
          (_) async => Err<Language, TWMTDatabaseException>(
            TWMTDatabaseException('Language not found with code: xx'),
          ),
        );
        when(() => langRepo.getActive()).thenAnswer(
          (_) async => Err<List<Language>, TWMTDatabaseException>(
            TWMTDatabaseException('DB offline'),
          ),
        );

        await expectLater(
          () => resolveDefaultTargetLanguage(settings, langRepo),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No active target language'),
            ),
          ),
        );
      },
    );
  });
}
