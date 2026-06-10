// Regression tests for the create-project rollback fix.
//
// `_initializeProjectFiles` used to return void and swallow every failure
// (empty RPFM schema path, or initializeProject returning Err) by only setting
// an error banner, so the caller fell through to pop() the dialog as success
// and left an orphaned, empty project row in the database. The decision is now
// extracted into [initializeProjectFilesOrRollback], which rolls the project
// back on any failure. These tests pin that behavior without pumping the wizard.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart'
    show
        initializeProjectFilesOrRollback,
        ProjectInitFailure,
        ProjectInitOutcome;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';

class _MockInitService extends Mock implements IProjectInitializationService {}

class _MockProjectRepo extends Mock implements ProjectRepository {}

void main() {
  late _MockInitService initService;
  late _MockProjectRepo projectRepo;

  setUp(() {
    initService = _MockInitService();
    projectRepo = _MockProjectRepo();
    when(() => projectRepo.delete(any()))
        .thenAnswer((_) async => Ok<void, TWMTDatabaseException>(null));
  });

  test('rolls back the project when the RPFM schema path is not configured',
      () async {
    final outcome = await initializeProjectFilesOrRollback(
      initService: initService,
      projectRepo: projectRepo,
      projectId: 'proj-1',
      packFilePath: 'C:/mods/foo.pack',
      schemaPath: '',
    );

    expect(outcome.success, isFalse);
    expect(outcome.failure, ProjectInitFailure.schemaNotConfigured);
    verify(() => projectRepo.delete('proj-1')).called(1);
    // The unconfigured schema must abort before touching the init service.
    verifyNever(() => initService.initializeProject(
        projectId: any(named: 'projectId'),
        packFilePath: any(named: 'packFilePath')));
  });

  test('rolls back the project when initializeProject returns an error',
      () async {
    when(() => initService.initializeProject(
          projectId: any(named: 'projectId'),
          packFilePath: any(named: 'packFilePath'),
        )).thenAnswer((_) async =>
        Err<int, ServiceException>(ServiceException('corrupt pack')));

    final outcome = await initializeProjectFilesOrRollback(
      initService: initService,
      projectRepo: projectRepo,
      projectId: 'proj-2',
      packFilePath: 'C:/mods/bar.pack',
      schemaPath: 'C:/rpfm/schema',
    );

    expect(outcome.success, isFalse);
    expect(outcome.failure, ProjectInitFailure.initError);
    expect(outcome.error, contains('corrupt pack'));
    verify(() => projectRepo.delete('proj-2')).called(1);
  });

  test('reports success and does NOT roll back when initialization succeeds',
      () async {
    when(() => initService.initializeProject(
          projectId: any(named: 'projectId'),
          packFilePath: any(named: 'packFilePath'),
        )).thenAnswer((_) async => Ok<int, ServiceException>(42));

    final outcome = await initializeProjectFilesOrRollback(
      initService: initService,
      projectRepo: projectRepo,
      projectId: 'proj-3',
      packFilePath: 'C:/mods/baz.pack',
      schemaPath: 'C:/rpfm/schema',
    );

    expect(outcome.success, isTrue);
    expect(outcome.unitsImported, 42);
    verifyNever(() => projectRepo.delete(any()));
  });

  test('returns a successful outcome object via the success constructor', () {
    const outcome = ProjectInitOutcome.success(7);
    expect(outcome.success, isTrue);
    expect(outcome.unitsImported, 7);
    expect(outcome.failure, isNull);
  });
}
