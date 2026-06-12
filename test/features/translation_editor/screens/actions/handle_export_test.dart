import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_base.dart';
import 'package:twmt/features/translation_editor/screens/actions/editor_actions_export.dart';
import 'package:twmt/features/translation_editor/screens/export_progress_screen.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockExportService extends Mock implements ExportOrchestratorService {}

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

class _ExportActions with EditorActionsBase, EditorActionsExport {
  _ExportActions({required this.ref, required this.context});
  @override
  final WidgetRef ref;
  @override
  final BuildContext context;
  @override
  String get projectId => _projectId;
  @override
  String get languageId => _languageId;
}

class _Harness extends ConsumerStatefulWidget {
  const _Harness({super.key});
  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  _ExportActions buildActions() => _ExportActions(ref: ref, context: context);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _MockProjectLanguageRepo projectLanguageRepo;
  late _MockLanguageRepo languageRepo;
  late _MockExportService exportService;

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    projectLanguageRepo = _MockProjectLanguageRepo();
    languageRepo = _MockLanguageRepo();
    exportService = _MockExportService();
  });

  Future<GlobalKey<_HarnessState>> pump(WidgetTester tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          exportOrchestratorServiceProvider.overrideWithValue(exportService),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: _Harness(key: key)),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  void stubProjectLanguages({bool ok = true}) {
    when(() => projectLanguageRepo.getByProject(_projectId)).thenAnswer(
      (_) async => ok
          ? const Ok<List<ProjectLanguage>, TWMTDatabaseException>(
              [_projectLanguage])
          : const Err<List<ProjectLanguage>, TWMTDatabaseException>(
              TWMTDatabaseException('boom')),
    );
  }

  testWidgets('shows an error dialog when the project language cannot be resolved',
      (tester) async {
    stubProjectLanguages(ok: false);
    final key = await pump(tester);

    await key.currentState!.buildActions().handleExport();
    await tester.pumpAndSettle();

    expect(find.text('Pack generation failed'), findsOneWidget);
  });

  testWidgets('shows an error dialog when the language load fails',
      (tester) async {
    stubProjectLanguages();
    when(() => projectLanguageRepo.getById(_projectLanguageId)).thenAnswer(
      (_) async => const Err<ProjectLanguage, TWMTDatabaseException>(
        TWMTDatabaseException('no pl'),
      ),
    );
    final key = await pump(tester);

    await key.currentState!.buildActions().handleExport();
    await tester.pumpAndSettle();

    expect(find.text('Pack generation failed'), findsOneWidget);
  });

  testWidgets('navigates to the export progress screen on success',
      (tester) async {
    stubProjectLanguages();
    when(() => projectLanguageRepo.getById(_projectLanguageId)).thenAnswer(
      (_) async =>
          const Ok<ProjectLanguage, TWMTDatabaseException>(_projectLanguage),
    );
    when(() => languageRepo.getById(_languageId)).thenAnswer(
      (_) async => const Ok<Language, TWMTDatabaseException>(_language),
    );
    // Never completes: keeps the export screen mounted without extra timers.
    when(() => exportService.exportToPack(
          projectId: any(named: 'projectId'),
          languageCodes: any(named: 'languageCodes'),
          outputPath: any(named: 'outputPath'),
          validatedOnly: any(named: 'validatedOnly'),
          generatePackImage: any(named: 'generatePackImage'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer(
      (_) => Completer<Result<ExportResult, FileServiceException>>().future,
    );

    final key = await pump(tester);

    await key.currentState!.buildActions().handleExport();
    await tester.pumpAndSettle();

    expect(find.byType(ExportProgressScreen), findsOneWidget);
  });
}
