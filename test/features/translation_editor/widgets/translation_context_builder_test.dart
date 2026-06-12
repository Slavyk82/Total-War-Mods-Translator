import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/widgets/translation_context_builder.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/llm_model_providers.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockGlossaryRepo extends Mock implements GlossaryRepository {}

class _MockModelRepo extends Mock implements LlmProviderModelRepository {}

const _projectId = 'project-1';
const _languageId = 'language-fr';
const _projectLanguageId = 'plang-1';

const _projectLanguage = ProjectLanguage(
  id: _projectLanguageId,
  projectId: _projectId,
  languageId: _languageId,
  createdAt: 0,
  updatedAt: 0,
);

const _language = Language(
  id: _languageId,
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
);

final _model = LlmProviderModel(
  id: 'model-1',
  providerCode: 'anthropic',
  modelId: 'claude',
  createdAt: 0,
  updatedAt: 0,
  lastFetchedAt: 0,
);

/// Fakes the toolbar model selector.
class _FakeSelectedModel extends SelectedLlmModel {
  _FakeSelectedModel(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

/// Fakes the LLM provider settings async notifier.
class _FakeLlmSettings extends LlmProviderSettings {
  _FakeLlmSettings(this._data);
  final Map<String, String> _data;
  @override
  Future<Map<String, String>> build() async => _data;
}

class _Harness extends ConsumerStatefulWidget {
  const _Harness({super.key});
  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  WidgetRef get widgetRef => ref;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _MockProjectLanguageRepo projectLanguageRepo;
  late _MockLanguageRepo languageRepo;
  late _MockGlossaryRepo glossaryRepo;
  late _MockModelRepo modelRepo;

  setUp(() {
    projectLanguageRepo = _MockProjectLanguageRepo();
    languageRepo = _MockLanguageRepo();
    glossaryRepo = _MockGlossaryRepo();
    modelRepo = _MockModelRepo();

    when(() => projectLanguageRepo.getByProject(_projectId)).thenAnswer(
      (_) async => const Ok<List<ProjectLanguage>, TWMTDatabaseException>(
        [_projectLanguage],
      ),
    );
    when(() => languageRepo.getById(_languageId)).thenAnswer(
      (_) async => const Ok<Language, TWMTDatabaseException>(_language),
    );
    when(() => glossaryRepo.getByProjectAndLanguage(
          projectId: any(named: 'projectId'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer(
      (_) async => const Ok<List<GlossaryEntry>, TWMTDatabaseException>([]),
    );
  });

  Future<WidgetRef> pumpRef(
    WidgetTester tester, {
    required String? selectedModel,
    Map<String, String> settings = const {'active_llm_provider': 'openai'},
  }) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          glossaryRepositoryProvider.overrideWithValue(glossaryRepo),
          llmProviderModelRepositoryProvider.overrideWithValue(modelRepo),
          selectedLlmModelProvider.overrideWith(
            () => _FakeSelectedModel(selectedModel),
          ),
          llmProviderSettingsProvider.overrideWith(
            () => _FakeLlmSettings(settings),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: _Harness(key: key)),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!.widgetRef;
  }

  testWidgets('uses the toolbar-selected model when one is chosen',
      (tester) async {
    when(() => modelRepo.getById('model-1')).thenAnswer(
      (_) async => Ok<LlmProviderModel, TWMTDatabaseException>(_model),
    );
    final ref = await pumpRef(tester, selectedModel: 'model-1');

    final ctx =
        await TranslationContextBuilder.build(ref, _projectId, _languageId);

    expect(ctx, isNotNull);
    expect(ctx!.providerId, 'anthropic');
    expect(ctx.modelId, 'claude');
    expect(ctx.targetLanguage, 'fr');
    expect(ctx.projectLanguageId, _projectLanguageId);
  });

  testWidgets('falls back to settings when no model is selected',
      (tester) async {
    final ref = await pumpRef(tester, selectedModel: null);

    final ctx =
        await TranslationContextBuilder.build(ref, _projectId, _languageId);

    expect(ctx, isNotNull);
    expect(ctx!.providerId, 'openai');
    expect(ctx.modelId, isNull);
  });

  testWidgets('falls back to settings when the selected model is not found',
      (tester) async {
    when(() => modelRepo.getById('missing')).thenAnswer(
      (_) async => const Err<LlmProviderModel, TWMTDatabaseException>(
        TWMTDatabaseException('no model'),
      ),
    );
    final ref = await pumpRef(tester, selectedModel: 'missing');

    final ctx =
        await TranslationContextBuilder.build(ref, _projectId, _languageId);

    expect(ctx, isNotNull);
    expect(ctx!.providerId, 'openai');
  });

  testWidgets('returns null when project languages cannot be loaded',
      (tester) async {
    when(() => projectLanguageRepo.getByProject(_projectId)).thenAnswer(
      (_) async => const Err<List<ProjectLanguage>, TWMTDatabaseException>(
        TWMTDatabaseException('boom'),
      ),
    );
    final ref = await pumpRef(tester, selectedModel: null);

    final ctx =
        await TranslationContextBuilder.build(ref, _projectId, _languageId);

    expect(ctx, isNull);
  });
}
