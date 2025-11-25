import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/file/change_detection_service.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

// Mock classes
class MockIFileService extends Mock implements IFileService {}

class MockModVersionRepository extends Mock implements ModVersionRepository {}

class MockLoggingService extends Mock implements LoggingService {}

void main() {
  // Initialize FFI for SQLite
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChangeDetectionServiceImpl - hasFileChanged', () {
    late ChangeDetectionServiceImpl service;
    late MockIFileService mockFileService;
    late MockModVersionRepository mockModVersionRepo;
    late MockLoggingService mockLogger;

    setUp(() {
      mockFileService = MockIFileService();
      mockModVersionRepo = MockModVersionRepository();
      mockLogger = MockLoggingService();

      // Configure mock logger to not throw on any call
      when(() => mockLogger.debug(any(), any())).thenReturn(null);
      when(() => mockLogger.info(any(), any())).thenReturn(null);
      when(() => mockLogger.error(any(), any(), any())).thenReturn(null);

      service = ChangeDetectionServiceImpl(
        fileService: mockFileService,
        modVersionRepository: mockModVersionRepo,
        logger: mockLogger,
      );
    });

    test('returns true when file hash differs from previous hash', () async {
      // Arrange
      const filePath = '/test/mod.pack';
      const previousHash = 'abc123';
      const currentHash = 'def456';

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer((_) async => const Ok(currentHash));

      // Act
      final result = await service.hasFileChanged(
        filePath: filePath,
        previousHash: previousHash,
      );

      // Assert
      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
      verify(() => mockFileService.calculateFileHash(filePath: filePath))
          .called(1);
    });

    test('returns false when file hash matches previous hash', () async {
      // Arrange
      const filePath = '/test/mod.pack';
      const previousHash = 'abc123';
      const currentHash = 'abc123';

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer((_) async => const Ok(currentHash));

      // Act
      final result = await service.hasFileChanged(
        filePath: filePath,
        previousHash: previousHash,
      );

      // Assert
      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('returns error when file hash calculation fails', () async {
      // Arrange
      const filePath = '/test/nonexistent.pack';
      const previousHash = 'abc123';

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer(
        (_) async => Err(
          FileNotFoundException('File not found', filePath),
        ),
      );

      // Act
      final result = await service.hasFileChanged(
        filePath: filePath,
        previousHash: previousHash,
      );

      // Assert
      expect(result.isErr, isTrue);
      expect(result.error, isA<ServiceException>());
    });
  });

  group('ChangeDetectionServiceImpl - detectChanges', () {
    late ChangeDetectionServiceImpl service;
    late MockIFileService mockFileService;
    late MockModVersionRepository mockModVersionRepo;
    late MockLoggingService mockLogger;

    setUp(() {
      mockFileService = MockIFileService();
      mockModVersionRepo = MockModVersionRepository();
      mockLogger = MockLoggingService();

      // Configure mock logger
      when(() => mockLogger.debug(any(), any())).thenReturn(null);
      when(() => mockLogger.info(any(), any())).thenReturn(null);
      when(() => mockLogger.error(any(), any(), any())).thenReturn(null);

      service = ChangeDetectionServiceImpl(
        fileService: mockFileService,
        modVersionRepository: mockModVersionRepo,
        logger: mockLogger,
      );
    });

    test('returns newFile result when no previous version exists', () async {
      // Arrange
      const modId = 'mod-123';
      const filePath = '/test/mod.pack';
      const currentHash = 'abc123';

      when(() => mockModVersionRepo.getCurrent(modId)).thenAnswer(
        (_) async => Err(
          TWMTDatabaseException('No current version found'),
        ),
      );

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer((_) async => const Ok(currentHash));

      // Act
      final result = await service.detectChanges(
        modId: modId,
        filePath: filePath,
      );

      // Assert
      expect(result.isOk, isTrue);
      final changeResult = result.value;
      expect(changeResult.hasChanged, isTrue);
      expect(changeResult.isNewFile, isTrue);
      expect(changeResult.newHash, equals(currentHash));
      expect(changeResult.oldHash, isNull);
    });

    test('returns changed result when file hash differs', () async {
      // Arrange
      const modId = 'mod-123';
      const filePath = '/test/mod.pack';
      const oldHash = 'abc123';
      const newHash = 'def456';

      final mockVersion = ModVersion(
        id: 'version-1',
        projectId: modId,
        versionString: oldHash,
        detectedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockModVersionRepo.getCurrent(modId))
          .thenAnswer((_) async => Ok(mockVersion));

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer((_) async => const Ok(newHash));

      // Act
      final result = await service.detectChanges(
        modId: modId,
        filePath: filePath,
      );

      // Assert
      expect(result.isOk, isTrue);
      final changeResult = result.value;
      expect(changeResult.hasChanged, isTrue);
      expect(changeResult.oldHash, equals(oldHash));
      expect(changeResult.newHash, equals(newHash));
    });

    test('returns noChange result when file hash matches', () async {
      // Arrange
      const modId = 'mod-123';
      const filePath = '/test/mod.pack';
      const hash = 'abc123';

      final mockVersion = ModVersion(
        id: 'version-1',
        projectId: modId,
        versionString: hash,
        detectedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockModVersionRepo.getCurrent(modId))
          .thenAnswer((_) async => Ok(mockVersion));

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer((_) async => const Ok(hash));

      // Act
      final result = await service.detectChanges(
        modId: modId,
        filePath: filePath,
      );

      // Assert
      expect(result.isOk, isTrue);
      final changeResult = result.value;
      expect(changeResult.hasChanged, isFalse);
      expect(changeResult.oldHash, equals(hash));
      expect(changeResult.newHash, equals(hash));
    });

    test('returns error when hash calculation fails', () async {
      // Arrange
      const modId = 'mod-123';
      const filePath = '/test/nonexistent.pack';

      when(() => mockFileService.calculateFileHash(filePath: filePath))
          .thenAnswer(
        (_) async => Err(
          FileNotFoundException('File not found', filePath),
        ),
      );

      // Act
      final result = await service.detectChanges(
        modId: modId,
        filePath: filePath,
      );

      // Assert
      expect(result.isErr, isTrue);
      expect(result.error, isA<ServiceException>());
    });
  });

  group('ChangeDetectionServiceImpl - markTranslationsObsolete', () {
    late ChangeDetectionServiceImpl service;
    late MockIFileService mockFileService;
    late MockModVersionRepository mockModVersionRepo;
    late MockLoggingService mockLogger;
    late Database database;
    late Directory tempDir;

    setUp(() async {
      mockFileService = MockIFileService();
      mockModVersionRepo = MockModVersionRepository();
      mockLogger = MockLoggingService();

      // Configure mock logger
      when(() => mockLogger.debug(any(), any())).thenReturn(null);
      when(() => mockLogger.info(any(), any())).thenReturn(null);
      when(() => mockLogger.error(any(), any(), any())).thenReturn(null);

      // Create a temporary database
      tempDir = await Directory.systemTemp.createTemp('change_detection_test_');
      final dbPath = '${tempDir.path}/test.db';
      database = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE translation_units (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                key TEXT NOT NULL,
                source_text TEXT NOT NULL,
                is_obsolete INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      // Initialize DatabaseService with our test database
      DatabaseService.setDatabase(database);

      service = ChangeDetectionServiceImpl(
        fileService: mockFileService,
        modVersionRepository: mockModVersionRepo,
        logger: mockLogger,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('marks all translations obsolete for project when versionId is null',
        () async {
      // Arrange
      const modId = 'mod-123';
      await database.insert('translation_units', {
        'id': 'unit-1',
        'project_id': modId,
        'key': 'key1',
        'source_text': 'Text 1',
        'is_obsolete': 0,
        'updated_at': 1000,
      });
      await database.insert('translation_units', {
        'id': 'unit-2',
        'project_id': modId,
        'key': 'key2',
        'source_text': 'Text 2',
        'is_obsolete': 0,
        'updated_at': 1000,
      });

      // Act
      final result = await service.markTranslationsObsolete(modId: modId);

      // Assert
      expect(result.isOk, isTrue);

      final units = await database.query('translation_units');
      expect(units.length, equals(2));
      expect(units[0]['is_obsolete'], equals(1));
      expect(units[1]['is_obsolete'], equals(1));
    });

    test('does not affect translations from other projects', () async {
      // Arrange
      const modId = 'mod-123';
      const otherModId = 'mod-456';

      await database.insert('translation_units', {
        'id': 'unit-1',
        'project_id': modId,
        'key': 'key1',
        'source_text': 'Text 1',
        'is_obsolete': 0,
        'updated_at': 1000,
      });
      await database.insert('translation_units', {
        'id': 'unit-2',
        'project_id': otherModId,
        'key': 'key2',
        'source_text': 'Text 2',
        'is_obsolete': 0,
        'updated_at': 1000,
      });

      // Act
      final result = await service.markTranslationsObsolete(modId: modId);

      // Assert
      expect(result.isOk, isTrue);

      final units = await database.query('translation_units');
      expect(units.length, equals(2));

      final modUnits = units.where((u) => u['project_id'] == modId).toList();
      expect(modUnits[0]['is_obsolete'], equals(1));

      final otherUnits =
          units.where((u) => u['project_id'] == otherModId).toList();
      expect(otherUnits[0]['is_obsolete'], equals(0));
    });
  });

  group('ChangeDetectionServiceImpl - generateChangeReport', () {
    late ChangeDetectionServiceImpl service;
    late MockIFileService mockFileService;
    late MockModVersionRepository mockModVersionRepo;
    late MockLoggingService mockLogger;
    late Database database;
    late Directory tempDir;

    setUp(() async {
      mockFileService = MockIFileService();
      mockModVersionRepo = MockModVersionRepository();
      mockLogger = MockLoggingService();

      // Configure mock logger
      when(() => mockLogger.debug(any(), any())).thenReturn(null);
      when(() => mockLogger.info(any(), any())).thenReturn(null);
      when(() => mockLogger.error(any(), any(), any())).thenReturn(null);

      // Create a temporary database
      tempDir = await Directory.systemTemp.createTemp('change_detection_test_');
      final dbPath = '${tempDir.path}/test.db';
      database = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE mod_versions (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                version_string TEXT NOT NULL,
                detected_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE mod_version_changes (
                id TEXT PRIMARY KEY,
                version_id TEXT NOT NULL,
                unit_key TEXT NOT NULL,
                change_type TEXT NOT NULL,
                old_source_text TEXT,
                new_source_text TEXT,
                detected_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      DatabaseService.setDatabase(database);

      service = ChangeDetectionServiceImpl(
        fileService: mockFileService,
        modVersionRepository: mockModVersionRepo,
        logger: mockLogger,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns list of FileChange objects for version changes', () async {
      // Arrange
      const modId = 'mod-123';
      const oldVersionId = 'version-1';
      const newVersionId = 'version-2';

      final now = DateTime.now();
      final nowUnix = now.millisecondsSinceEpoch ~/ 1000;

      final oldVersion = ModVersion(
        id: oldVersionId,
        projectId: modId,
        versionString: '1.0.0',
        detectedAt: nowUnix,
      );

      final newVersion = ModVersion(
        id: newVersionId,
        projectId: modId,
        versionString: '2.0.0',
        detectedAt: nowUnix,
      );

      when(() => mockModVersionRepo.getById(oldVersionId))
          .thenAnswer((_) async => Ok(oldVersion));
      when(() => mockModVersionRepo.getById(newVersionId))
          .thenAnswer((_) async => Ok(newVersion));

      // Insert test changes
      await database.insert('mod_version_changes', {
        'id': 'change-1',
        'version_id': newVersionId,
        'unit_key': 'key1',
        'change_type': 'added',
        'old_source_text': null,
        'new_source_text': 'New text',
        'detected_at': nowUnix,
      });

      await database.insert('mod_version_changes', {
        'id': 'change-2',
        'version_id': newVersionId,
        'unit_key': 'key2',
        'change_type': 'modified',
        'old_source_text': 'Old text',
        'new_source_text': 'Modified text',
        'detected_at': nowUnix,
      });

      await database.insert('mod_version_changes', {
        'id': 'change-3',
        'version_id': newVersionId,
        'unit_key': 'key3',
        'change_type': 'deleted',
        'old_source_text': 'Deleted text',
        'new_source_text': null,
        'detected_at': nowUnix,
      });

      // Act
      final result = await service.generateChangeReport(
        modId: modId,
        oldVersionId: oldVersionId,
        newVersionId: newVersionId,
      );

      // Assert
      expect(result.isOk, isTrue);
      final changes = result.value;
      expect(changes.length, equals(3));

      // Check added change
      final addedChange = changes.firstWhere((c) => c.filePath == 'key1');
      expect(addedChange.isAdded, isTrue);
      expect(addedChange.oldHash, isNull);
      expect(addedChange.newHash, isNotNull);

      // Check modified change
      final modifiedChange = changes.firstWhere((c) => c.filePath == 'key2');
      expect(modifiedChange.isModified, isTrue);
      expect(modifiedChange.oldHash, isNotNull);
      expect(modifiedChange.newHash, isNotNull);

      // Check deleted change
      final deletedChange = changes.firstWhere((c) => c.filePath == 'key3');
      expect(deletedChange.isDeleted, isTrue);
      expect(deletedChange.oldHash, isNotNull);
      expect(deletedChange.newHash, isNull);
    });

    test('returns error when old version not found', () async {
      // Arrange
      const modId = 'mod-123';
      const oldVersionId = 'version-1';
      const newVersionId = 'version-2';

      when(() => mockModVersionRepo.getById(oldVersionId)).thenAnswer(
        (_) async => Err(TWMTDatabaseException('Version not found')),
      );

      // Act
      final result = await service.generateChangeReport(
        modId: modId,
        oldVersionId: oldVersionId,
        newVersionId: newVersionId,
      );

      // Assert
      expect(result.isErr, isTrue);
      expect(result.error, isA<ServiceException>());
    });

    test('returns error when new version not found', () async {
      // Arrange
      const modId = 'mod-123';
      const oldVersionId = 'version-1';
      const newVersionId = 'version-2';

      final oldVersion = ModVersion(
        id: oldVersionId,
        projectId: modId,
        versionString: '1.0.0',
        detectedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockModVersionRepo.getById(oldVersionId))
          .thenAnswer((_) async => Ok(oldVersion));
      when(() => mockModVersionRepo.getById(newVersionId)).thenAnswer(
        (_) async => Err(TWMTDatabaseException('Version not found')),
      );

      // Act
      final result = await service.generateChangeReport(
        modId: modId,
        oldVersionId: oldVersionId,
        newVersionId: newVersionId,
      );

      // Assert
      expect(result.isErr, isTrue);
      expect(result.error, isA<ServiceException>());
    });

    test('returns empty list when no changes exist', () async {
      // Arrange
      const modId = 'mod-123';
      const oldVersionId = 'version-1';
      const newVersionId = 'version-2';

      final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final oldVersion = ModVersion(
        id: oldVersionId,
        projectId: modId,
        versionString: '1.0.0',
        detectedAt: nowUnix,
      );

      final newVersion = ModVersion(
        id: newVersionId,
        projectId: modId,
        versionString: '2.0.0',
        detectedAt: nowUnix,
      );

      when(() => mockModVersionRepo.getById(oldVersionId))
          .thenAnswer((_) async => Ok(oldVersion));
      when(() => mockModVersionRepo.getById(newVersionId))
          .thenAnswer((_) async => Ok(newVersion));

      // Act
      final result = await service.generateChangeReport(
        modId: modId,
        oldVersionId: oldVersionId,
        newVersionId: newVersionId,
      );

      // Assert
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });
}
