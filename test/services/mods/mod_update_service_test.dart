import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/mods/mod_update_service_impl.dart';
import 'package:twmt/services/steam/i_steam_workshop_service.dart';
import 'package:twmt/services/steam/models/workshop_item_details.dart';
import 'package:twmt/services/steam/models/workshop_item_update.dart';

class MockSteamWorkshopService extends Mock implements ISteamWorkshopService {}

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockModVersionRepository extends Mock implements ModVersionRepository {}

void main() {
  late ModUpdateServiceImpl service;
  late MockSteamWorkshopService mockWorkshopService;
  late MockProjectRepository mockProjectRepository;
  late MockModVersionRepository mockModVersionRepository;

  setUpAll(() {
    registerFallbackValue(Project(
      id: 'test-id',
      name: 'Test Project',
      gameInstallationId: 'game-id',
      createdAt: 0,
      updatedAt: 0,
    ));
    registerFallbackValue(ModVersion(
      id: 'version-id',
      projectId: 'project-id',
      versionString: '1.0.0',
      detectedAt: 0,
    ));
  });

  setUp(() {
    mockWorkshopService = MockSteamWorkshopService();
    mockProjectRepository = MockProjectRepository();
    mockModVersionRepository = MockModVersionRepository();

    service = ModUpdateServiceImpl(
      workshopService: mockWorkshopService,
      projectRepository: mockProjectRepository,
      modVersionRepository: mockModVersionRepository,
    );
  });

  group('ModUpdateService - checkAllModsForUpdates', () {
    test('should return empty list when no projects exist', () async {
      // Arrange
      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => const Ok([]));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
    });

    test('should return empty list when no projects have Steam Workshop IDs', () async {
      // Arrange
      final projects = [
        Project(
          id: 'project-1',
          name: 'Local Mod',
          gameInstallationId: 'game-1',
          modSteamId: null,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => Ok(projects));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
    });

    test('should check Steam projects for updates successfully', () async {
      // Arrange
      final now = DateTime.now();
      final oldTimestamp = now.subtract(const Duration(days: 30));
      final newTimestamp = now;

      final projects = [
        Project(
          id: 'project-1',
          name: 'Steam Mod 1',
          gameInstallationId: 'game-1',
          modSteamId: '1111111111',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      final currentVersion = ModVersion(
        id: 'version-1',
        projectId: 'project-1',
        versionString: '1.0.0',
        steamUpdateTimestamp: oldTimestamp.millisecondsSinceEpoch ~/ 1000,
        detectedAt: 0,
      );

      final workshopUpdates = [
        WorkshopItemUpdate(
          workshopId: '1111111111',
          modName: 'Steam Mod 1',
          lastKnownUpdate: oldTimestamp,
          latestUpdate: newTimestamp,
          hasUpdate: true,
        ),
      ];

      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => Ok(projects));
      when(() => mockModVersionRepository.getCurrent('project-1'))
          .thenAnswer((_) async => Ok(currentVersion));
      when(() => mockWorkshopService.checkForUpdates(
            workshopIds: any(named: 'workshopIds'),
          )).thenAnswer((_) async => Ok(workshopUpdates));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value.length, 1);
      expect(result.value.first.hasUpdate, true);
      expect(result.value.first.modName, 'Steam Mod 1');
    });

    test('should handle projects without Steam update timestamps', () async {
      // Arrange
      final projects = [
        Project(
          id: 'project-1',
          name: 'Steam Mod',
          gameInstallationId: 'game-1',
          modSteamId: '1111111111',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      final currentVersion = ModVersion(
        id: 'version-1',
        projectId: 'project-1',
        versionString: '1.0.0',
        steamUpdateTimestamp: null,
        detectedAt: 0,
      );

      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => Ok(projects));
      when(() => mockModVersionRepository.getCurrent('project-1'))
          .thenAnswer((_) async => Ok(currentVersion));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
    });

    test('should return error when project repository fails', () async {
      // Arrange
      when(() => mockProjectRepository.getAll()).thenAnswer(
          (_) async => Err(TWMTDatabaseException('Database error')));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
      expect(result.error.message, contains('Failed to fetch projects'));
    });

    test('should return error when Steam Workshop check fails', () async {
      // Arrange
      final projects = [
        Project(
          id: 'project-1',
          name: 'Steam Mod',
          gameInstallationId: 'game-1',
          modSteamId: '1111111111',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      final currentVersion = ModVersion(
        id: 'version-1',
        projectId: 'project-1',
        versionString: '1.0.0',
        steamUpdateTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        detectedAt: 0,
      );

      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => Ok(projects));
      when(() => mockModVersionRepository.getCurrent('project-1'))
          .thenAnswer((_) async => Ok(currentVersion));
      when(() => mockWorkshopService.checkForUpdates(
            workshopIds: any(named: 'workshopIds'),
          )).thenAnswer((_) async =>
              Err(SteamException('Steam API error', workshopId: '1111111111')));

      // Act
      final result = await service.checkAllModsForUpdates();

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
      expect(result.error.message, contains('Failed to check Steam Workshop'));
    });
  });

  group('ModUpdateService - checkModForUpdate', () {
    test('should check single mod for update successfully', () async {
      // Arrange
      const projectId = 'project-1';
      final oldTimestamp = DateTime(2024, 1, 1);
      final newTimestamp = DateTime(2024, 6, 1);

      final project = Project(
        id: projectId,
        name: 'Test Mod',
        gameInstallationId: 'game-1',
        modSteamId: '1111111111',
        createdAt: 0,
        updatedAt: 0,
      );

      final currentVersion = ModVersion(
        id: 'version-1',
        projectId: projectId,
        versionString: '1.0.0',
        steamUpdateTimestamp: oldTimestamp.millisecondsSinceEpoch ~/ 1000,
        detectedAt: 0,
      );

      final workshopDetails = WorkshopItemDetails(
        publishedFileId: '1111111111',
        title: 'Test Mod',
        timeUpdated: newTimestamp,
        fileSize: 1024000,
      );

      when(() => mockProjectRepository.getById(projectId))
          .thenAnswer((_) async => Ok(project));
      when(() => mockModVersionRepository.getCurrent(projectId))
          .thenAnswer((_) async => Ok(currentVersion));
      when(() => mockWorkshopService.getWorkshopItemDetails(
            workshopId: '1111111111',
          )).thenAnswer((_) async => Ok(workshopDetails));

      // Act
      final result = await service.checkModForUpdate(projectId: projectId);

      // Assert
      expect(result.isOk, true);
      expect(result.value.hasUpdate, true);
      expect(result.value.modName, 'Test Mod');
      expect(result.value.currentVersionString, '1.0.0');
    });

    test('should return error for project without Steam Workshop ID', () async {
      // Arrange
      const projectId = 'project-1';

      final project = Project(
        id: projectId,
        name: 'Local Mod',
        gameInstallationId: 'game-1',
        modSteamId: null,
        createdAt: 0,
        updatedAt: 0,
      );

      when(() => mockProjectRepository.getById(projectId))
          .thenAnswer((_) async => Ok(project));

      // Act
      final result = await service.checkModForUpdate(projectId: projectId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
      expect(result.error.message, contains('does not have a Steam Workshop ID'));
    });

    test('should return error when project not found', () async {
      // Arrange
      const projectId = 'nonexistent';

      when(() => mockProjectRepository.getById(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('Project not found')));

      // Act
      final result = await service.checkModForUpdate(projectId: projectId);

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
      expect(result.error.message, contains('Project not found'));
    });
  });

  group('ModUpdateService - trackModUpdate', () {
    test('should track mod update successfully', () async {
      // Arrange
      const projectId = 'project-1';
      const newVersionString = '2.0.0';
      final updateTime = DateTime(2024, 6, 1);

      final project = Project(
        id: projectId,
        name: 'Test Mod',
        gameInstallationId: 'game-1',
        modSteamId: '1111111111',
        createdAt: 0,
        updatedAt: 0,
      );

      final workshopDetails = WorkshopItemDetails(
        publishedFileId: '1111111111',
        title: 'Test Mod',
        timeUpdated: updateTime,
        fileSize: 1024000,
      );

      when(() => mockProjectRepository.getById(projectId))
          .thenAnswer((_) async => Ok(project));
      when(() => mockWorkshopService.getWorkshopItemDetails(
            workshopId: '1111111111',
          )).thenAnswer((_) async => Ok(workshopDetails));
      when(() => mockModVersionRepository.insert(any()))
          .thenAnswer((invocation) async {
        final version = invocation.positionalArguments[0] as ModVersion;
        return Ok(version);
      });
      when(() => mockModVersionRepository.markAsCurrent(any()))
          .thenAnswer((invocation) async {
        final versionId = invocation.positionalArguments[0] as String;
        return Ok(ModVersion(
          id: versionId,
          projectId: projectId,
          versionString: newVersionString,
          isCurrent: true,
          detectedAt: 0,
        ));
      });
      when(() => mockProjectRepository.update(any()))
          .thenAnswer((invocation) async {
        final project = invocation.positionalArguments[0] as Project;
        return Ok(project);
      });

      // Act
      final result = await service.trackModUpdate(
        projectId: projectId,
        newVersionString: newVersionString,
      );

      // Assert
      expect(result.isOk, true);
      verify(() => mockModVersionRepository.insert(any())).called(1);
      verify(() => mockModVersionRepository.markAsCurrent(any())).called(1);
      verify(() => mockProjectRepository.update(any())).called(1);
    });

    test('should return error when project not found', () async {
      // Arrange
      const projectId = 'nonexistent';
      const newVersionString = '2.0.0';

      when(() => mockProjectRepository.getById(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('Project not found')));

      // Act
      final result = await service.trackModUpdate(
        projectId: projectId,
        newVersionString: newVersionString,
      );

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
    });

    test('should return error when version insertion fails', () async {
      // Arrange
      const projectId = 'project-1';
      const newVersionString = '2.0.0';
      final updateTime = DateTime(2024, 6, 1);

      final project = Project(
        id: projectId,
        name: 'Test Mod',
        gameInstallationId: 'game-1',
        modSteamId: '1111111111',
        createdAt: 0,
        updatedAt: 0,
      );

      final workshopDetails = WorkshopItemDetails(
        publishedFileId: '1111111111',
        title: 'Test Mod',
        timeUpdated: updateTime,
        fileSize: 1024000,
      );

      when(() => mockProjectRepository.getById(projectId))
          .thenAnswer((_) async => Ok(project));
      when(() => mockWorkshopService.getWorkshopItemDetails(
            workshopId: '1111111111',
          )).thenAnswer((_) async => Ok(workshopDetails));
      when(() => mockModVersionRepository.insert(any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('Insert failed')));

      // Act
      final result = await service.trackModUpdate(
        projectId: projectId,
        newVersionString: newVersionString,
      );

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<ServiceException>());
      expect(result.error.message, contains('Failed to insert new mod version'));
    });
  });

  group('ModUpdateService - getPendingUpdates', () {
    test('should return only projects with updates', () async {
      // Arrange
      final now = DateTime.now();
      final oldTimestamp = now.subtract(const Duration(days: 30));

      final projects = [
        Project(
          id: 'project-1',
          name: 'Mod with Update',
          gameInstallationId: 'game-1',
          modSteamId: '1111111111',
          createdAt: 0,
          updatedAt: 0,
        ),
        Project(
          id: 'project-2',
          name: 'Mod without Update',
          gameInstallationId: 'game-1',
          modSteamId: '2222222222',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      final version1 = ModVersion(
        id: 'version-1',
        projectId: 'project-1',
        versionString: '1.0.0',
        steamUpdateTimestamp: oldTimestamp.millisecondsSinceEpoch ~/ 1000,
        detectedAt: 0,
      );

      final version2 = ModVersion(
        id: 'version-2',
        projectId: 'project-2',
        versionString: '1.0.0',
        steamUpdateTimestamp: now.millisecondsSinceEpoch ~/ 1000,
        detectedAt: 0,
      );

      final workshopUpdates = [
        WorkshopItemUpdate(
          workshopId: '1111111111',
          modName: 'Mod with Update',
          lastKnownUpdate: oldTimestamp,
          latestUpdate: now,
          hasUpdate: true,
        ),
        WorkshopItemUpdate(
          workshopId: '2222222222',
          modName: 'Mod without Update',
          lastKnownUpdate: now,
          latestUpdate: now,
          hasUpdate: false,
        ),
      ];

      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => Ok(projects));
      when(() => mockModVersionRepository.getCurrent('project-1'))
          .thenAnswer((_) async => Ok(version1));
      when(() => mockModVersionRepository.getCurrent('project-2'))
          .thenAnswer((_) async => Ok(version2));
      when(() => mockWorkshopService.checkForUpdates(
            workshopIds: any(named: 'workshopIds'),
          )).thenAnswer((_) async => Ok(workshopUpdates));

      // Act
      final result = await service.getPendingUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value.length, 1);
      expect(result.value.first.modName, 'Mod with Update');
      expect(result.value.first.hasUpdate, true);
    });

    test('should return empty list when no updates available', () async {
      // Arrange
      when(() => mockProjectRepository.getAll())
          .thenAnswer((_) async => const Ok([]));

      // Act
      final result = await service.getPendingUpdates();

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
    });
  });
}
