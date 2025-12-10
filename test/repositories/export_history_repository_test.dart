import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late ExportHistoryRepository repository;
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          // Create minimal schema for testing
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              game_installation_id TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE export_history (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              languages TEXT NOT NULL,
              format TEXT NOT NULL,
              validated_only INTEGER NOT NULL DEFAULT 0,
              output_path TEXT NOT NULL,
              file_size INTEGER,
              entry_count INTEGER NOT NULL,
              exported_at INTEGER NOT NULL,
              FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
            )
          ''');

          // Insert test project
          await db.insert('projects', {
            'id': 'project-1',
            'name': 'Test Project',
            'game_installation_id': 'game-1',
            'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          });
        },
      ),
    );

    DatabaseService.setDatabase(database);
    repository = ExportHistoryRepository();
    await repository.ensureTableExists();
  });

  tearDown(() async {
    await database.close();
  });

  group('ExportHistoryRepository', () {
    test('should create export history record', () async {
      // Arrange
      final history = ExportHistory(
        id: 'export-1',
        projectId: 'project-1',
        languages: jsonEncode(['en', 'fr']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\test.pack',
        fileSize: 1024000,
        entryCount: 500,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      // Act
      final insertResult = await repository.insert(history);
      expect(insertResult.isOk, isTrue);

      // Assert
      final retrievedResult = await repository.getById(history.id);
      expect(retrievedResult.isOk, isTrue);
      final retrieved = retrievedResult.unwrap();
      expect(retrieved.id, history.id);
      expect(retrieved.projectId, history.projectId);
      expect(retrieved.format, ExportFormat.pack);
      expect(retrieved.entryCount, 500);
    });

    test('should get export history by project', () async {
      // Arrange
      final history1 = ExportHistory(
        id: 'export-1',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\test1.pack',
        entryCount: 100,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final history2 = ExportHistory(
        id: 'export-2',
        projectId: 'project-1',
        languages: jsonEncode(['fr']),
        format: ExportFormat.csv,
        validatedOnly: false,
        outputPath: 'C:\\Exports\\test2.csv',
        entryCount: 200,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repository.insert(history1);
      await repository.insert(history2);

      // Act
      final results = await repository.getByProject('project-1');

      // Assert
      expect(results, hasLength(2));
      expect(results.any((h) => h.id == 'export-1'), isTrue);
      expect(results.any((h) => h.id == 'export-2'), isTrue);
    });

    test('should get export history by format', () async {
      // Arrange
      final history1 = ExportHistory(
        id: 'export-1',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\test1.pack',
        entryCount: 100,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final history2 = ExportHistory(
        id: 'export-2',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:\\Exports\\test2.pack',
        entryCount: 200,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repository.insert(history1);
      await repository.insert(history2);

      // Act
      final results = await repository.getByFormat(ExportFormat.pack);

      // Assert
      expect(results, hasLength(2));
    });

    test('should get recent export history', () async {
      // Arrange
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final history1 = ExportHistory(
        id: 'export-1',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\test1.pack',
        entryCount: 100,
        exportedAt: now - 1000,
      );

      final history2 = ExportHistory(
        id: 'export-2',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:\\Exports\\test2.pack',
        entryCount: 200,
        exportedAt: now,
      );

      await repository.insert(history1);
      await repository.insert(history2);

      // Act
      final results = await repository.getRecent(limit: 1);

      // Assert
      expect(results, hasLength(1));
      expect(results.first.id, 'export-2'); // Most recent
    });

    test('should delete old export history', () async {
      // Arrange
      final now = DateTime.now();
      final oldTimestamp =
          now.subtract(const Duration(days: 40)).millisecondsSinceEpoch ~/
              1000;
      final recentTimestamp = now.millisecondsSinceEpoch ~/ 1000;

      final oldHistory = ExportHistory(
        id: 'export-old',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\old.pack',
        entryCount: 100,
        exportedAt: oldTimestamp,
      );

      final recentHistory = ExportHistory(
        id: 'export-recent',
        projectId: 'project-1',
        languages: jsonEncode(['en']),
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:\\Exports\\recent.pack',
        entryCount: 200,
        exportedAt: recentTimestamp,
      );

      await repository.insert(oldHistory);
      await repository.insert(recentHistory);

      // Act
      final deletedCount = await repository.deleteOlderThan(days: 30);

      // Assert
      expect(deletedCount, 1);
      final remainingResult = await repository.getAll();
      expect(remainingResult.isOk, isTrue);
      final remaining = remainingResult.unwrap();
      expect(remaining, hasLength(1));
      expect(remaining.first.id, 'export-recent');
    });

    test('should parse language list correctly', () async {
      // Arrange
      final history = ExportHistory(
        id: 'export-1',
        projectId: 'project-1',
        languages: jsonEncode(['en', 'fr', 'de']),
        format: ExportFormat.pack,
        validatedOnly: true,
        outputPath: 'C:\\Exports\\test.pack',
        entryCount: 100,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await repository.insert(history);

      // Act
      final retrievedResult = await repository.getById(history.id);

      // Assert
      expect(retrievedResult.isOk, isTrue);
      final retrieved = retrievedResult.unwrap();
      expect(retrieved.languagesList, hasLength(3));
      expect(retrieved.languagesList, contains('en'));
      expect(retrieved.languagesList, contains('fr'));
      expect(retrieved.languagesList, contains('de'));
    });
  });
}
