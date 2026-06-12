import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/editor_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';

import '../helpers/mock_providers.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockLanguageRepository extends Mock implements LanguageRepository {}

void main() {
  group('TranslationInProgress notifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('build() defaults to false', () {
      expect(container.read(translationInProgressProvider), isFalse);
    });

    test('setInProgress(true) flips the state', () {
      expect(container.read(translationInProgressProvider), isFalse);

      container.read(translationInProgressProvider.notifier).setInProgress(true);

      expect(container.read(translationInProgressProvider), isTrue);
    });

    test('setInProgress(false) restores the state', () {
      final notifier = container.read(translationInProgressProvider.notifier);
      notifier.setInProgress(true);
      expect(container.read(translationInProgressProvider), isTrue);

      notifier.setInProgress(false);
      expect(container.read(translationInProgressProvider), isFalse);
    });
  });

  group('undoRedoManager family', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('returns a non-null UndoRedoManager for given args', () {
      final manager = container.read(undoRedoManagerProvider('p1', 'l1'));
      expect(manager, isA<UndoRedoManager>());
    });

    test('distinct args yield independent instances', () {
      final a = container.read(undoRedoManagerProvider('p1', 'l1'));
      final b = container.read(undoRedoManagerProvider('p2', 'l2'));

      expect(identical(a, b), isFalse);
    });

    test('same args yield the same cached instance', () {
      final a = container.read(undoRedoManagerProvider('p1', 'l1'));
      final b = container.read(undoRedoManagerProvider('p1', 'l1'));

      expect(identical(a, b), isTrue);
    });
  });

  group('currentProject family', () {
    late MockProjectRepository mockRepo;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockProjectRepository();
      container = ProviderContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(mockRepo),
      ]);
    });

    tearDown(() => container.dispose());

    test('Ok result resolves to the Project', () async {
      final project = createMockProject(id: 'p1', name: 'My Project');
      when(() => mockRepo.getById('p1')).thenAnswer(
        (_) async => Ok<Project, TWMTDatabaseException>(project),
      );

      final result = await container.read(currentProjectProvider('p1').future);

      expect(result.id, 'p1');
      expect(result.name, 'My Project');
    });

    test('Err result drives the provider into an error state', () async {
      when(() => mockRepo.getById('bad')).thenAnswer(
        (_) async => Err<Project, TWMTDatabaseException>(
          TWMTDatabaseException('boom'),
        ),
      );

      // Reading `.future` of a family whose build throws hangs; listen instead.
      container.listen(currentProjectProvider('bad'), (_, _) {});
      await pumpEventQueue();

      final state = container.read(currentProjectProvider('bad'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });
  });

  group('currentLanguage family', () {
    late MockLanguageRepository mockRepo;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockLanguageRepository();
      container = ProviderContainer(overrides: [
        languageRepositoryProvider.overrideWithValue(mockRepo),
      ]);
    });

    tearDown(() => container.dispose());

    test('Ok result resolves to the Language', () async {
      final language = createMockLanguage(id: 'fr', name: 'French');
      when(() => mockRepo.getById('fr')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(language),
      );

      final result = await container.read(currentLanguageProvider('fr').future);

      expect(result.id, 'fr');
      expect(result.name, 'French');
    });

    test('Err result drives the provider into an error state', () async {
      when(() => mockRepo.getById('bad')).thenAnswer(
        (_) async => Err<Language, TWMTDatabaseException>(
          TWMTDatabaseException('boom'),
        ),
      );

      container.listen(currentLanguageProvider('bad'), (_, _) {});
      await pumpEventQueue();

      final state = container.read(currentLanguageProvider('bad'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });
  });
}
