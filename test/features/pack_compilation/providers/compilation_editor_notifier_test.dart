// Regression coverage for [CompilationEditorNotifier.saveCompilation].
//
// `CompilationRepository.setProjects` returns a `Result` and never throws,
// so the notifier must check it explicitly: a failed project-link write used
// to be silently swallowed and reported as 'Compilation saved'.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';

class _MockCompilationRepository extends Mock
    implements CompilationRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _FakeCompilation extends Fake implements Compilation {}

Compilation _compilation({String id = 'comp-1'}) {
  return Compilation(
    id: id,
    name: 'My compilation',
    prefix: '!!!_fr_compilation_twmt_',
    packName: 'my_pack',
    gameInstallationId: 'install-wh3',
    languageId: 'lang-fr',
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCompilation());
  });

  late _MockCompilationRepository compilationRepo;
  late _MockLanguageRepository languageRepo;
  late ProviderContainer container;

  setUp(() {
    compilationRepo = _MockCompilationRepository();
    languageRepo = _MockLanguageRepository();
    // updateLanguage looks the language up only to derive a default prefix;
    // an Err keeps the current prefix while still selecting the language,
    // which is all these tests need.
    when(() => languageRepo.getById(any())).thenAnswer(
      (_) async => const Err<Language, TWMTDatabaseException>(
        TWMTDatabaseException('not needed in test'),
      ),
    );
    container = ProviderContainer(overrides: [
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
      languageRepositoryProvider.overrideWithValue(languageRepo),
    ]);
    addTearDown(container.dispose);
  });

  /// Fill the form so `canSave` passes.
  ///
  /// Edit mode (non-null [compilationId]) goes through [loadCompilation],
  /// create mode through the individual form updaters.
  Future<void> fillForm({String? compilationId}) async {
    final notifier = container.read(compilationEditorProvider.notifier);
    if (compilationId != null) {
      notifier.loadCompilation(CompilationWithDetails(
        compilation: _compilation(id: compilationId),
        projects: [
          Project(
            id: 'proj-1',
            name: 'P1',
            gameInstallationId: 'install-wh3',
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
        projectCount: 1,
      ));
      return;
    }
    notifier
      ..updateName('My compilation')
      ..updatePackName('my_pack');
    await notifier.updateLanguage('lang-fr');
    notifier
      ..updatePrefix('!!!_fr_compilation_twmt_')
      ..toggleProject('proj-1');
  }

  group('saveCompilation (edit mode)', () {
    test('returns false and surfaces the error when setProjects fails',
        () async {
      await fillForm(compilationId: 'comp-1');

      when(() => compilationRepo.getById('comp-1')).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(_compilation()),
      );
      when(() => compilationRepo.update(any())).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(_compilation()),
      );
      when(() => compilationRepo.setProjects('comp-1', any())).thenAnswer(
        (_) async => const Err<void, TWMTDatabaseException>(
          TWMTDatabaseException('FOREIGN KEY constraint failed'),
        ),
      );

      final saved = await container
          .read(compilationEditorProvider.notifier)
          .saveCompilation('install-wh3');

      expect(saved, isFalse);
      final state = container.read(compilationEditorProvider);
      expect(state.successMessage, isNull,
          reason: 'a failed link write must not be reported as saved');
      expect(state.errorMessage, contains('FOREIGN KEY constraint failed'));
    });

    test('returns true with success message when setProjects succeeds',
        () async {
      await fillForm(compilationId: 'comp-1');

      when(() => compilationRepo.getById('comp-1')).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(_compilation()),
      );
      when(() => compilationRepo.update(any())).thenAnswer(
        (_) async => Ok<Compilation, TWMTDatabaseException>(_compilation()),
      );
      when(() => compilationRepo.setProjects('comp-1', any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );

      final saved = await container
          .read(compilationEditorProvider.notifier)
          .saveCompilation('install-wh3');

      expect(saved, isTrue);
      final state = container.read(compilationEditorProvider);
      expect(state.successMessage, 'Compilation saved');
      expect(state.errorMessage, isNull);
    });
  });

  group('saveCompilation (create mode)', () {
    test('returns false and surfaces the error when setProjects fails',
        () async {
      await fillForm();

      when(() => compilationRepo.insert(any())).thenAnswer(
        (invocation) async => Ok<Compilation, TWMTDatabaseException>(
          invocation.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Err<void, TWMTDatabaseException>(
          TWMTDatabaseException('database is locked'),
        ),
      );

      final saved = await container
          .read(compilationEditorProvider.notifier)
          .saveCompilation('install-wh3');

      expect(saved, isFalse);
      final state = container.read(compilationEditorProvider);
      expect(state.successMessage, isNull);
      expect(state.errorMessage, contains('database is locked'));
      // The row was inserted before the link write failed: the id must be
      // recorded so a retry updates that row instead of inserting a duplicate.
      expect(state.compilationId, isNotNull);
    });

    test('returns true with success message when setProjects succeeds',
        () async {
      await fillForm();

      when(() => compilationRepo.insert(any())).thenAnswer(
        (invocation) async => Ok<Compilation, TWMTDatabaseException>(
          invocation.positionalArguments.first as Compilation,
        ),
      );
      when(() => compilationRepo.setProjects(any(), any())).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );

      final saved = await container
          .read(compilationEditorProvider.notifier)
          .saveCompilation('install-wh3');

      expect(saved, isTrue);
      final state = container.read(compilationEditorProvider);
      expect(state.successMessage, 'Compilation saved');
      expect(state.errorMessage, isNull);
      expect(state.compilationId, isNotNull);
    });
  });
}
