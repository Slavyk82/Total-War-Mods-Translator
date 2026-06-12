import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/utils/translation_batch_helper.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/noop_logger.dart';

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockBatchRepo extends Mock implements TranslationBatchRepository {}

class _MockBatchUnitRepo extends Mock
    implements TranslationBatchUnitRepository {}

class _MockProjectRepo extends Mock implements ProjectRepository {}

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockGlossaryRepo extends Mock implements GlossaryRepository {}

class _MockGameInstallationRepo extends Mock
    implements GameInstallationRepository {}

/// A [Reader] backed by an explicit provider->value map. The helper reads
/// top-level (const codegen) providers, so equality lookups resolve to the
/// registered mocks.
class _FakeReader {
  _FakeReader(this._map);
  final Map<ProviderListenable<Object?>, Object?> _map;

  T call<T>(ProviderListenable<T> provider) {
    if (!_map.containsKey(provider)) {
      throw StateError('Unmapped provider: $provider');
    }
    return _map[provider] as T;
  }
}

void main() {
  late _MockVersionRepo versionRepo;
  late _MockBatchRepo batchRepo;
  late _MockBatchUnitRepo batchUnitRepo;
  late _MockProjectRepo projectRepo;
  late _MockProjectLanguageRepo projectLanguageRepo;
  late _MockLanguageRepo languageRepo;
  late _MockGlossaryRepo glossaryRepo;
  late _MockGameInstallationRepo gameInstallationRepo;
  late _FakeReader reader;

  setUpAll(() {
    registerFallbackValue(
      const TranslationBatch(
        id: 'x',
        projectLanguageId: 'pl',
        providerId: 'p',
        batchNumber: 1,
      ),
    );
    registerFallbackValue(<TranslationBatchUnit>[]);
  });

  setUp(() {
    versionRepo = _MockVersionRepo();
    batchRepo = _MockBatchRepo();
    batchUnitRepo = _MockBatchUnitRepo();
    projectRepo = _MockProjectRepo();
    projectLanguageRepo = _MockProjectLanguageRepo();
    languageRepo = _MockLanguageRepo();
    glossaryRepo = _MockGlossaryRepo();
    gameInstallationRepo = _MockGameInstallationRepo();

    reader = _FakeReader({
      loggingServiceProvider: NoopLogger(),
      shared_repo.translationVersionRepositoryProvider: versionRepo,
      shared_repo.projectRepositoryProvider: projectRepo,
      shared_repo.projectLanguageRepositoryProvider: projectLanguageRepo,
      shared_repo.languageRepositoryProvider: languageRepo,
      shared_repo.glossaryRepositoryProvider: glossaryRepo,
      shared_repo.gameInstallationRepositoryProvider: gameInstallationRepo,
      shared_svc.translationBatchRepositoryProvider: batchRepo,
      shared_svc.translationBatchUnitRepositoryProvider: batchUnitRepo,
    });
  });

  group('checkProviderConfigured', () {
    Future<bool> check(Map<String, dynamic> settings) =>
        TranslationBatchHelper.checkProviderConfigured(
          getSettings: () async => settings,
        );

    test('is true when any provider has an API key', () async {
      expect(await check({'anthropic_api_key': 'sk'}), isTrue);
      expect(await check({'openai_api_key': 'sk'}), isTrue);
      expect(await check({'deepl_api_key': 'sk'}), isTrue);
      expect(await check({'deepseek_api_key': 'sk'}), isTrue);
      expect(await check({'gemini_api_key': 'sk'}), isTrue);
    });

    test('is false when no provider has a key', () async {
      expect(await check({}), isFalse);
      expect(await check({'anthropic_api_key': ''}), isFalse);
    });
  });

  group('getUntranslatedUnitIds', () {
    test('returns the repository ids on success', () async {
      when(() => versionRepo.getUntranslatedIds(
              projectLanguageId: 'pl1'))
          .thenAnswer((_) async => const Ok(['a', 'b']));
      final ids = await TranslationBatchHelper.getUntranslatedUnitIds(
        read: reader.call,
        projectLanguageId: 'pl1',
      );
      expect(ids, ['a', 'b']);
    });

    test('returns an empty list on repository error', () async {
      when(() => versionRepo.getUntranslatedIds(
              projectLanguageId: any(named: 'projectLanguageId')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final ids = await TranslationBatchHelper.getUntranslatedUnitIds(
        read: reader.call,
        projectLanguageId: 'pl1',
      );
      expect(ids, isEmpty);
    });
  });

  group('filterUntranslatedUnits', () {
    test('returns the filtered ids on success', () async {
      when(() => versionRepo.filterUntranslatedIds(
            ids: ['a', 'b'],
            projectLanguageId: 'pl1',
          )).thenAnswer((_) async => const Ok(['a']));
      final ids = await TranslationBatchHelper.filterUntranslatedUnits(
        read: reader.call,
        unitIds: ['a', 'b'],
        projectLanguageId: 'pl1',
      );
      expect(ids, ['a']);
    });

    test('returns an empty list on repository error', () async {
      when(() => versionRepo.filterUntranslatedIds(
            ids: any(named: 'ids'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final ids = await TranslationBatchHelper.filterUntranslatedUnits(
        read: reader.call,
        unitIds: ['a'],
        projectLanguageId: 'pl1',
      );
      expect(ids, isEmpty);
    });
  });

  group('createAndPrepareBatch', () {
    test('creates the batch and its units, returning the batch id', () async {
      when(() => batchRepo.getByProjectLanguage('pl1')).thenAnswer(
        (_) async => const Ok(<TranslationBatch>[]),
      );
      when(() => batchRepo.insert(any()))
          .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));
      when(() => batchUnitRepo.insertBatch(any()))
          .thenAnswer((_) async => const Ok(2));

      var errorCalled = false;
      final id = await TranslationBatchHelper.createAndPrepareBatch(
        read: reader.call,
        projectLanguageId: 'pl1',
        unitIds: ['u1', 'u2'],
        providerId: 'anthropic',
        onError: () => errorCalled = true,
      );

      expect(id, isNotNull);
      expect(errorCalled, isFalse);
      // batchNumber is derived from existing batches (none -> 1).
      final batch =
          verify(() => batchRepo.insert(captureAny())).captured.single
              as TranslationBatch;
      expect(batch.batchNumber, 1);
      expect(batch.unitsCount, 2);
      final units =
          verify(() => batchUnitRepo.insertBatch(captureAny())).captured.single
              as List<TranslationBatchUnit>;
      expect(units, hasLength(2));
      expect(units[1].processingOrder, 1);
    });

    test('increments the batch number from existing batches', () async {
      when(() => batchRepo.getByProjectLanguage('pl1')).thenAnswer(
        (_) async => const Ok([
          TranslationBatch(
            id: 'b1',
            projectLanguageId: 'pl1',
            providerId: 'anthropic',
            batchNumber: 4,
          ),
        ]),
      );
      when(() => batchRepo.insert(any()))
          .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));
      when(() => batchUnitRepo.insertBatch(any()))
          .thenAnswer((_) async => const Ok(1));

      await TranslationBatchHelper.createAndPrepareBatch(
        read: reader.call,
        projectLanguageId: 'pl1',
        unitIds: ['u1'],
        providerId: 'anthropic',
        onError: () {},
      );

      final batch =
          verify(() => batchRepo.insert(captureAny())).captured.single
              as TranslationBatch;
      expect(batch.batchNumber, 5);
    });

    test('calls onError and returns null when batch insert fails', () async {
      when(() => batchRepo.getByProjectLanguage(any()))
          .thenAnswer((_) async => const Ok(<TranslationBatch>[]));
      when(() => batchRepo.insert(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));

      var errorCalled = false;
      final id = await TranslationBatchHelper.createAndPrepareBatch(
        read: reader.call,
        projectLanguageId: 'pl1',
        unitIds: ['u1'],
        providerId: 'anthropic',
        onError: () => errorCalled = true,
      );

      expect(id, isNull);
      expect(errorCalled, isTrue);
      verifyNever(() => batchUnitRepo.insertBatch(any()));
    });

    test('calls onError and returns null when unit insert fails', () async {
      when(() => batchRepo.getByProjectLanguage(any()))
          .thenAnswer((_) async => const Ok(<TranslationBatch>[]));
      when(() => batchRepo.insert(any()))
          .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));
      when(() => batchUnitRepo.insertBatch(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));

      var errorCalled = false;
      final id = await TranslationBatchHelper.createAndPrepareBatch(
        read: reader.call,
        projectLanguageId: 'pl1',
        unitIds: ['u1'],
        providerId: 'anthropic',
        onError: () => errorCalled = true,
      );

      expect(id, isNull);
      expect(errorCalled, isTrue);
    });
  });

  group('buildTranslationContext', () {
    void stubGraph({String gameCode = 'wh3'}) {
      when(() => projectRepo.getById('proj')).thenAnswer(
        (_) async => Ok(Project(
          id: 'proj',
          name: 'P',
          gameInstallationId: 'gi1',
          createdAt: 1,
          updatedAt: 1,
        )),
      );
      when(() => gameInstallationRepo.getById('gi1')).thenAnswer(
        (_) async => Ok(GameInstallation(
          id: 'gi1',
          gameCode: gameCode,
          gameName: 'G',
          createdAt: 1,
          updatedAt: 1,
        )),
      );
      when(() => projectLanguageRepo.getById('pl1')).thenAnswer(
        (_) async => Ok(ProjectLanguage(
          id: 'pl1',
          projectId: 'proj',
          languageId: 'lang_fr',
          createdAt: 1,
          updatedAt: 1,
        )),
      );
      when(() => languageRepo.getById('lang_fr')).thenAnswer(
        (_) async => Ok(const Language(
          id: 'lang_fr',
          code: 'fr',
          name: 'French',
          nativeName: 'Français',
        )),
      );
      when(() => glossaryRepo.getAllGlossaries(
              gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => []);
    }

    test('resolves the target language and builds a context', () async {
      stubGraph();

      final ctx = await TranslationBatchHelper.buildTranslationContext(
        read: reader.call,
        projectId: 'proj',
        projectLanguageId: 'pl1',
        providerId: 'anthropic',
        modelId: 'claude',
      );

      expect(ctx.projectId, 'proj');
      expect(ctx.projectLanguageId, 'pl1');
      expect(ctx.providerId, 'anthropic');
      expect(ctx.modelId, 'claude');
      // Language code is uppercased for the API.
      expect(ctx.targetLanguage, 'FR');
      expect(ctx.sourceLanguage, 'EN');
    });

    test('falls back to a default context when the graph throws', () async {
      when(() => projectRepo.getById(any())).thenThrow(Exception('boom'));

      final ctx = await TranslationBatchHelper.buildTranslationContext(
        read: reader.call,
        projectId: 'proj',
        projectLanguageId: 'pl1',
        providerId: 'anthropic',
      );

      // Fallback context uses the lowercase 'en' default.
      expect(ctx.targetLanguage, 'en');
      expect(ctx.projectId, 'proj');
    });
  });
}
